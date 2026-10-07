import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          _SettingsTile(
            icon: Icons.account_tree_rounded,
            title: 'Repositórios',
            subtitle: 'Origens usadas pela Loja para localizar addons.',
          ),
          _SettingsTile(
            icon: Icons.extension_rounded,
            title: 'Componentes de addons',
            subtitle: 'InputStream, PVR, VFS e outras dependências instaláveis.',
          ),
          _SettingsTile(
            icon: Icons.smart_display_rounded,
            title: 'Player',
            subtitle: 'Reprodução, áudio, legendas e decodificação.',
          ),
          _SettingsTile(
            icon: Icons.history_rounded,
            title: 'Compatibilidade Kodi',
            subtitle: 'Estado do runtime legado e APIs xbmc.',
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}
