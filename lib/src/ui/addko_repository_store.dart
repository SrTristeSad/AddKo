import 'dart:typed_data';

import 'package:addko/src/repositories/addko_repositories.dart';
import 'package:addko/src/repositories/catalog_version.dart';
import 'package:flutter/material.dart';

typedef RepositoryInstaller = Future<bool> Function(RepositoryAddon addon);

class AddKoRepositoryStore extends StatefulWidget {
  const AddKoRepositoryStore({
    super.key,
    required this.repositories,
    required this.onInstallPackage,
    required this.onInstallAddon,
    this.installedVersions = const <String, String>{},
    this.busy = false,
  });

  final AddKoRepositoryManager repositories;
  final VoidCallback onInstallPackage;
  final RepositoryInstaller onInstallAddon;
  final Map<String, String> installedVersions;
  final bool busy;

  @override
  State<AddKoRepositoryStore> createState() => _AddKoRepositoryStoreState();
}

class _AddKoRepositoryStoreState extends State<AddKoRepositoryStore> {
  List<RepositoryStatus> _sources = <RepositoryStatus>[];
  bool _working = false;
  bool _loading = true;
  String? _error;
  String? _categoryFilter;
  late final Map<String, String> _installedVersions;
  final Map<String, Future<Uint8List?>> _iconFutures =
      <String, Future<Uint8List?>>{};

  @override
  void initState() {
    super.initState();
    _installedVersions = Map<String, String>.of(widget.installedVersions);
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
      if (mounted) {
        setState(() {
          _sources = result;
          _iconFutures.clear();
          _categoryFilter = null;
        });
      }
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
      if (installed) {
        if (mounted) {
          setState(() => _installedVersions[addon.id] = addon.version);
        }
        _notify('${addon.name} instalado.');
      }
    } on Object catch (error) {
      _notify('Falha na instalação: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }


  CatalogVersionStatus _status(RepositoryAddon addon) =>
      catalogVersionStatus(addon.version, _installedVersions[addon.id]);

  String _statusLabel(CatalogVersionStatus status) => switch (status) {
        CatalogVersionStatus.notInstalled => 'Não instalado',
        CatalogVersionStatus.installed => 'Instalado',
        CatalogVersionStatus.updateAvailable => 'Atualização disponível',
        CatalogVersionStatus.installedNewer => 'Versão local mais nova',
        CatalogVersionStatus.differentVersion => 'Versão diferente',
      };

  String _actionLabel(CatalogVersionStatus status) => switch (status) {
        CatalogVersionStatus.notInstalled => 'Instalar',
        CatalogVersionStatus.installed => 'Instalado',
        CatalogVersionStatus.updateAvailable => 'Atualizar',
        CatalogVersionStatus.installedNewer => 'Versão local mais nova',
        CatalogVersionStatus.differentVersion => 'Substituir versão',
      };

  IconData _categoryIcon(String category) {
    final name = category.toLowerCase();
    if (name.contains('video') || name.contains('vídeo') ||
        name.contains('filme')) return Icons.movie_outlined;
    if (name.contains('jogo') || name.contains('game') ||
        name.contains('emulad')) return Icons.sports_esports_outlined;
    if (name.contains('music') || name.contains('músic') ||
        name.contains('radio') || name.contains('rádio')) {
      return Icons.music_note_outlined;
    }
    if (name.contains('livro') || name.contains('mangá') ||
        name.contains('manga') || name.contains('leitura')) {
      return Icons.menu_book_outlined;
    }
    if (name.contains('ferramenta') || name.contains('utilit')) {
      return Icons.build_outlined;
    }
    return Icons.extension_outlined;
  }

  Future<Uint8List?> _icon(RepositoryAddon addon) {
    final url = addon.icon;
    if (url == null) return Future<Uint8List?>.value();
    final cacheKey = '${url.toString()}/${addon.iconSha256}';
    final existing = _iconFutures[cacheKey];
    if (existing != null) return existing;
    // Never retain unbounded icon futures across massive catalogs.
    if (_iconFutures.length >= 48) {
      _iconFutures.remove(_iconFutures.keys.first);
    }
    final future = widget.repositories.downloadIcon(addon).catchError(
      (Object _) => null,
    );
    _iconFutures[cacheKey] = future;
    return future;
  }

  Widget _artwork(RepositoryAddon addon, {double size = 56}) {
    final placeholder = Icon(_categoryIcon(addon.category), size: size * .53);
    if (addon.icon == null) {
      return SizedBox(width: size, height: size, child: Center(child: placeholder));
    }
    return SizedBox(
      width: size,
      height: size,
      child: FutureBuilder<Uint8List?>(
        future: _icon(addon),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null) return Center(child: placeholder);
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              bytes,
              fit: BoxFit.cover,
              cacheWidth: 144,
              cacheHeight: 144,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => Center(child: placeholder),
            ),
          );
        },
      ),
    );
  }

  Future<void> _details(RepositoryAddon addon, RepositoryIndex source) async {
    final status = _status(addon);
    final installed = _installedVersions[addon.id];
    final actionable = status != CatalogVersionStatus.installed &&
        status != CatalogVersionStatus.installedNewer;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(addon.name),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: _artwork(addon, size: 90)),
                const SizedBox(height: 16),
                Text(addon.category, style: Theme.of(dialogContext).textTheme.labelLarge),
                const SizedBox(height: 8),
                Text(addon.description.isEmpty
                    ? 'O publicador não forneceu uma descrição.'
                    : addon.description),
                const SizedBox(height: 18),
                Text('Versão publicada: ${addon.version}'),
                Text('Versão instalada: ${installed ?? "Nenhuma"}'),
                Text('Situação: ${_statusLabel(status)}'),
                const SizedBox(height: 12),
                Text('Repositório: ${source.name}'),
                Text('Origem: ${source.url.host}'),
                const SizedBox(height: 8),
                Text('SHA-256: ${addon.sha256}',
                    style: Theme.of(dialogContext).textTheme.bodySmall),
                const SizedBox(height: 12),
                const Text(
                  'As permissões e dependências verdadeiras são verificadas '
                  'no pacote e exibidas antes de instalar ou atualizar. '
                  'O catálogo é informação do publicador, não uma aprovação de segurança.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fechar'),
          ),
          FilledButton(
            onPressed: (_working || widget.busy || !actionable)
                ? null
                : () {
                    Navigator.of(dialogContext).pop();
                    _install(addon);
                  },
            child: Text(_actionLabel(status)),
          ),
        ],
      ),
    );
  }

  Widget _addonCard(RepositoryAddon addon, RepositoryIndex source) {
    final status = _status(addon);
    final label = _statusLabel(status);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _details(addon, source),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _artwork(addon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(addon.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('${addon.category} · v${addon.version}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(label,
                        style: TextStyle(
                          color: status == CatalogVersionStatus.updateAvailable
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                          fontWeight: status == CatalogVersionStatus.updateAvailable
                              ? FontWeight.w700
                              : FontWeight.normal,
                        )),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _details(addon, source),
                child: const Text('Detalhes'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final disabled = _working || widget.busy;

    final categories = _sources
        .expand((source) => source.index?.addons ?? const <RepositoryAddon>[])
        .map((addon) => addon.category)
        .toSet()
        .toList()
      ..sort();
    if (_categoryFilter != null && !categories.contains(_categoryFilter)) {
      _categoryFilter = null;
    }
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

                if (categories.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('Categorias', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      ChoiceChip(
                        label: const Text('Todas'),
                        selected: _categoryFilter == null,
                        onSelected: (_) => setState(() => _categoryFilter = null),
                      ),
                      for (final category in categories)
                        ChoiceChip(
                          label: Text(category),
                          selected: _categoryFilter == category,
                          onSelected: (_) =>
                              setState(() => _categoryFilter = category),
                        ),
                    ],
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
                          for (final addon in source.index!.addons.where(
                            (item) => _categoryFilter == null ||
                                item.category == _categoryFilter,
                          ))
                            _addonCard(addon, source.index!),
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
