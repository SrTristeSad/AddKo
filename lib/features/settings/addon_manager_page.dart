import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/addons/application/addon_install_controller.dart';
import '../../core/addons/domain/installed_addon.dart';

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
  final Set<String> _removing = <String>{};
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);

    try {
      await widget.addonInstallController.refreshInstalled();
    } on Object catch (error) {
      if (mounted) {
        _showMessage('Falha ao atualizar addons: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _remove(InstalledAddon addon) async {
    final id = addon.manifest.id;
    if (_removing.contains(id)) return;

    final dependents = widget.addonInstallController.requiredBy(id);
    if (dependents.isNotEmpty) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Não é possível desinstalar'),
          content: Text(
            '${addon.manifest.name} é necessário para: '
            '${dependents.map((item) => item.manifest.name).join(', ')}.',
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

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Desinstalar ${addon.manifest.name}?'),
            content: Text('${addon.manifest.id} • v${addon.manifest.version}'),
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
        ) ??
        false;

    if (!confirmed || !mounted) return;

    setState(() => _removing.add(id));
    try {
      await widget.addonInstallController.uninstall(id);
      if (mounted) {
        _showMessage('${addon.manifest.name} desinstalado.');
      }
    } on Object catch (error) {
      if (mounted) {
        _showMessage('Falha ao desinstalar: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _removing.remove(id));
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
          final addons = widget.addonInstallController.installedAddons
              .toList(growable: false)
            ..sort(
              (left, right) => left.manifest.name
                  .toLowerCase()
                  .compareTo(right.manifest.name.toLowerCase()),
            );

          if (addons.isEmpty) {
            return const Center(
              child: Text('Nenhum addon encontrado'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: addons.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final addon = addons[index];
              final removing = _removing.contains(addon.manifest.id);

              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  leading: const Icon(Icons.extension_rounded),
                  title: Text(addon.manifest.name),
                  subtitle: Text(
                    '${addon.manifest.id} • v${addon.manifest.version}',
                  ),
                  trailing: removing
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : IconButton(
                          tooltip: 'Desinstalar',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => unawaited(_remove(addon)),
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
