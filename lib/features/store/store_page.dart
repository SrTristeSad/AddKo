import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/repositories/application/repository_registry.dart';
import '../../core/repositories/application/repository_store_controller.dart';
import '../../core/repositories/domain/repository_source.dart';
import 'repository_catalog_page.dart';

class StorePage extends StatefulWidget {
  const StorePage({
    required this.repositoryRegistry,
    required this.repositoryStoreController,
    super.key,
  });

  final RepositoryRegistry repositoryRegistry;
  final RepositoryStoreController repositoryStoreController;

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  @override
  void initState() {
    super.initState();
    widget.repositoryRegistry.addListener(_handleRegistryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncIdleSources());
  }

  @override
  void dispose() {
    widget.repositoryRegistry.removeListener(_handleRegistryChanged);
    super.dispose();
  }

  void _handleRegistryChanged() {
    _syncIdleSources();
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
        onPressed: () => _showAddRepositoryDialog(context),
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

  Future<void> _remove(RepositorySource repository) async {
    await widget.repositoryRegistry.remove(repository.uri);
    widget.repositoryStoreController.forget(repository.uri);
  }

  Future<void> _showAddRepositoryDialog(BuildContext context) async {
    final controller = TextEditingController();
    String? errorText;
    var submitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (submitting) {
                return;
              }
              setDialogState(() {
                submitting = true;
                errorText = null;
              });

              try {
                await widget.repositoryRegistry.addUrl(controller.text);
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              } on FormatException catch (error) {
                if (dialogContext.mounted) {
                  setDialogState(() {
                    errorText = error.message.toString();
                    submitting = false;
                  });
                }
              } on Object catch (error) {
                if (dialogContext.mounted) {
                  setDialogState(() {
                    errorText = 'Não foi possível salvar: $error';
                    submitting = false;
                  });
                }
              }
            }

            return AlertDialog(
              title: const Text('Adicionar repositório'),
              content: SizedBox(
                width: 560,
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  enabled: !submitting,
                  keyboardType: TextInputType.url,
                  onSubmitted: (_) => unawaited(submit()),
                  decoration: InputDecoration(
                    labelText: 'URL do repositório',
                    hintText: 'https://exemplo.com/repository/',
                    helperText:
                        'Aceita descriptor addon.xml ou índice addons.xml/addons.xml.gz.',
                    errorText: errorText,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: submitting ? null : () => unawaited(submit()),
                  child: submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Adicionar'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
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
                'Adicione o endereço de um repositório. A Loja sincroniza o índice e exibe os addons separados pelos tipos publicados pelo ecossistema Kodi.',
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
