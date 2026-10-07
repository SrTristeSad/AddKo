import 'package:flutter/material.dart';

import '../../core/repositories/application/repository_registry.dart';
import '../../core/repositories/domain/repository_source.dart';

class StorePage extends StatelessWidget {
  const StorePage({
    required this.repositoryRegistry,
    super.key,
  });

  final RepositoryRegistry repositoryRegistry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loja')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddRepositoryDialog(context),
        icon: const Icon(Icons.add_link_rounded),
        label: const Text('Adicionar repositório'),
      ),
      body: AnimatedBuilder(
        animation: repositoryRegistry,
        builder: (context, _) {
          final repositories = repositoryRegistry.sources;
          if (repositories.isEmpty) {
            return const _EmptyStore();
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
            itemCount: repositories.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final repository = repositories[index];
              return _RepositoryCard(
                repository: repository,
                onEnabledChanged: (value) {
                  repositoryRegistry.setEnabled(repository.uri, value);
                },
                onRemove: () => repositoryRegistry.remove(repository.uri),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showAddRepositoryDialog(BuildContext context) async {
    final controller = TextEditingController();
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Adicionar repositório'),
              content: SizedBox(
                width: 560,
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  onSubmitted: (_) => _tryAddRepository(
                    dialogContext,
                    controller.text,
                    onError: (message) {
                      setDialogState(() => errorText = message);
                    },
                  ),
                  decoration: InputDecoration(
                    labelText: 'URL do repositório',
                    hintText: 'https://exemplo.com/repository/',
                    errorText: errorText,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => _tryAddRepository(
                    dialogContext,
                    controller.text,
                    onError: (message) {
                      setDialogState(() => errorText = message);
                    },
                  ),
                  child: const Text('Adicionar'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  void _tryAddRepository(
    BuildContext dialogContext,
    String rawUrl, {
    required ValueChanged<String> onError,
  }) {
    try {
      repositoryRegistry.addUrl(rawUrl);
      Navigator.pop(dialogContext);
    } on FormatException catch (error) {
      onError(error.message.toString());
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
              const SizedBox(height: 20),
              Text(
                'Nenhum repositório configurado',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Adicione o endereço de um repositório. A Loja exibirá os addons conforme a organização e os metadados fornecidos por ele.',
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
    required this.onEnabledChanged,
    required this.onRemove,
  });

  final RepositorySource repository;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: const Icon(Icons.account_tree_rounded),
        title: Text(repository.displayName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(repository.uri.toString()),
            const SizedBox(height: 4),
            const Text('Aguardando sincronização do Repository Manager.'),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: repository.enabled,
              onChanged: onEnabledChanged,
            ),
            IconButton(
              tooltip: 'Remover',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
