import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:addko/src/plugins/plugin_package.dart';
import 'package:addko/src/repositories/addko_repositories.dart';
import 'package:addko/src/repositories/catalog_version.dart';
import 'package:flutter/material.dart';

typedef AddonRemover = Future<void> Function(InstalledPlugin plugin, bool eraseData);

class AddKoInstalledManager extends StatefulWidget {
  const AddKoInstalledManager({
    super.key,
    required this.installed,
    required this.repositories,
    required this.onRemove,
    required this.onReload,
    required this.onOpenStore,
  });

  final List<InstalledPlugin> installed;
  final AddKoRepositoryManager repositories;
  final AddonRemover onRemove;
  final Future<List<InstalledPlugin>> Function() onReload;
  final Future<void> Function() onOpenStore;

  @override
  State<AddKoInstalledManager> createState() => _AddKoInstalledManagerState();
}

class _AddKoInstalledManagerState extends State<AddKoInstalledManager> {
  late List<InstalledPlugin> _plugins;
  List<RepositoryStatus> _sources = const <RepositoryStatus>[];
  bool _busy = false;
  bool _checking = false;
  String? _warning;

  @override
  void initState() {
    super.initState();
    _plugins = List<InstalledPlugin>.of(widget.installed);
    _checkUpdates();
  }

  List<InstalledPlugin> _dependents(String id) => _plugins
      .where((plugin) => plugin.manifest.dependencies.contains(id))
      .toList();

  RepositoryAddon? _updateFor(InstalledPlugin installed) {
    for (final source in _sources) {
      if (source.index == null) continue;
      for (final addon in source.index!.addons) {
        if (addon.id == installed.manifest.id &&
            catalogVersionStatus(
              addon.version,
              installed.manifest.version,
            ) == CatalogVersionStatus.updateAvailable) {
          return addon;
        }
      }
    }
    return null;
  }

  Future<void> _checkUpdates() async {
    if (_busy || _checking) return;
    setState(() {
      _checking = true;
      _warning = null;
    });
    try {
      final sources = await widget.repositories.refresh();
      if (!mounted) return;
      setState(() {
        _sources = sources;
        final unavailable = sources.where((item) => item.error != null).length;
        if (unavailable > 0) {
          _warning = '$unavailable repositório(s) indisponível(is).';
        }
      });
    } on Object catch (error) {
      if (mounted) setState(() => _warning = 'Falha na consulta: $error');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _browseStore() async {
    if (_busy) return;
    await widget.onOpenStore();
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final plugins = await widget.onReload();
      if (mounted) setState(() => _plugins = plugins);
    } on Object catch (error) {
      _notify('Falha ao atualizar a lista: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _checkUpdates();
  }

  Future<void> _details(InstalledPlugin plugin) async {
    final dependents = _dependents(plugin.manifest.id);
    final permissions = plugin.manifest.permissions.toList()
      ..sort((a, b) => a.wireName.compareTo(b.wireName));
    final dependencies = plugin.manifest.dependencies.toList()..sort();
    final update = _updateFor(plugin);
    final removalRequested = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(plugin.manifest.name),
        content: SizedBox(
          width: 490,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ID: ${plugin.manifest.id}'),
                Text(plugin.manifest.kind == PluginKind.service
                    ? 'Tipo: Serviço para outros addons'
                    : 'Tipo: Aplicativo'),
                Text('Versão instalada: ${plugin.manifest.version}'),
                if (update != null)
                  Text('Atualização disponível: ${update.version}'),
                const SizedBox(height: 20),
                Text('Permissões',
                    style: Theme.of(dialogContext).textTheme.titleMedium),
                const SizedBox(height: 6),
                if (permissions.isEmpty)
                  const Text('Nenhuma permissão especial.')
                else
                  for (final permission in permissions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(_permissionDescription(permission)),
                    ),
                const SizedBox(height: 16),
                Text('Dependências',
                    style: Theme.of(dialogContext).textTheme.titleMedium),
                const SizedBox(height: 6),
                if (dependencies.isEmpty)
                  const Text('Não declara dependências.')
                else
                  for (final dependency in dependencies) Text('• $dependency'),
                const SizedBox(height: 16),
                Text('Outros addons que dependem deste',
                    style: Theme.of(dialogContext).textTheme.titleMedium),
                const SizedBox(height: 6),
                if (dependents.isEmpty)
                  const Text('Nenhum.')
                else
                  for (final dependent in dependents)
                    Text('• ${dependent.manifest.name}'),
                const SizedBox(height: 12),
                const Text(
                  'As permissões exibidas vêm do manifesto local instalado, '
                  'não do catálogo do repositório.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Fechar'),
          ),
          TextButton.icon(
            onPressed: _busy || dependents.isNotEmpty
                ? null
                : () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Desinstalar'),
          ),
          if (update != null)
            FilledButton.tonal(
              onPressed: () {
                Navigator.pop(dialogContext, false);
                _browseStore();
              },
              child: const Text('Ver atualização na Loja'),
            ),
        ],
      ),
    );
    if (removalRequested == true && mounted) {
      await _confirmUninstall(plugin);
    }
  }

  Future<void> _confirmUninstall(InstalledPlugin plugin) async {
    if (_busy || _dependents(plugin.manifest.id).isNotEmpty) return;
    var erase = false;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) => AlertDialog(
          title: Text('Desinstalar ${plugin.manifest.name}?'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'O AddKo preserva os dados privados por padrão. '
                  'Você pode apagá-los também, se desejar.',
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: erase,
                  onChanged: (value) => updateDialog(() => erase = value ?? false),
                  title: const Text('Apagar também os dados do addon'),
                  subtitle: const Text(
                    'Histórico, favoritos e configurações poderão ser '
                    'perdidos permanentemente.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Desinstalar'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.onRemove(plugin, erase);
      final remaining = await widget.onReload();
      if (mounted) {
        setState(() => _plugins = remaining);
        _notify('${plugin.manifest.name} desinstalado.');
      }
    } on Object catch (error) {
      _notify('Falha na desinstalação: $error');
      try {
        final remaining = await widget.onReload();
        if (mounted) setState(() => _plugins = remaining);
      } on Object {
        // Keep the original removal error visible.
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final updateCount = _plugins.where(
      (plugin) => _updateFor(plugin) != null,
    ).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciar addons'),
        actions: [
          IconButton(
            tooltip: 'Verificar atualizações',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _busy || _checking ? null : _checkUpdates,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_plugins.length} addon(s) instalado(s)',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _browseStore,
                      icon: const Icon(Icons.storefront_outlined),
                      label: const Text('Abrir Loja'),
                    ),
                  ],
                ),
                if (_checking) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (updateCount > 0) ...[
                  const SizedBox(height: 14),
                  Text('$updateCount atualização(ões) disponível(is).'),
                ],
                if (_warning != null) ...[
                  const SizedBox(height: 14),
                  Text(_warning!),
                ],
                if (_plugins.isEmpty) ...[
                  const SizedBox(height: 22),
                  const Center(child: Text('Nenhum addon instalado.')),
                ],
                for (final plugin in _plugins) ...[
                  const SizedBox(height: 10),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.extension_outlined),
                      title: Text(plugin.manifest.name),
                      subtitle: Text(
                        '${plugin.manifest.kind == PluginKind.service ? 'Serviço • ' : ''}'
                        'v${plugin.manifest.version}'
                        '${_updateFor(plugin) != null ? ' • Atualização disponível' : ''}',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _busy ? null : () => _details(plugin),
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

String _permissionDescription(PluginPermission permission) => switch (permission) {
      PluginPermission.network => 'Rede — acesso HTTP/HTTPS.',
      PluginPermission.storage =>
        'Armazenamento — arquivos próprios e dados privados.',
      PluginPermission.media => 'Mídia — player fornecido pelo host.',
      PluginPermission.background => 'Segundo plano — sessões prolongadas.',
      PluginPermission.nativeEngine =>
        'Motor nativo — iniciar módulos aprovados já incluídos no APK.',
    };
