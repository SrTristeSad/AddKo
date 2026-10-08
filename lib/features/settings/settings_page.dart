import 'package:flutter/material.dart';

import '../../core/addons/application/addon_install_controller.dart';
import '../../core/runtime/legacy/legacy_service_supervisor.dart';
import 'services_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.addonInstallController,
    required this.serviceSupervisor,
    super.key,
  });

  final AddonInstallController addonInstallController;
  final LegacyServiceSupervisor serviceSupervisor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const _SettingsTile(
            icon: Icons.account_tree_rounded,
            title: 'Repositórios',
            subtitle: 'Origens usadas pela Loja para localizar addons.',
          ),
          const _SettingsTile(
            icon: Icons.extension_rounded,
            title: 'Componentes de addons',
            subtitle: 'InputStream, PVR, VFS e outras dependências instaláveis.',
          ),
          _SettingsTile(
            icon: Icons.settings_input_component_rounded,
            title: 'Serviços',
            subtitle: 'Estado dos addons xbmc.service executados em segundo plano.',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ServicesPage(
                    addonInstallController: addonInstallController,
                    serviceSupervisor: serviceSupervisor,
                  ),
                ),
              );
            },
          ),
          const _SettingsTile(
            icon: Icons.smart_display_rounded,
            title: 'Player',
            subtitle: 'Reprodução, áudio, legendas e decodificação.',
          ),
          const _SettingsTile(
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
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
