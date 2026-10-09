import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/addons/application/addon_install_controller.dart';
import '../../core/repositories/application/repository_registry.dart';
import '../../core/repositories/application/repository_store_controller.dart';
import '../../core/repositories/domain/repository_source.dart';
import '../../core/repositories/infrastructure/repository_descriptor_parser.dart';
import 'repository_catalog_page.dart';

class StorePage extends StatefulWidget {
  const StorePage({
    required this.repositoryRegistry,
    required this.repositoryStoreController,
    required this.addonInstallController,
    super.key,
  });

  final RepositoryRegistry repositoryRegistry;
  final RepositoryStoreController repositoryStoreController;
  final AddonInstallController addonInstallController;

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  static const XTypeGroup _zipTypeGroup = XTypeGroup(
    label: 'Kodi addon ZIP',
    extensions: <String>['zip'],
    mimeTypes: <String>['application/zip', 'application/x-zip-compressed'],
  );

  bool _syncScheduled = false;
  bool _installingZip = false;

  @override
  void initState() {
    super.initState();
    widget.repositoryRegistry.addListener(_handleRegistryChanged);
    _scheduleIdleSync();
  }

  @override
  void dispose() {
    widget.repositoryRegistry.removeListener(_handleRegistryChanged);
    super.dispose();
  }

  void _handleRegistryChanged() {
    _scheduleIdleSync();
  }

  void _scheduleIdleSync() {
    if (_syncScheduled) {
      return;
    }
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) {
        return;
      }
      _syncIdleSources();
    });
  }

  void _syncIdleSources() {
    for (final source in widget.repositoryRegistry.sources) {
      final state = widget.repositoryStoreController.stateFor(source.uri);
      if (source.enabled && state.status == RepositorySyncStatus.idle) {
        unawaited(widget.repositoryStoreController.synchronize(source));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Loja'),
        actions: [
          IconButton(
            tooltip: 'Instalar addon por ZIP',
            onPressed: _installingZip ? null : () => unawaited(_installZip()),
            icon: _installingZip
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.folder_zip_rounded),
          ),
          IconButton(
            tooltip: 'Atualizar todos',
            onPressed: () => unawaited(
              widget.repositoryStoreController.synchronizeAll(
                widget.repositoryRegistry.sources,
              ),
            ),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddRepositoryDialog,
        icon: const Icon(Icons.add_link_rounded),
        label: const Text('Adicionar repositório'),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          widget.repositoryRegistry,
          widget.repositoryStoreController,
        ]),
        builder: (context, _) {
          final repositories = widget.repositoryRegistry.sources;
          if (repositories.isEmpty) {
            return const _EmptyStore();
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
            itemCount: repositories.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final repository = repositories[index];
              final state =
                  widget.repositoryStoreController.stateFor(repository.uri);
              return _RepositoryCard(
                repository: repository,
                state: state,
                onOpen: state.catalog == null
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => RepositoryCatalogPage(
                              catalog: state.catalog!,
                              repositoryStoreController:
                                  widget.repositoryStoreController,
                              addonInstallController:
                                  widget.addonInstallController,
                            ),
                          ),
                        );
                      },
                onRefresh: () => unawaited(
                  widget.repositoryStoreController.synchronize(repository),
                ),
                onEnabledChanged: (value) => unawaited(
                  widget.repositoryRegistry.setEnabled(repository.uri, value),
                ),
                onRemove: () => unawaited(_remove(repository)),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _installZip() async {
    final selected = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_zipTypeGroup],
    );
    if (selected == null || !mounted) {
      return;
    }

    setState(() => _installingZip = true);
    try {
      final bytes = await selected.readAsBytes();
      final result = await widget.addonInstallController.installLocalPackage(
        bytes: bytes,
        catalogs: widget.repositoryStoreController.catalogs,
      );

      var repositoryRegistered = false;
      if (result.addon.manifest.isRepository) {
        repositoryRegistered = await _registerRepositoryAddon(result.addon.installPath);
      }

      if (!mounted) return;
      if (!result.dependenciesResolved) {
        await _showDependencyIssues(
          addonName: result.addon.manifest.name,
          issues: result.dependencyPlan.issues
              .map((issue) => '${issue.addonId}: ${issue.message}')
              .toList(growable: false),
        );
        return;
      }

      final repositorySuffix = repositoryRegistered
          ? ' O repositório também foi adicionado à Loja.'
          : '';
      _showMessage(
        '${result.addon.manifest.name} instalado com sucesso.$repositorySuffix',
      );
    } on Object catch (error) {
      if (!mounted) return;
      _showError('Falha ao instalar o ZIP: $error');
    } finally {
      if (mounted) {
        setState(() => _installingZip = false);
      }
    }
  }

  Future<bool> _registerRepositoryAddon(String installPath) async {
    final manifestFile = File(p.join(installPath, 'addon.xml'));
    if (!await manifestFile.exists()) {
      return false;
    }

    final descriptor = const RepositoryDescriptorParser().parse(
      await manifestFile.readAsString(),
    );
    var added = false;
    for (final endpoint in descriptor.endpoints) {
      final alreadyRegistered = widget.repositoryRegistry.sources.any(
        (source) => source.uri == endpoint.infoUri,
      );
      if (alreadyRegistered) {
        continue;
      }
      await widget.repositoryRegistry.addResolvedEndpoint(
        infoUri: endpoint.infoUri,
        packageBaseUri: endpoint.dataUri,
        checksumUri: endpoint.checksumUri,
        name: descriptor.name,
      );
      added = true;
    }
    return added;
  }

  Future<void> _showDependencyIssues({
    required String addonName,
    required List<String> issues,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$addonName foi instalado, mas precisa de dependências'),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'O ZIP foi instalado, porém estas dependências obrigatórias não foram encontradas nos repositórios ativos:',
              ),
              const SizedBox(height: 12),
              for (final issue in issues)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• $issue'),
                ),
              const SizedBox(height: 8),
              const Text(
                'Adicione ou atualize o repositório que fornece essas dependências e reinstale o addon.',
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _remove(RepositorySource repository) async {
    await widget.repositoryRegistry.remove(repository.uri);
    widget.repositoryStoreController.forget(repository.uri);
  }

  Future<void> _showAddRepositoryDialog() async {
    final rawUrl = await showDialog<String>(
      context: context,
      builder: (_) => _AddRepositoryDialog(
        existingUris: widget.repositoryRegistry.sources
            .map((source) => source.uri)
            .toSet(),
      ),
    );
    if (!mounted || rawUrl == null) {
      return;
    }

    try {
      await widget.repositoryRegistry.addUrl(rawUrl);
    } on FormatException catch (error) {
      if (!mounted) return;
      _showError(error.message.toString());
    } on Object catch (error) {
      if (!mounted) return;
      _showError('Não foi possível salvar o repositório: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
  }
}

class _AddRepositoryDialog extends StatefulWidget {
  const _AddRepositoryDialog({required this.existingUris});

  final Set<Uri> existingUris;

  @override
  State<_AddRepositoryDialog> createState() => _AddRepositoryDialogState();
}

class _AddRepositoryDialogState extends State<_AddRepositoryDialog> {
  late final TextEditingController _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    final uri = Uri.tryParse(value);

    String? error;
    if (value.isEmpty) {
      error = 'Informe a URL do repositório.';
    } else if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      error = 'Use uma URL HTTP ou HTTPS válida.';
    } else if (widget.existingUris.contains(uri)) {
      error = 'Este repositório já foi adicionado.';
    }

    if (error != null) {
      setState(() => _errorText = error);
      return;
    }

    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Adicionar repositório'),
      content: SizedBox(
        width: 560,
        child: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onChanged: (_) {
            if (_errorText != null) {
              setState(() => _errorText = null);
            }
          },
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'URL do repositório',
            hintText: 'https://exemplo.com/repository/',
            helperText:
                'Aceita descriptor addon.xml ou índice addons.xml/addons.xml.gz.',
            errorText: _errorText,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}

class _EmptyStore extends StatelessWidget {
  const _EmptyStore();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.storefront_rounded,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                'Nenhum repositório configurado',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Adicione a URL de um repositório ou use o ícone de ZIP na barra superior para instalar um addon/repository Kodi local.',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepositoryCard extends StatelessWidget {
  const _RepositoryCard({
    required this.repository,
    required this.state,
    required this.onEnabledChanged,
    required this.onRefresh,
    required this.onRemove,
    required this.onOpen,
  });

  final RepositorySource repository;
  final RepositorySyncState state;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onRefresh;
  final VoidCallback onRemove;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final catalog = state.catalog;
    final title = catalog?.repositoryName ?? repository.displayName;

    return Card(
      child: ListTile(
        onTap: onOpen,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: _StatusIcon(state: state),
        title: Text(title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(repository.uri.toString()),
            const SizedBox(height: 5),
            Text(_statusText(state)),
            if (state.errorMessage case final error?) ...[
              const SizedBox(height: 4),
              Text(
                error,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Atualizar',
              onPressed: repository.enabled &&
                      state.status != RepositorySyncStatus.syncing
                  ? onRefresh
                  : null,
              icon: const Icon(Icons.refresh_rounded),
            ),
            Switch(
              value: repository.enabled,
              onChanged: onEnabledChanged,
            ),
            IconButton(
              tooltip: 'Remover',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
            if (onOpen != null) const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }

  String _statusText(RepositorySyncState state) {
    switch (state.status) {
      case RepositorySyncStatus.idle:
        return repository.enabled
            ? 'Aguardando sincronização.'
            : 'Repositório desativado.';
      case RepositorySyncStatus.syncing:
        return 'Sincronizando índice…';
      case RepositorySyncStatus.ready:
        final catalog = state.catalog!;
        final skipped = catalog.skippedAddons == 0
            ? ''
            : ' • ${catalog.skippedAddons} ignorado(s)';
        return '${catalog.addons.length} addon(s)$skipped';
      case RepositorySyncStatus.failed:
        return state.catalog == null
            ? 'Falha na sincronização.'
            : 'Falha ao atualizar; mostrando o último índice carregado.';
    }
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.state});

  final RepositorySyncState state;

  @override
  Widget build(BuildContext context) {
    switch (state.status) {
      case RepositorySyncStatus.syncing:
        return const SizedBox.square(
          dimension: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        );
      case RepositorySyncStatus.ready:
        return const Icon(Icons.cloud_done_rounded);
      case RepositorySyncStatus.failed:
        return Icon(
          Icons.cloud_off_rounded,
          color: Theme.of(context).colorScheme.error,
        );
      case RepositorySyncStatus.idle:
        return const Icon(Icons.account_tree_rounded);
    }
  }
}
