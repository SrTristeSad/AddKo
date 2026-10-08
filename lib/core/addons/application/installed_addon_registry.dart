import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../domain/installed_addon.dart';
import '../infrastructure/addon_manifest_parser.dart';

class InstalledAddonRegistry extends ChangeNotifier {
  InstalledAddonRegistry({
    required this.addonsRoot,
    this.manifestParser = const AddonManifestParser(),
  });

  final Directory addonsRoot;
  final AddonManifestParser manifestParser;
  final Map<String, InstalledAddon> _addons = {};

  bool _initialized = false;

  bool get initialized => _initialized;
  List<InstalledAddon> get addons => List.unmodifiable(_addons.values);

  InstalledAddon? byId(String addonId) {
    final exact = _addons[addonId];
    if (exact != null) {
      return exact;
    }

    final normalized = addonId.toLowerCase();
    for (final entry in _addons.entries) {
      if (entry.key.toLowerCase() == normalized) {
        return entry.value;
      }
    }
    return null;
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await refresh();
    _initialized = true;
  }

  Future<void> refresh() async {
    await addonsRoot.create(recursive: true);
    final discovered = <String, InstalledAddon>{};

    await for (final entity in addonsRoot.list(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }

      final folderName = p.basename(entity.path);
      if (folderName.startsWith('.staging-') || folderName.startsWith('.backup-')) {
        continue;
      }

      final manifestFile = File(p.join(entity.path, 'addon.xml'));
      if (!await manifestFile.exists()) {
        continue;
      }

      try {
        final manifest = manifestParser.parse(await manifestFile.readAsString());
        discovered[manifest.id] = InstalledAddon(
          manifest: manifest,
          installPath: entity.path,
        );
      } on Object {
        // A broken directory must not prevent other addons from loading.
      }
    }

    _addons
      ..clear()
      ..addAll(discovered);
    notifyListeners();
  }

  Future<void> remove(String addonId) async {
    final addon = byId(addonId);
    if (addon == null) {
      return;
    }

    final directory = Directory(addon.installPath);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    _addons.remove(addon.manifest.id);
    notifyListeners();
  }
}
