import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../repositories/domain/repository_catalog.dart';
import '../domain/installed_addon.dart';
import '../domain/kodi_host_capabilities.dart';
import '../domain/kodi_version.dart';
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
  Future<void> _mutationTail = Future<void>.value();
  final Set<String> _installing = {};
  String? _initializationError;
  bool _disposed = false;

  bool get initialized => _registry?.initialized ?? false;
  String? get initializationError => _initializationError;
  List<InstalledAddon> get installedAddons => _registry?.addons ?? const [];

  InstalledAddon? installedById(String addonId) => _registry?.byId(addonId);
  bool isInstalling(String addonId) => _installing.contains(addonId.toLowerCase());

  bool hasRequiredDependencies(InstalledAddon addon) {
    return _hasRequiredDependencies(addon, <String>{});
  }

  bool _hasRequiredDependencies(InstalledAddon addon, Set<String> visiting) {
    final addonKey = addon.manifest.id.toLowerCase();
    if (!visiting.add(addonKey)) {
      return true;
    }

    try {
      for (final dependency in addon.manifest.dependencies) {
        if (dependency.optional) {
          continue;
        }

        final hostVersion = KodiHostCapabilities.versionFor(dependency.id);
        if (hostVersion != null) {
          if (!KodiVersion(hostVersion).isAtLeast(dependency.version)) {
            return false;
          }
          continue;
        }

        final installedDependency = installedById(dependency.id);
        if (installedDependency == null ||
            !KodiVersion(installedDependency.manifest.version)
                .isAtLeast(dependency.version) ||
            !_hasRequiredDependencies(installedDependency, visiting)) {
          return false;
        }
      }
      return true;
    } finally {
      visiting.remove(addonKey);
    }
  }

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
    _notifySafely();
  }

  Future<void> refreshInstalled() async {
    await initialize();
    await _runExclusive(() async {
      await _requireRegistry().refresh();
    });
  }

  Future<DirectoryInfo> directories() async {
    final addonsRoot = await _directories.addonsRoot();
    final addonDataRoot = await _directories.addonDataRoot();
    return DirectoryInfo(
      addonsRootPath: addonsRoot.path,
      addonDataRootPath: addonDataRoot.path,
    );
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
    return _runExclusive(() async {
      final registry = _requireRegistry();
      await registry.refresh();
      final plan = buildPlan(addon: addon, catalogs: catalogs);
      if (!plan.canInstall) {
        return plan;
      }
      await _installPlan(plan, registry);
      await registry.refresh();
      return plan;
    });
  }

  Future<LocalPackageInstallResult> installLocalPackage({
    required List<int> bytes,
    required Iterable<RepositoryCatalog> catalogs,
  }) async {
    await initialize();
    return _runExclusive(() async {
      final registry = _requireRegistry();
      await registry.refresh();
      final installed = await _installer.installBytes(
        bytes: bytes,
        addonsRoot: registry.addonsRoot,
      );
      await registry.refresh();

      final root = RepositoryAddonEntry(
        manifest: installed.manifest,
        category: RepositoryAddonCategory.other,
      );
      final dependencyPlan = dependencyResolver.resolve(
        root: root,
        catalogs: catalogs,
        installedAddons: installedAddons,
        installRoot: false,
      );
      if (dependencyPlan.canInstall) {
        await _installPlan(dependencyPlan, registry);
        await registry.refresh();
      }
      return LocalPackageInstallResult(
        addon: registry.byId(installed.manifest.id) ?? installed,
        dependencyPlan: dependencyPlan,
      );
    });
  }

  Future<T> _runExclusive<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _mutationTail = _mutationTail.catchError((Object _) {}).then((_) async {
      if (_disposed) {
        completer.completeError(StateError('AddonInstallController foi encerrado.'));
        return;
      }
      try {
        completer.complete(await action());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _installPlan(
    AddonInstallPlan plan,
    InstalledAddonRegistry registry,
  ) async {
    final touched = <String>{};
    try {
      for (final entry in plan.installOrder) {
        final packageUri = entry.packageUri!;
        final key = entry.manifest.id.toLowerCase();
        touched.add(key);
        _installing.add(key);
        _notifySafely();
        await _installer.installFromUri(
          packageUri: packageUri,
          addonsRoot: registry.addonsRoot,
          expectedAddonId: entry.manifest.id,
          expectedVersion: entry.manifest.version,
        );
        await registry.refresh();
      }
    } finally {
      _installing.removeAll(touched);
      _notifySafely();
    }
  }

  InstalledAddonRegistry _requireRegistry() {
    final registry = _registry;
    if (registry == null) {
      throw AddonInstallException(
        _initializationError ?? 'O registro local de addons não foi iniciado.',
      );
    }
    return registry;
  }

  List<InstalledAddon> requiredBy(String addonId) {
    final normalized = addonId.toLowerCase();
    final dependents = installedAddons.where((installed) {
      return installed.manifest.dependencies.any(
        (dependency) =>
            !dependency.optional && dependency.id.toLowerCase() == normalized,
      );
    }).toList(growable: false)
      ..sort(
        (left, right) => left.manifest.name
            .toLowerCase()
            .compareTo(right.manifest.name.toLowerCase()),
      );
    return dependents;
  }

  Future<void> uninstall(
    String addonId, {
    bool removeData = false,
    bool force = false,
  }) async {
    await initialize();
    await _runExclusive(() async {
      final registry = _requireRegistry();
      await registry.refresh();
      final addon = registry.byId(addonId);
      if (addon == null) {
        return;
      }

      final dependents = requiredBy(addon.manifest.id);
      if (!force && dependents.isNotEmpty) {
        final names = dependents.map((item) => item.manifest.name).take(4).join(', ');
        final more = dependents.length > 4 ? ' e mais ${dependents.length - 4}' : '';
        throw AddonInstallException(
          '${addon.manifest.name} é necessário para: $names$more. Remova esses addons primeiro.',
        );
      }

      await registry.remove(addon.manifest.id);
      if (removeData) {
        final addonDataRoot = await _directories.addonDataRoot();
        final dataDirectory = Directory(p.join(addonDataRoot.path, addon.manifest.id));
        if (await dataDirectory.exists()) {
          await dataDirectory.delete(recursive: true);
        }
      }
    });
  }

  void _relayRegistryChange() => _notifySafely();

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final registry = _registry;
    if (registry != null) {
      registry.removeListener(_relayRegistryChange);
      registry.dispose();
    }
    if (_ownsInstaller) {
      final installer = _installer;
      unawaited(_mutationTail.whenComplete(installer.close));
    }
    super.dispose();
  }
}

class LocalPackageInstallResult {
  const LocalPackageInstallResult({
    required this.addon,
    required this.dependencyPlan,
  });

  final InstalledAddon addon;
  final AddonInstallPlan dependencyPlan;

  bool get dependenciesResolved => dependencyPlan.canInstall;
}

class DirectoryInfo {
  const DirectoryInfo({
    required this.addonsRootPath,
    required this.addonDataRootPath,
  });

  final String addonsRootPath;
  final String addonDataRootPath;
}
