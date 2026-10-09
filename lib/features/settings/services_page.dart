import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/addons/application/addon_install_controller.dart';
import '../../core/addons/domain/installed_addon.dart';
import '../../core/runtime/legacy/legacy_service_supervisor.dart';

class ServicesPage extends StatelessWidget {
  const ServicesPage({
    required this.addonInstallController,
    required this.serviceSupervisor,
    super.key,
  });

  final AddonInstallController addonInstallController;
  final LegacyServiceSupervisor serviceSupervisor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Serviços'),
        actions: [
          IconButton(
            tooltip: 'Reverificar serviços',
            onPressed: () => unawaited(serviceSupervisor.reconcile()),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          addonInstallController,
          serviceSupervisor,
        ]),
        builder: (context, _) {
          final services = addonInstallController.installedAddons
              .where((addon) => addon.manifest.isPythonService)
              .toList(growable: false)
            ..sort((a, b) => a.manifest.name.compareTo(b.manifest.name));

          if (services.isEmpty) {
            return const _EmptyServices();
          }

          final running = serviceSupervisor.runningAddonIds.toSet();
          final errors = serviceSupervisor.errors;
          final runningCount = services
              .where((addon) => running.contains(addon.manifest.id))
              .length;
          final failedCount = services
              .where((addon) => errors.containsKey(addon.manifest.id))
              .length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            children: [
              _ServiceSummary(
                total: services.length,
                running: runningCount,
                failed: failedCount,
              ),
              const SizedBox(height: 18),
              for (final addon in services)
                _ServiceCard(
                  addon: addon,
                  running: running.contains(addon.manifest.id),
                  error: errors[addon.manifest.id],
                  onRestart: () => unawaited(
                    serviceSupervisor.restart(addon.manifest.id),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ServiceSummary extends StatelessWidget {
  const _ServiceSummary({
    required this.total,
    required this.running,
    required this.failed,
  });

  final int total;
  final int running;
  final int failed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(
          spacing: 22,
          runSpacing: 12,
          children: [
            _Metric(
              icon: Icons.settings_input_component_rounded,
              value: total,
              label: 'Instalados',
            ),
            _Metric(
              icon: Icons.play_circle_fill_rounded,
              value: running,
              label: 'Rodando',
            ),
            _Metric(
              icon: failed == 0 ? Icons.check_circle_rounded : Icons.error_rounded,
              value: failed,
              label: 'Com falha',
              foreground: failed == 0 ? null : scheme.error,
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.value,
    required this.label,
    this.foreground,
  });

  final IconData icon;
  final int value;
  final String label;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final color = foreground ?? Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Text(
          '$value',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
              ),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.addon,
    required this.running,
    required this.error,
    required this.onRestart,
  });

  final InstalledAddon addon;
  final bool running;
  final String? error;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasError = error != null && error!.trim().isNotEmpty;
    final statusLabel = hasError
        ? 'Falhou'
        : running
            ? 'Rodando'
            : 'Parado';
    final statusIcon = hasError
        ? Icons.error_rounded
        : running
            ? Icons.play_circle_fill_rounded
            : Icons.pause_circle_outline_rounded;
    final statusColor = hasError
        ? scheme.error
        : running
            ? scheme.primary
            : scheme.onSurfaceVariant;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(statusIcon, color: statusColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    addon.manifest.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${addon.manifest.id} • v${addon.manifest.version}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(statusIcon, size: 17, color: statusColor),
                      const SizedBox(width: 6),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  if (hasError) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      error!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.error,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton.filledTonal(
              tooltip: running ? 'Reiniciar serviço' : 'Tentar iniciar serviço',
              onPressed: onRestart,
              icon: const Icon(Icons.restart_alt_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyServices extends StatelessWidget {
  const _EmptyServices();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.settings_input_component_rounded,
                size: 68,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Nenhum serviço Kodi instalado',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Addons xbmc.service instalados pela Loja aparecerão aqui e serão iniciados automaticamente pelo AddKo.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
