import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/addons/application/addon_install_controller.dart';
import '../../core/addons/domain/installed_addon.dart';
import '../legacy/legacy_addon_settings_page.dart';

class AddonManagerPage extends StatefulWidget {
  const AddonManagerPage({
    required this.addonInstallController,
    super.key,
  });

  final AddonInstallController addonInstallController;

  @override
  State<AddonManagerPage> createState() => _AddonManagerPageState();
}

class _AddonManagerPageState extends State<AddonManagerPage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _removing = <String>{};
  _AddonFilter _filter = _AddonFilter.all;
  bool _refreshing = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await widget.addonInstallController.refreshInstalled();
    } on Object catch (error) {
      if (mounted) _showMessage('Falha ao atualizar a lista: $error', error: true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  List<InstalledAddon> _visibleAddons() {
    final query = _searchController.text.trim().toLowerCase();
    final addons = widget.addonInstallController.installedAddons.where((addon) {
      if (!_filter.matches(addon)) return false;
      if (query.isEmpty) return true;
      final manifest = addon.manifest;
      return manifest.name.toLowerCase().contains(query) ||
          manifest.id.toLowerCase().contains(query) ||
          manifest.providerName.toLowerCase().contains(query);
    }).toList(growable: false)
      ..sort((a, b) =>
          a.manifest.name.toLowerCase().compareTo(b.manifest.name.toLowerCase()));
    return addons;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Addons instalados'),
        actions: [
          IconButton(
            tooltip: 'Atualizar lista',
            onPressed: _refreshing ? null : () => unawaited(_refresh()),
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.addonInstallController,
        builder: (context, _) {
          final all = widget.addonInstallController.installedAddons;
          final visible = _visibleAddons();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: 'Buscar addon por nome ou ID',
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpar busca',
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  children: [
                    for (final filter in _AddonFilter.values) ...[
                      ChoiceChip(
                        label: Text(filter.label),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${visible.length} exibido(s) • ${all.length} instalado(s)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ),
              Expanded(
                child: visible.isEmpty
                    ? const _EmptyAddonManager()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            _addonTile(visible[index]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _addonTile(InstalledAddon addon) {
    final manifest = addon.manifest;
    final dependents = widget.addonInstallController.requiredBy(manifest.id);
    final removing = _removing.contains(manifest.id);
    final canConfigure = _hasSettings(addon);

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: CircleAvatar(child: Icon(_iconFor(addon))),
        title: Text(manifest.name),
        subtitle: Text(
          '${manifest.id} • v${manifest.version}\n'
          '${_typeLabel(addon)}'
          '${dependents.isEmpty ? '' : ' • usado por ${dependents.length} addon(s)'}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        onTap: () => _showDetails(addon),
        trailing: removing
            ? const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : PopupMenuButton<_AddonAction>(
                tooltip: 'Ações do addon',
                onSelected: (action) {
                  switch (action) {
                    case _AddonAction.details:
                      _showDetails(addon);
                    case _AddonAction.settings:
                      unawaited(_openSettings(addon));
                    case _AddonAction.uninstall:
                      unawaited(_requestUninstall(addon));
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _AddonAction.details,
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.info_outline_rounded),
                      title: Text('Detalhes'),
                    ),
                  ),
                  if (canConfigure)
                    const PopupMenuItem(
                      value: _AddonAction.settings,
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.tune_rounded),
                        title: Text('Configurações do addon'),
                      ),
                    ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: _AddonAction.uninstall,
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.delete_outline_rounded),
                      title: Text('Desinstalar'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  bool _hasSettings(InstalledAddon addon) {
    return File(p.join(addon.installPath, 'resources', 'settings.xml')).existsSync() ||
        File(
          p.join(
            addon.installPath,
            'resources',
            'settings',
            'settings.xml',
          ),
        ).existsSync();
  }

  Future<void> _openSettings(InstalledAddon addon) async {
    final directories = await widget.addonInstallController.directories();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LegacyAddonSettingsPage(
          addon: addon,
          addonDataRootPath: directories.addonDataRootPath,
        ),
      ),
    );
  }

  void _showDetails(InstalledAddon addon) {
    final manifest = addon.manifest;
    final requiredBy = widget.addonInstallController.requiredBy(manifest.id);
    final dependencies = manifest.dependencies
        .where((dependency) => !dependency.optional)
        .toList(growable: false);

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 30),
              children: [
                Text(
                  manifest.name,
                  style: Theme.of(sheetContext).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                SelectableText('${manifest.id} • v${manifest.version}'),
                const SizedBox(height: 16),
                _DetailRow(label: 'Tipo', value: _typeLabel(addon)),
                _DetailRow(
                  label: 'Autor',
                  value: manifest.providerName.trim().isEmpty
                      ? 'Não informado'
                      : manifest.providerName,
                ),
                _DetailRow(label: 'Pasta', value: addon.installPath),
                if (manifest.summary?.trim().isNotEmpty == true)
                  _DetailRow(label: 'Resumo', value: manifest.summary!.trim()),
                if (dependencies.isNotEmpty)
                  _DetailRow(
                    label: 'Dependências',
                    value: dependencies
                        .map((dependency) =>
                            '${dependency.id}${dependency.version == null ? '' : ' >= ${dependency.version}'}')
                        .join('\n'),
                  ),
                if (requiredBy.isNotEmpty)
                  _DetailRow(
                    label: 'Necessário para',
                    value: requiredBy
                        .map((dependent) => dependent.manifest.name)
                        .join('\n'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _requestUninstall(InstalledAddon addon) async {
    final manifest = addon.manifest;
    final dependents = widget.addonInstallController.requiredBy(manifest.id);
    if (dependents.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Não é possível desinstalar'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${manifest.name} é uma dependência obrigatória de:'),
                const SizedBox(height: 10),
                for (final dependent in dependents)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• ${dependent.manifest.name} (${dependent.manifest.id})'),
                  ),
                const SizedBox(height: 10),
                const Text('Desinstale esses addons primeiro.'),
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
      return;
    }

    var removeData = false;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text('Desinstalar ${manifest.name}?'),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${manifest.id} • v${manifest.version}'),
                    const SizedBox(height: 12),
                    const Text('O código do addon será removido do AddKo.'),
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: removeData,
                      onChanged: (value) =>
                          setDialogState(() => removeData = value ?? false),
                      title: const Text('Apagar também configurações e dados'),
                      subtitle: const Text(
                        'Se desmarcado, os dados ficam guardados para uma futura reinstalação.',
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
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Desinstalar'),
                ),
              ],
            ),
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;
    setState(() => _removing.add(manifest.id));
    try {
      await widget.addonInstallController.uninstall(
        manifest.id,
        removeData: removeData,
      );
      if (mounted) _showMessage('${manifest.name} desinstalado.');
    } on Object catch (error) {
      if (mounted) _showMessage('Falha ao desinstalar: $error', error: true);
    } finally {
      if (mounted) setState(() => _removing.remove(manifest.id));
    }
  }

  void _showMessage(String message, {bool error = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String _typeLabel(InstalledAddon addon) {
    final manifest = addon.manifest;
    if (manifest.isPythonPlugin) return 'Plugin executável';
    if (manifest.isPythonService) return 'Serviço em segundo plano';
    if (manifest.isRepository) return 'Repositório';
    if (manifest.isPythonScript) return 'Script Python';
    if (manifest.extensions.any((extension) =>
        extension.point.toLowerCase().contains('inputstream'))) {
      return 'InputStream';
    }
    if (manifest.extensions.any(
      (extension) => extension.point.toLowerCase().contains('pvr'),
    )) {
      return 'PVR';
    }
    if (manifest.id.startsWith('script.module.')) return 'Módulo Python';
    return 'Componente Kodi';
  }

  IconData _iconFor(InstalledAddon addon) {
    final manifest = addon.manifest;
    if (manifest.isPythonPlugin) return Icons.play_circle_outline_rounded;
    if (manifest.isPythonService) return Icons.settings_input_component_rounded;
    if (manifest.isRepository) return Icons.account_tree_rounded;
    if (manifest.isPythonScript) return Icons.code_rounded;
    if (manifest.id.startsWith('script.module.')) return Icons.inventory_2_outlined;
    if (manifest.extensions.any((extension) =>
        extension.point.toLowerCase().contains('inputstream'))) {
      return Icons.stream_rounded;
    }
    if (manifest.extensions.any(
      (extension) => extension.point.toLowerCase().contains('pvr'),
    )) {
      return Icons.live_tv_rounded;
    }
    return Icons.extension_rounded;
  }
}

enum _AddonFilter {
  all('Todos'),
  plugins('Plugins'),
  components('Componentes'),
  services('Serviços'),
  repositories('Repositórios');

  const _AddonFilter(this.label);
  final String label;

  bool matches(InstalledAddon addon) {
    return switch (this) {
      _AddonFilter.all => true,
      _AddonFilter.plugins => addon.manifest.isPythonPlugin,
      _AddonFilter.services => addon.manifest.isPythonService,
      _AddonFilter.repositories => addon.manifest.isRepository,
      _AddonFilter.components => !addon.manifest.isPythonPlugin &&
          !addon.manifest.isPythonService &&
          !addon.manifest.isRepository,
    };
  }
}

enum _AddonAction { details, settings, uninstall }

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(height: 3),
          SelectableText(value),
        ],
      ),
    );
  }
}

class _EmptyAddonManager extends StatelessWidget {
  const _EmptyAddonManager();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.extension_off_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              'Nenhum addon encontrado',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'Instale addons pela Loja ou altere a busca e os filtros.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
