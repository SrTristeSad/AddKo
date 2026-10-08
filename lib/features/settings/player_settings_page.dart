import 'package:flutter/material.dart';

import '../../core/player/playback_host_controller.dart';

class PlayerSettingsPage extends StatelessWidget {
  const PlayerSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final host = PlaybackHostController.shared;

    return Scaffold(
      appBar: AppBar(title: const Text('Player')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _PlayerStatusCard(
            icon: Icons.smart_display_rounded,
            title: 'Backend de reprodução',
            detail: 'media_kit • HLS/DASH/HTTP/local',
            ok: true,
          ),
          _PlayerStatusCard(
            icon: Icons.link_rounded,
            title: 'Ponte global do player',
            detail: host.isAttached
                ? 'Um player está ativo e pode receber comandos de addons.'
                : 'Nenhum player está aberto no momento.',
            ok: host.isAttached,
            neutralWhenFalse: true,
          ),
          const _PlayerStatusCard(
            icon: Icons.subtitles_rounded,
            title: 'Legendas',
            detail: 'Suporte básico disponível; integração completa com comandos Kodi ainda será ampliada.',
            ok: true,
          ),
          const _PlayerStatusCard(
            icon: Icons.memory_rounded,
            title: 'InputStream/DRM',
            detail: 'Metadados já são reconhecidos. O host binário Kodi ABI ainda está pendente.',
            ok: false,
            neutralWhenFalse: true,
          ),
        ],
      ),
    );
  }
}

class _PlayerStatusCard extends StatelessWidget {
  const _PlayerStatusCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.ok,
    this.neutralWhenFalse = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool ok;
  final bool neutralWhenFalse;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = ok
        ? scheme.primary
        : neutralWhenFalse
            ? scheme.onSurfaceVariant
            : scheme.error;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.12),
          child: Icon(icon, color: statusColor),
        ),
        title: Text(title),
        subtitle: Text(detail),
        trailing: Icon(
          ok
              ? Icons.check_circle_rounded
              : neutralWhenFalse
                  ? Icons.info_outline_rounded
                  : Icons.error_outline_rounded,
          color: statusColor,
        ),
      ),
    );
  }
}
