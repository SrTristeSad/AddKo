import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/addons/application/addon_install_controller.dart';
import '../../core/addons/domain/kodi_version.dart';
import '../../core/repositories/application/repository_registry.dart';
import '../../core/repositories/application/repository_store_controller.dart';
import '../../core/repositories/domain/repository_descriptor.dart';
import '../../core/repositories/domain/repository_source.dart';
import '../../core/repositories/infrastructure/repository_descriptor_parser.dart';
import '../../core/ui/kodi_text.dart';
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

  static final KodiVersion _hostKodiVersion = KodiVersion('21.0.0');

  bool _installingZip = false;
  bool _syncScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.repositoryRegistry.addListener(_onRegistryChanged);
    _scheduleIdleSync();
  }

  @override
  void dispose() {
    widget.repositoryRegistry.removeListener(_onRegistryChanged);
    super.dispose();
  }

  void _onRegistryChanged() {
    _scheduleIdleSync();
  }

  void _scheduleIdleSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      for (final source in widget.repositoryRegistry.sources) {
        final state = widget.repositoryStoreController.stateFor(source.uri);
        if (source.enabled && state.status == RepositorySyncStatus.idle) {
          unawaited(widget.repositoryStoreController.synchronize(source));
        }
      }
    });
  }

  Future<void> _addRepository() async {
    final rawUrl = await showDialog<String>(
      context: context,
      builder: (_) => _AddRepositoryDialog(
        existingUris: widget.repositoryRegistry.sources
            .map((source) => source.uri)
            .toSet(),
      ),
    );

    if (!mounted || rawUrl == null) return;

    try {
      await widget.repositoryRegistry.addUrl(rawUrl);
    } on FormatException catch (error) {
      if (mounted) _showError(error.message.toString());
    } on Object catch (error) {
      if (mounted) _showError('Não foi possível adicionar a fonte: $error');
    }
  }

  Future<void> _installZip() async {
    final selected = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_zipTypeGroup],
    );
    if (selected == null || !mounted) return;

    setState(() => _installingZip = true);
    try {
      await widget.repositoryStoreController.ensureKodiSystemCatalog();
      final result = await widget.addonInstallController.installLocalPackage(
        bytes: await selected.readAsBytes(),
        catalogs: widget.repositoryStoreController.catalogs,
      );

      var registeredRepository = false;
      if (result.addon.manifest.isRepository) {
        registeredRepository = await _registerRepositoryAddon(
          result.addon.installPath,
        );
      }

      if (!mounted) return;

      if (!result.dependenciesResolved) {
        final issues = result.dependencyPlan.issues
            .map((issue) => '${issue.addonId}: ${issue.message}')
            .join('\n');
        _showError(
          '${result.addon.manifest.name} foi instalado, mas ainda faltam dependências:\n$issues',
        );
        return;
      }

      _showMessage(
        registeredRepository
            ? '${result.addon.manifest.name} instalado e adicionado à Loja.'
            : '${result.addon.manifest.name} instalado com sucesso.',
      );
    } on Object catch (error) {
      if (mounted) _showError('Falha ao instalar ZIP: $error');
    } finally {
      if (mounted) setState(() => _installingZip = false);
    }
  }

  Future<bool> _registerRepositoryAddon(String installPath) async {
    final manifestFile = File(p.join(installPath, 'addon.xml'));
    if (!await manifestFile.exists()) return false;

    final descriptor = const RepositoryDescriptorParser().parse(
      await manifestFile.readAsString(),
    );

    var added = false;
    for (final endpoint in descriptor.endpoints) {
      if (!_endpointIsCompatible(endpoint)) continue;
      if (widget.repositoryRegistry.sources.any(
        (source) => source.uri == endpoint.infoUri,
      )) {
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

  bool _endpointIsCompatible(RepositoryEndpoint endpoint) {
    final minimum = endpoint.minimumVersion?.trim();
    if (minimum != null &&
        minimum.isNotEmpty &&
        _hostKodiVersion.compareTo(KodiVersion(minimum)) < 0) {
      return false;
    }

    final maximum = endpoint.maximumVersion?.trim();
    if (maximum != null &&
        maximum.isNotEmpty &&
        _hostKodiVersion.compareTo(KodiVersion(maximum)) > 0) {
      return false;
    }
    return true;
  }

  Future<void> _removeRepository(RepositorySource source) async {
    await widget.repositoryRegistry.remove(source.uri);
    widget.repositoryStoreController.forget(source.uri);
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
        onPressed: () => unawaited(_addRepository()),
        icon: const Icon(Icons.add_link_rounded),
        label: const Text('Adicionar fonte'),
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
                onEnabledChanged: (enabled) => unawaited(
                  widget.repositoryRegistry.setEnabled(
                    repository.uri,
                    enabled,
                  ),
                ),
                onRemove: () => unawaited(_removeRepository(repository)),
              );
            },
          );
        },
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
      error = 'Informe a URL da fonte/repositório.';
    } else if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      error = 'Use uma URL HTTP ou HTTPS válida.';
    } else if (widget.existingUris.contains(uri)) {
      error = 'Esta fonte já foi adicionada.';
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
      title: const Text('Adicionar fonte Kodi'),
      content: SizedBox(
        width: 580,
        child: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onChanged: (_) {
            if (_errorText != null) setState(() => _errorText = null);
          },
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'URL',
            hintText: 'https://vikingskoditeam.github.io',
            helperText:
                'Aceita fonte Kodi com ZIPs, addon.xml ou addons.xml/addons.xml.gz.',
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
    return Card(
      child: ListTile(
        onTap: onOpen,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: _StatusIcon(state: state),
        title: KodiText(catalog?.repositoryName ?? repository.displayName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(repository.uri.toString()),
            const SizedBox(height: 5),
            Text(_statusText()),
            if (state.errorMessage case final error?) ...[
              const SizedBox(height: 4),
              Text(
                error,
                maxLines: 3,
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
            Switch(value: repository.enabled, onChanged: onEnabledChanged),
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

  String _statusText() {
    switch (state.status) {
      case RepositorySyncStatus.idle:
        return repository.enabled
            ? 'Aguardando sincronização.'
            : 'Fonte desativada.';
      case RepositorySyncStatus.syncing:
        return 'Detectando fonte e sincronizando…';
      case RepositorySyncStatus.ready:
        final catalog = state.catalog!;
        final skipped = catalog.skippedAddons == 0
            ? ''
            : ' • ${catalog.skippedAddons} ignorado(s)';
        return '${catalog.addons.length} addon(s)$skipped';
      case RepositorySyncStatus.failed:
        return state.catalog == null
            ? 'Falha na sincronização.'
            : 'Falha ao atualizar; usando o último catálogo.';
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
              const SizedBox(height: 18),
              Text(
                'Nenhuma fonte configurada',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Adicione a mesma URL que você usaria como fonte no Kodi. O AddKo também aceita addon.xml, addons.xml e ZIP local.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
