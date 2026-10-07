import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../repositories/domain/repository_catalog.dart';
import '../domain/installed_addon.dart';
import '../infrastructure/addon_directories.dart';
import '../infrastructure/addon_package_installer.dart';
import 'addon_dependency_resolver.dart';
import 'installed_addon_registry.dart';

class AddonInstallController extends ChangeNotifier {
  AddonInstallController({
    AddonDirectories? directories,
    AddonPackageInstaller? installer,
    this.dependencyResolver = const AddonDependencyResolver(),
  })  : _directories = directories ?? AddonDirectories(),
        _installer = installer ?? AddonPackageInstaller(),
        _ownsInstaller = installer == null;

  final AddonDirectories _directories;
  final AddonPackageInstaller _installer;
  final bool _ownsInstaller;
  final AddonDependencyResolver dependencyResolver;

  InstalledAddonRegistry? _registry;
  Future<void>? _initialization;
  final Set<String> _installing = {};
  String? _initializationError;

  bool get initialized => _registry?.initialized ?? false;
  String? get initializationError => _initializationError;
  List<InstalledAddon> get installedAddons => _registry?.addons ?? const [];

  InstalledAddon? installedById(String addonId) => _registry?.byId(addonId);
  bool isInstalling(String addonId) => _installing.contains(addonId);

  Future<void> initialize() {
    return _initialization ??= _initializeInternal();
  }

  Future<void> _initializeInternal() async {
    try {
      final root = await _directories.addonsRoot();
      final registry = InstalledAddonRegistry(addonsRoot: root);
      registry.addListener(_relayRegistryChange);
      await registry.initialize();
      _registry = registry;
      _initializationError = null;
    } on Object catch (error) {
      _initializationError = error.toString();
    }
    notifyListeners();
  }

  AddonInstallPlan buildPlan({
    required RepositoryAddonEntry addon,
    required Iterable<RepositoryCatalog> catalogs,
  }) {
    return dependencyResolver.resolve(
      root: addon,
      catalogs: catalogs,
      installedAddons: installedAddons,
    );
  }

  Future<AddonInstallPlan> install({
    required RepositoryAddonEntry addon,
    required Iterable<RepositoryCatalog> catalogs,
  }) async {
    await initialize();
    final registry = _registry;
    if (registry == null) {
      throw AddonInstallException(
        _initializationError ?? 'O registro local de addons não foi iniciado.',
      );
    }

    final plan = buildPlan(addon: addon, catalogs: catalogs);
    if (!plan.canInstall) {
      return plan;
    }

    final root = registry.addonsRoot;
    try {
      for (final entry in plan.installOrder) {
        final packageUri = entry.packageUri!;
        _installing.add(entry.manifest.id);
        notifyListeners();

        await _installer.installFromUri(
          packageUri: packageUri,
          addonsRoot: root,
          expectedAddonId: entry.manifest.id,
          expectedVersion: entry.manifest.version,
        );
        await registry.refresh();
      }
    } finally {
      for (final entry in plan.installOrder) {
        _installing.remove(entry.manifest.id);
      }
      notifyListeners();
    }

    return plan;
  }

  Future<void> uninstall(String addonId) async {
    await initialize();
    await _registry?.remove(addonId);
  }

  void _relayRegistryChange() {
    notifyListeners();
  }

  @override
  void dispose() {
    final registry = _registry;
    if (registry != null) {
      registry.removeListener(_relayRegistryChange);
      registry.dispose();
    }
    if (_ownsInstaller) {
      _installer.close();
    }
    super.dispose();
  }
}
