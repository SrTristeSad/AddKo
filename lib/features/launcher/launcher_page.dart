import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../core/addons/application/addon_install_controller.dart';
import '../../core/addons/domain/installed_addon.dart';
import '../../core/repositories/application/repository_registry.dart';
import '../../core/repositories/application/repository_store_controller.dart';
import '../../core/runtime/legacy/legacy_plugin_runtime.dart';
import '../../core/runtime/legacy/legacy_service_supervisor.dart';
import '../../core/ui/kodi_text.dart';
import '../legacy/legacy_addon_page.dart';
import '../legacy/legacy_flutter_ui_bridge.dart';
import '../settings/settings_page.dart';
import '../store/store_page.dart';

class LauncherPage extends StatelessWidget {
  const LauncherPage({
    required this.repositoryRegistry,
    required this.repositoryStoreController,
    required this.addonInstallController,
    required this.serviceSupervisor,
    this.onExitRequested,
    super.key,
  });

  final RepositoryRegistry repositoryRegistry;
  final RepositoryStoreController repositoryStoreController;
  final AddonInstallController addonInstallController;
  final LegacyServiceSupervisor serviceSupervisor;
  final Future<void> Function()? onExitRequested;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _TopBar(),
            Expanded(
              child: AnimatedBuilder(
                animation: addonInstallController,
                builder: (context, _) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final isLandscape =
                          constraints.maxWidth > constraints.maxHeight;
                      final crossAxisCount = isLandscape
                          ? constraints.maxWidth >= 1700
                              ? 4
                              : 3
                          : constraints.maxWidth >= 700
                              ? 3
                              : 2;

                      final launchable = addonInstallController.installedAddons
                          .where(
                            (addon) =>
                                addon.manifest.isPythonPlugin &&
                                addonInstallController
                                    .hasRequiredDependencies(addon),
                          )
                          .toList(growable: false);

                      return GridView.count(
                        padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 20,
                        mainAxisSpacing: 20,
                        childAspectRatio: isLandscape ? 1.05 : 0.78,
                        children: [
                          for (final addon in launchable)
                            _installedAddonCard(context, addon),
                          if (launchable.isEmpty)
                            _EmptyAddonCard(
                              initializationError:
                                  addonInstallController.initializationError,
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            _BottomBar(
              onExit: () => unawaited(_exitApp()),
              onStore: () => _openStore(context),
              onSettings: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsPage(
                      repositoryRegistry: repositoryRegistry,
                      repositoryStoreController: repositoryStoreController,
                      addonInstallController: addonInstallController,
                      serviceSupervisor: serviceSupervisor,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openStore(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StorePage(
          repositoryRegistry: repositoryRegistry,
          repositoryStoreController: repositoryStoreController,
          addonInstallController: addonInstallController,
        ),
      ),
    );
  }

  Future<void> _exitApp() async {
    await onExitRequested?.call();
    if (Platform.isAndroid || Platform.isIOS) {
      await SystemNavigator.pop();
      return;
    }
    exit(0);
  }

  Widget _installedAddonCard(BuildContext context, InstalledAddon addon) {
    final iconPath = addon.manifest.iconPath ?? 'icon.png';
    final iconFile = File(p.join(addon.installPath, iconPath));

    return _LauncherCard(
      title: addon.manifest.name,
      subtitle: '${addon.manifest.id} • v${addon.manifest.version}',
      icon: Icons.extension_rounded,
      artwork: iconFile.existsSync()
          ? Image.file(
              iconFile,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.extension_rounded,
                size: 62,
              ),
            )
          : null,
      onOpen: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => LegacyAddonPage(
              addon: addon,
              runtime: LegacyPluginRuntime(
                addonInstallController: addonInstallController,
                requestHandler: (request) =>
                    LegacyFlutterUiBridge.handle(context, request),
              ),
              repositoryRegistry: repositoryRegistry,
              repositoryStoreController: repositoryStoreController,
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 8),
      child: Row(
        children: [
          Icon(
            Icons.extension_rounded,
            color: Theme.of(context).colorScheme.primary,
            size: 34,
          ),
          const SizedBox(width: 12),
          Text(
            'AddKo',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const Spacer(),
          Text(
            'Kodi Omega Runtime • v0.1.9',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _LauncherCard extends StatefulWidget {
  const _LauncherCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onOpen,
    this.artwork,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onOpen;
  final Widget? artwork;

  @override
  State<_LauncherCard> createState() => _LauncherCardState();
}

class _LauncherCardState extends State<_LauncherCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return FocusableActionDetector(
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onOpen();
            return null;
          },
        ),
      },
      child: AnimatedScale(
        scale: _focused ? 1.025 : 1,
        duration: const Duration(milliseconds: 140),
        child: Card(
          elevation: _focused ? 8 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(
              color: _focused ? scheme.primary : scheme.outlineVariant,
              width: _focused ? 2 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: widget.onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KodiText(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    widget.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Center(
                      child: SizedBox(
                        width: 112,
                        height: 92,
                        child: widget.artwork ??
                            Icon(widget.icon, size: 62, color: scheme.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 42,
                    child: FilledButton.icon(
                      onPressed: widget.onOpen,
                      icon: const Icon(Icons.login_rounded, size: 19),
                      label: const Text('ENTRAR'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyAddonCard extends StatelessWidget {
  const _EmptyAddonCard({this.initializationError});

  final String? initializationError;

  @override
  Widget build(BuildContext context) {
    final hasError = initializationError?.trim().isNotEmpty == true;
    return Card(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasError
                    ? Icons.error_outline_rounded
                    : Icons.extension_off_rounded,
                size: 52,
              ),
              const SizedBox(height: 16),
              Text(
                hasError
                    ? 'Falha ao carregar addons'
                    : 'Nenhum addon pronto para executar',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                hasError
                    ? initializationError!
                    : 'Abra a Loja para instalar ou corrigir addons e dependências.',
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.onExit,
    required this.onStore,
    required this.onSettings,
  });

  final VoidCallback onExit;
  final VoidCallback onStore;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: 'Sair',
            onPressed: onExit,
            icon: const Icon(Icons.logout_rounded),
          ),
          const Spacer(),
          IconButton.filled(
            tooltip: 'Loja',
            onPressed: onStore,
            icon: const Icon(Icons.storefront_rounded),
          ),
          const SizedBox(width: 14),
          IconButton.filledTonal(
            tooltip: 'Configurações',
            onPressed: onSettings,
            icon: const Icon(Icons.settings_rounded),
          ),
        ],
      ),
    );
  }
}
