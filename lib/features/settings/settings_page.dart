import 'package:flutter/material.dart';

import '../../core/addons/application/addon_install_controller.dart';
import '../../core/repositories/application/repository_registry.dart';
import '../../core/repositories/application/repository_store_controller.dart';
import '../../core/runtime/legacy/legacy_service_supervisor.dart';
import '../store/store_page.dart';
import 'compatibility_page.dart';
import 'components_page.dart';
import 'player_settings_page.dart';
import 'services_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.repositoryRegistry,
    required this.repositoryStoreController,
    required this.addonInstallController,
    required this.serviceSupervisor,
    super.key,
  });

  final RepositoryRegistry repositoryRegistry;
  final RepositoryStoreController repositoryStoreController;
  final AddonInstallController addonInstallController;
  final LegacyServiceSupervisor serviceSupervisor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _SettingsTile(
            icon: Icons.account_tree_rounded,
            title: 'Repositórios',
            subtitle: 'Origens usadas pela Loja para localizar addons.',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StorePage(
                    repositoryRegistry: repositoryRegistry,
                    repositoryStoreController: repositoryStoreController,
                    addonInstallController: addonInstallController,
                  ),
                ),
              );
            },
          ),
          _SettingsTile(
            icon: Icons.extension_rounded,
            title: 'Componentes de addons',
            subtitle: 'Módulos, serviços, InputStream, PVR, VFS e dependências instaladas.',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ComponentsPage(
                    addonInstallController: addonInstallController,
                  ),
                ),
              );
            },
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
          _SettingsTile(
            icon: Icons.smart_display_rounded,
            title: 'Player',
            subtitle: 'Estado do backend de reprodução e integrações Kodi.',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PlayerSettingsPage(),
                ),
              );
            },
          ),
          _SettingsTile(
            icon: Icons.history_rounded,
            title: 'Compatibilidade Kodi',
            subtitle: 'Runtime legado, host nativo e estado do CPython embarcado.',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CompatibilityPage(),
                ),
              );
            },
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
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

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
