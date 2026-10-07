import 'dart:async';

import 'package:flutter/material.dart';

import '../core/addons/application/addon_install_controller.dart';
import '../core/repositories/application/repository_registry.dart';
import '../core/repositories/application/repository_store_controller.dart';
import '../core/repositories/infrastructure/shared_preferences_repository_storage.dart';
import '../features/launcher/launcher_page.dart';
import 'addko_theme.dart';

class AddKoApp extends StatefulWidget {
  const AddKoApp({
    this.repositoryRegistry,
    this.repositoryStoreController,
    this.addonInstallController,
    super.key,
  });

  final RepositoryRegistry? repositoryRegistry;
  final RepositoryStoreController? repositoryStoreController;
  final AddonInstallController? addonInstallController;

  @override
  State<AddKoApp> createState() => _AddKoAppState();
}

class _AddKoAppState extends State<AddKoApp> {
  late final RepositoryRegistry _repositoryRegistry;
  late final RepositoryStoreController _repositoryStoreController;
  late final AddonInstallController _addonInstallController;
  late final bool _ownsRepositoryRegistry;
  late final bool _ownsRepositoryStoreController;
  late final bool _ownsAddonInstallController;

  @override
  void initState() {
    super.initState();
    _ownsRepositoryRegistry = widget.repositoryRegistry == null;
    _repositoryRegistry = widget.repositoryRegistry ??
        RepositoryRegistry(
          storage: const SharedPreferencesRepositoryStorage(),
        );

    _ownsRepositoryStoreController = widget.repositoryStoreController == null;
    _repositoryStoreController =
        widget.repositoryStoreController ?? RepositoryStoreController();

    _ownsAddonInstallController = widget.addonInstallController == null;
    _addonInstallController =
        widget.addonInstallController ?? AddonInstallController();

    if (_ownsRepositoryRegistry) {
      unawaited(_initializeRepositoryRegistry());
    }
    unawaited(_addonInstallController.initialize());
  }

  Future<void> _initializeRepositoryRegistry() async {
    try {
      await _repositoryRegistry.initialize();
    } catch (error, stackTrace) {
      debugPrint('Failed to initialize repository registry: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  void dispose() {
    if (_ownsAddonInstallController) {
      _addonInstallController.dispose();
    }
    if (_ownsRepositoryStoreController) {
      _repositoryStoreController.dispose();
    }
    if (_ownsRepositoryRegistry) {
      _repositoryRegistry.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AddKo',
      debugShowCheckedModeBanner: false,
      theme: buildAddKoTheme(),
      home: LauncherPage(
        repositoryRegistry: _repositoryRegistry,
        repositoryStoreController: _repositoryStoreController,
        addonInstallController: _addonInstallController,
      ),
    );
  }
}
