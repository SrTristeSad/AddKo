import 'package:flutter/material.dart';

import '../settings/settings_page.dart';
import '../store/store_page.dart';

class LauncherPage extends StatelessWidget {
  const LauncherPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _TopBar(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isLandscape = constraints.maxWidth > constraints.maxHeight;
                  final crossAxisCount = isLandscape
                      ? constraints.maxWidth >= 1100
                          ? 4
                          : 3
                      : constraints.maxWidth >= 700
                          ? 3
                          : 2;

                  return GridView.count(
                    padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 20,
                    childAspectRatio: isLandscape ? 1.22 : 0.82,
                    children: [
                      _LauncherCard(
                        title: 'Loja',
                        subtitle: 'Repositórios e addons',
                        icon: Icons.storefront_rounded,
                        onOpen: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const StorePage(),
                            ),
                          );
                        },
                      ),
                      const _EmptyAddonCard(),
                    ],
                  );
                },
              ),
            ),
            _BottomBar(
              onSettings: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
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
            'Kodi Legacy Runtime • v0.1.0',
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
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onOpen;

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
        scale: _focused ? 1.035 : 1,
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
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const Spacer(),
                  Center(
                    child: Icon(widget.icon, size: 68, color: scheme.primary),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: widget.onOpen,
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('ENTRAR'),
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
  const _EmptyAddonCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.extension_off_rounded,
              size: 56,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum addon instalado',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Use a Loja para adicionar um repositório e instalar plugins.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.logout_rounded),
            label: const Text('SAIR'),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onSettings,
            icon: const Icon(Icons.settings_rounded),
            label: const Text('CONFIGURAÇÕES'),
          ),
        ],
      ),
    );
  }
}
