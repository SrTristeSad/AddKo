import 'package:flutter/material.dart';

import '../../core/addons/application/addon_install_controller.dart';
import '../../core/addons/application/addon_dependency_resolver.dart';
import '../../core/addons/domain/kodi_version.dart';
import '../../core/repositories/application/repository_store_controller.dart';
import '../../core/repositories/domain/repository_catalog.dart';

class RepositoryCatalogPage extends StatelessWidget {
  const RepositoryCatalogPage({
    required this.catalog,
    required this.repositoryStoreController,
    required this.addonInstallController,
    super.key,
  });

  final RepositoryCatalog catalog;
  final RepositoryStoreController repositoryStoreController;
  final AddonInstallController addonInstallController;

  @override
  Widget build(BuildContext context) {
    final groups = catalog.grouped.entries.toList()
      ..sort((left, right) => left.key.index.compareTo(right.key.index));

    return Scaffold(
      appBar: AppBar(
        title: Text(catalog.repositoryName),
      ),
      body: AnimatedBuilder(
        animation: addonInstallController,
        builder: (context, _) {
          if (groups.isEmpty) {
            return const Center(
              child: Text('Este repositório não publicou addons.'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 14),
                child: ExpansionTile(
                  initiallyExpanded: index == 0,
                  title: Text(group.key.label),
                  subtitle: Text('${group.value.length} addon(s)'),
                  children: [
                    for (final addon in group.value)
                      ListTile(
                        leading: addon.iconUri == null
                            ? const Icon(Icons.extension_rounded)
                            : Image.network(
                                addon.iconUri.toString(),
                                width: 44,
                                height: 44,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.extension_rounded),
                              ),
                        title: Text(addon.manifest.name),
                        subtitle: Text(
                          _subtitleFor(addon),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: _installAction(context, addon),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _installAction(BuildContext context, RepositoryAddonEntry addon) {
    final addonId = addon.manifest.id;
    if (addonInstallController.isInstalling(addonId)) {
      return const SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    }

    if (addon.packageUri == null) {
      return const Tooltip(
        message: 'O repositório não forneceu uma URL de pacote ZIP.',
        child: Icon(Icons.info_outline_rounded),
      );
    }

    final installed = addonInstallController.installedById(addonId);
    var label = 'Instalar';
    var icon = Icons.download_rounded;
    if (installed != null) {
      final current = KodiVersion(installed.manifest.version);
      final available = KodiVersion(addon.manifest.version);
      if (current.compareTo(available) < 0) {
        label = 'Atualizar';
        icon = Icons.system_update_alt_rounded;
      } else {
        label = 'Reinstalar';
        icon = Icons.refresh_rounded;
      }
    }

    return FilledButton.tonalIcon(
      onPressed: () => _requestInstall(context, addon),
      icon: Icon(icon),
      label: Text(label),
    );
  }

  Future<void> _requestInstall(
    BuildContext context,
    RepositoryAddonEntry addon,
  ) async {
    await addonInstallController.initialize();
    if (!context.mounted) {
      return;
    }

    final plan = addonInstallController.buildPlan(
      addon: addon,
      catalogs: repositoryStoreController.catalogs,
    );

    if (!plan.canInstall) {
      await _showPlanIssues(context, addon, plan);
      return;
    }

    final dependencies = plan.installOrder
        .where((entry) => entry.manifest.id != addon.manifest.id)
        .toList(growable: false);

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text('Instalar ${addon.manifest.name}?'),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${addon.manifest.id} • v${addon.manifest.version}'),
                    const SizedBox(height: 12),
                    if (dependencies.isEmpty)
                      const Text('Nenhuma dependência adicional precisa ser instalada.')
                    else ...[
                      Text(
                        '${dependencies.length} dependência(s) serão instaladas automaticamente:',
                      ),
                      const SizedBox(height: 8),
                      for (final dependency in dependencies)
                        Text(
                          '• ${dependency.manifest.name} (${dependency.manifest.id}) v${dependency.manifest.version}',
                        ),
                    ],
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
                  child: const Text('Instalar'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed || !context.mounted) {
      return;
    }

    try {
      final result = await addonInstallController.install(
        addon: addon,
        catalogs: repositoryStoreController.catalogs,
      );
      if (!context.mounted) {
        return;
      }
      if (!result.canInstall) {
        await _showPlanIssues(context, addon, result);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${addon.manifest.name} instalado com sucesso.'),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao instalar ${addon.manifest.name}: $error'),
        ),
      );
    }
  }

  Future<void> _showPlanIssues(
    BuildContext context,
    RepositoryAddonEntry addon,
    AddonInstallPlan plan,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Não foi possível instalar ${addon.manifest.name}'),
          content: SizedBox(
            width: 580,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Dependências ou pacotes necessários estão ausentes:'),
                const SizedBox(height: 10),
                for (final issue in plan.issues)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• ${issue.addonId}: ${issue.message}'),
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
        );
      },
    );
  }

  String _subtitleFor(RepositoryAddonEntry addon) {
    final provider = addon.manifest.providerName.trim();
    final parts = <String>['v${addon.manifest.version}'];
    if (provider.isNotEmpty) {
      parts.add(provider);
    }
    final summary = addon.manifest.summary?.trim();
    if (summary != null && summary.isNotEmpty) {
      parts.add(summary);
    }
    return parts.join(' • ');
  }
}
