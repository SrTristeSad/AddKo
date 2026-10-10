import '../kodi/kodi_core_page.dart';
import '../../core/runtime/kodi/kodi_core.dart';

import 'package:flutter/material.dart';

import '../../core/addons/application/addon_install_controller.dart';
import '../../core/repositories/application/repository_registry.dart';
import '../../core/repositories/application/repository_store_controller.dart';
import '../../core/runtime/legacy/legacy_service_supervisor.dart';
import '../store/store_page.dart';
import 'addon_manager_page.dart';
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
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Configurações')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (KodiCore.supported)
          _tile(
            c,
            Icons.play_circle,
            'Núcleo Kodi',
            'Kodi 21.3, addons e player nativos.',
            () => const KodiCorePage(),
          ),
        _tile(
          c,
          Icons.apps_rounded,
          'Addons instalados',
          'Gerenciar e desinstalar addons.',
          () =>
              AddonManagerPage(addonInstallController: addonInstallController),
        ),
        _tile(
          c,
          Icons.account_tree_rounded,
          'Repositórios',
          'Origens usadas pela Loja.',
          () => StorePage(
            repositoryRegistry: repositoryRegistry,
            repositoryStoreController: repositoryStoreController,
            addonInstallController: addonInstallController,
          ),
        ),
        _tile(
          c,
          Icons.extension_rounded,
          'Componentes de addons',
          'Módulos, serviços, InputStream, PVR e VFS.',
          () => ComponentsPage(addonInstallController: addonInstallController),
        ),
        _tile(
          c,
          Icons.settings_input_component_rounded,
          'Serviços',
          'Estado dos addons xbmc.service.',
          () => ServicesPage(
            addonInstallController: addonInstallController,
            serviceSupervisor: serviceSupervisor,
          ),
        ),
        _tile(
          c,
          Icons.smart_display_rounded,
          'Player',
          'Backend de reprodução.',
          () => const PlayerSettingsPage(),
        ),
        _tile(
          c,
          Icons.history_rounded,
          'Compatibilidade Kodi',
          'Runtime legado e CPython embarcado.',
          () => const CompatibilityPage(),
        ),
      ],
    ),
  );
  Widget _tile(
    BuildContext c,
    IconData i,
    String t,
    String s,
    Widget Function() page,
  ) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      leading: Icon(i),
      title: Text(t),
      subtitle: Text(s),
      trailing: const Icon(Icons.chevron_right),
      onTap: () =>
          Navigator.of(c).push(MaterialPageRoute(builder: (_) => page())),
    ),
  );
}
