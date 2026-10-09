import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/addons/application/addon_install_controller.dart';
import '../../core/addons/domain/installed_addon.dart';

class ComponentsPage extends StatefulWidget {
  const ComponentsPage({
    required this.addonInstallController,
    super.key,
  });

  final AddonInstallController addonInstallController;

  @override
  State<ComponentsPage> createState() => _ComponentsPageState();
}

class _ComponentsPageState extends State<ComponentsPage> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await widget.addonInstallController.refreshInstalled();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Componentes de addons'),
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
          final components = widget.addonInstallController.installedAddons
              .where((addon) => !addon.manifest.isPythonPlugin)
              .toList(growable: false)
            ..sort((a, b) => a.manifest.name.compareTo(b.manifest.name));

          if (components.isEmpty) {
            return const _EmptyComponents();
          }

          return ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: components.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _ComponentTile(
              addon: components[index],
            ),
          );
        },
      ),
    );
  }
}

class _ComponentTile extends StatelessWidget {
  const _ComponentTile({required this.addon});

  final InstalledAddon addon;

  @override
  Widget build(BuildContext context) {
    final manifest = addon.manifest;
    final points = manifest.extensions
        .map((extension) => extension.point)
        .where((point) => point.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: Icon(_iconFor(addon)),
        title: Text(manifest.name),
        subtitle: Text(
          '${manifest.id} • v${manifest.version}'
          '${points.isEmpty ? '' : '\n${points.join(' • ')}'}',
        ),
        isThreeLine: points.isNotEmpty,
      ),
    );
  }

  IconData _iconFor(InstalledAddon addon) {
    final manifest = addon.manifest;
    if (manifest.isPythonService) return Icons.settings_input_component_rounded;
    if (manifest.isRepository) return Icons.account_tree_rounded;
    if (manifest.isPythonScript) return Icons.code_rounded;
    if (manifest.extensions.any((e) => e.point.contains('inputstream'))) {
      return Icons.stream_rounded;
    }
    if (manifest.extensions.any((e) => e.point.contains('pvr'))) {
      return Icons.live_tv_rounded;
    }
    return Icons.extension_rounded;
  }
}

class _EmptyComponents extends StatelessWidget {
  const _EmptyComponents();

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
            const SizedBox(height: 16),
            Text(
              'Nenhum componente instalado',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Dependências, serviços, módulos Python e addons binários aparecerão aqui quando forem instalados.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
