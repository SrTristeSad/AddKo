import 'package:addko/src/repositories/addko_repositories.dart';
import 'package:flutter/material.dart';

typedef RepositoryInstaller = Future<bool> Function(RepositoryAddon addon);

class AddKoRepositoryStore extends StatefulWidget {
  const AddKoRepositoryStore({
    super.key,
    required this.repositories,
    required this.onInstallPackage,
    required this.onInstallAddon,
    this.busy = false,
  });

  final AddKoRepositoryManager repositories;
  final VoidCallback onInstallPackage;
  final RepositoryInstaller onInstallAddon;
  final bool busy;

  @override
  State<AddKoRepositoryStore> createState() => _AddKoRepositoryStoreState();
}

class _AddKoRepositoryStoreState extends State<AddKoRepositoryStore> {
  List<RepositoryStatus> _sources = <RepositoryStatus>[];
  bool _working = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_working) return;
    setState(() {
      _working = true;
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.repositories.refresh();
      if (mounted) setState(() => _sources = result);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _loading = false;
        });
      }
    }
  }

  void _notify(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _addRepository() async {
    if (_working || widget.busy) return;
    var enteredUrl = '';
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Adicionar repositório'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Informe a URL HTTPS do arquivo JSON do repositório. '
                'Adicione somente fontes em que você confia.',
              ),
              const SizedBox(height: 16),
              TextField(
                onChanged: (value) => enteredUrl = value,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'URL do índice',
                  hintText: 'https://exemplo.com/addko/index.json',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (value) => Navigator.pop(dialogContext, value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, enteredUrl),
            child: const Text('Validar e adicionar'),
          ),
        ],
      ),
    );
    if (url == null || url.trim().isEmpty || !mounted) return;
    setState(() => _working = true);
    try {
      final source = await widget.repositories.add(url);
      _notify('Repositório adicionado: ${source.name}');
    } on Object catch (error) {
      _notify('Não foi possível adicionar: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
    await _refresh();
  }

  Future<void> _removeRepository(RepositoryStatus source) async {
    if (_working || widget.busy) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover repositório?'),
        content: Text(
          'Remover ${source.index?.name ?? source.url.host} da Loja? '
          'Os addons já instalados serão mantidos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => _working = true);
    try {
      await widget.repositories.remove(source.url);
      _notify('Repositório removido.');
    } on Object catch (error) {
      _notify('Falha ao remover: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
    await _refresh();
  }

  Future<void> _install(RepositoryAddon addon) async {
    if (_working || widget.busy) return;
    setState(() => _working = true);
    try {
      final installed = await widget.onInstallAddon(addon);
      if (installed) _notify('${addon.name} instalado.');
    } on Object catch (error) {
      _notify('Falha na instalação: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final disabled = _working || widget.busy;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Loja'),
        actions: [
          IconButton(
            tooltip: 'Atualizar repositórios',
            onPressed: disabled ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Repositórios',
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'A Loja mostra apenas fontes cadastradas por você. '
                  'Nenhum catálogo é adicionado automaticamente.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 22),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: disabled ? null : _addRepository,
                      icon: const Icon(Icons.add_link_rounded),
                      label: const Text('Adicionar repositório'),
                    ),
                    OutlinedButton.icon(
                      onPressed: disabled ? null : widget.onInstallPackage,
                      icon: const Icon(Icons.archive_outlined),
                      label: const Text('Instalar arquivo .addko'),
                    ),
                  ],
                ),
                if (_loading || _working) ...[
                  const SizedBox(height: 18),
                  const LinearProgressIndicator(),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 20),
                  Text('Erro ao carregar repositórios: ${_error!}'),
                ],
                if (_sources.isEmpty && !_loading && _error == null) ...[
                  const SizedBox(height: 28),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        children: [
                          Icon(Icons.storefront_outlined,
                              size: 52, color: scheme.onSurfaceVariant),
                          const SizedBox(height: 14),
                          Text('Sua loja ainda está vazia',
                              style: theme.textTheme.titleLarge),
                          const SizedBox(height: 8),
                          const Text(
                            'Adicione uma URL de repositório para ver addons aqui.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                for (final source in _sources) ...[
                  const SizedBox(height: 22),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.storage_rounded),
                          title: Text(source.index?.name ?? source.url.host),
                          subtitle: Text(
                            source.url.toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: 'Remover repositório',
                            onPressed: disabled
                                ? null
                                : () => _removeRepository(source),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ),
                        if (source.error != null)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Falha ao atualizar: ${source.error!}',
                              style: TextStyle(color: scheme.error),
                            ),
                          )
                        else if (source.index!.addons.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('Este repositório não possui addons.'),
                          )
                        else
                          for (final addon in source.index!.addons) ...[
                            const Divider(height: 1),
                            ListTile(
                              title: Text(addon.name),
                              subtitle: Text(
                                'v${addon.version}' +
                                (addon.description.isEmpty
                                    ? ''
                                    : '\n${addon.description}'),
                              ),
                              isThreeLine: addon.description.isNotEmpty,
                              trailing: FilledButton.tonal(
                                onPressed: disabled ? null : () => _install(addon),
                                child: const Text('Instalar'),
                              ),
                            ),
                          ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
