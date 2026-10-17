import 'dart:io';

import 'package:addko/src/plugins/plugin_package.dart';
import 'package:flutter/material.dart';

class AddKoLauncher extends StatelessWidget {
  const AddKoLauncher({
    super.key,
    required this.plugins,
    required this.busy,
    required this.activePluginIds,
    required this.onOpenPlugin,
    required this.onOpenStore,
    required this.onOpenSettings,
    required this.onExit,
  });

  final List<InstalledPlugin> plugins;
  final bool busy;
  final Set<String> activePluginIds;
  final ValueChanged<InstalledPlugin> onOpenPlugin;
  final VoidCallback onOpenStore;
  final VoidCallback onOpenSettings;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _LauncherTopBar(busy: busy),
            Expanded(
              child: plugins.isEmpty && !busy
                  ? const _EmptyLauncher()
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = _columnsForWidth(constraints.maxWidth);
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            crossAxisSpacing: 20,
                            mainAxisSpacing: 20,
                            mainAxisExtent: 292,
                          ),
                          itemCount: plugins.length,
                          itemBuilder: (context, index) {
                            final plugin = plugins[index];
                            return _PluginCard(
                              plugin: plugin,
                              busy: busy,
                              active:
                                  activePluginIds.contains(plugin.manifest.id),
                              onOpen: () => onOpenPlugin(plugin),
                            );
                          },
                        );
                      },
                    ),
            ),
            _LauncherBottomBar(
              onExit: onExit,
              onStore: onOpenStore,
              onSettings: onOpenSettings,
            ),
          ],
        ),
      ),
    );
  }

  static int _columnsForWidth(double width) {
    if (width >= 1280) return 5;
    if (width >= 1000) return 4;
    if (width >= 720) return 3;
    return 2;
  }
}

class AddKoStoreShell extends StatelessWidget {
  const AddKoStoreShell({
    super.key,
    required this.busy,
    required this.onInstallPackage,
  });

  final bool busy;
  final VoidCallback onInstallPackage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Loja'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: ListView(
              padding: const EdgeInsets.all(28),
              children: [
                Text(
                  'Repositórios',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'A loja será formada pelas fontes que você escolher.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 760;
                    return GridView.count(
                      crossAxisCount: wide ? 2 : 1,
                      crossAxisSpacing: 18,
                      mainAxisSpacing: 18,
                      childAspectRatio: wide ? 2.25 : 2.8,
                      physics: const NeverScrollableScrollPhysics(),
                      shrinkWrap: true,
                      children: [
                        _StoreActionCard(
                          icon: Icons.storage_rounded,
                          title: 'Adicionar repositório',
                          subtitle:
                              'Nenhum repositório é adicionado automaticamente.',
                          actionLabel: 'Em breve',
                          onPressed: null,
                        ),
                        _StoreActionCard(
                          icon: Icons.archive_outlined,
                          title: 'Instalar arquivo .addko',
                          subtitle:
                              'Instale manualmente um pacote que você já possui.',
                          actionLabel: 'Escolher arquivo',
                          onPressed: busy ? null : onInstallPackage,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 28),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      children: [
                        Icon(
                          Icons.storefront_outlined,
                          size: 52,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Sua loja ainda está vazia',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Quando o sistema de repositórios entrar, os addons aparecerão aqui em cards, sem alterar a tela inicial do AddKo.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AddKoSettingsShell extends StatelessWidget {
  const AddKoSettingsShell({
    super.key,
    required this.runtimeStatus,
    required this.busy,
    required this.onInstallPackage,
  });

  final String runtimeStatus;
  final bool busy;
  final VoidCallback onInstallPackage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.memory_rounded),
                    title: const Text('Runtime Lua'),
                    subtitle: Text(runtimeStatus),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.archive_outlined),
                    title: const Text('Instalar pacote local'),
                    subtitle: const Text(
                      'Escolha um arquivo .addko no dispositivo.',
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: busy ? null : onInstallPackage,
                      child: const Text('Instalar'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LauncherTopBar extends StatelessWidget {
  const _LauncherTopBar({required this.busy});

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 8),
      child: Row(
        children: [
          Icon(Icons.extension_rounded, color: scheme.primary, size: 34),
          const SizedBox(width: 12),
          Text(
            'AddKo',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          if (busy)
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

class _PluginCard extends StatefulWidget {
  const _PluginCard({
    required this.plugin,
    required this.busy,
    required this.active,
    required this.onOpen,
  });

  final InstalledPlugin plugin;
  final bool busy;
  final bool active;
  final VoidCallback onOpen;

  @override
  State<_PluginCard> createState() => _PluginCardState();
}

class _PluginCardState extends State<_PluginCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final artwork = _pluginArtwork(widget.plugin);

    return FocusableActionDetector(
      onShowFocusHighlight: (focused) {
        if (mounted) setState(() => _focused = focused);
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            if (!widget.busy) widget.onOpen();
            return null;
          },
        ),
      },
      child: AnimatedScale(
        scale: _focused ? 1.035 : 1,
        duration: const Duration(milliseconds: 140),
        child: Card(
          elevation: _focused ? 8 : 1,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(
              color: _focused ? scheme.primary : scheme.outlineVariant,
              width: _focused ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: widget.busy ? null : widget.onOpen,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.plugin.manifest.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'v${widget.plugin.manifest.version}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Center(
                    child: SizedBox.square(
                      dimension: 92,
                      child: artwork == null
                          ? Icon(
                              Icons.extension_rounded,
                              size: 68,
                              color: scheme.primary,
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.file(
                                artwork,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.extension_rounded,
                                  size: 68,
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: widget.busy ? null : widget.onOpen,
                    icon: const Icon(Icons.login_rounded),
                    label: Text(widget.active ? 'REINICIAR' : 'ENTRAR'),
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

class _EmptyLauncher extends StatelessWidget {
  const _EmptyLauncher();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.extension_off_rounded,
              size: 58,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              'Nenhum addon instalado',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Abra a Loja para começar.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _LauncherBottomBar extends StatelessWidget {
  const _LauncherBottomBar({
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

class _StoreActionCard extends StatelessWidget {
  const _StoreActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: scheme.onPrimaryContainer, size: 32),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonal(
              onPressed: onPressed,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

File? _pluginArtwork(InstalledPlugin plugin) {
  const candidates = <String>[
    'assets/icon.png',
    'icon.png',
    'assets/logo.png',
  ];
  for (final relative in candidates) {
    final file = File(
      '${plugin.directory.path}${Platform.pathSeparator}${relative.split('/').join(Platform.pathSeparator)}',
    );
    if (file.existsSync()) return file;
  }
  return null;
}
