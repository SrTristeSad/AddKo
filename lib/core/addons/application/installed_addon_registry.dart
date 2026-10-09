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
  final Map<String, String> _normalizedIds = {};

  bool _initialized = false;

  bool get initialized => _initialized;
  List<InstalledAddon> get addons => List.unmodifiable(_addons.values);

  InstalledAddon? byId(String addonId) {
    final exact = _addons[addonId];
    if (exact != null) {
      return exact;
    }

    final canonicalId = _normalizedIds[addonId.toLowerCase()];
    return canonicalId == null ? null : _addons[canonicalId];
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await addonsRoot.create(recursive: true);
    await _recoverInterruptedInstalls();
    await refresh();
    _initialized = true;
  }

  Future<void> _recoverInterruptedInstalls() async {
    final backups = <Directory>[];
    final staleStaging = <Directory>[];

    await for (final entity in addonsRoot.list(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      final name = p.basename(entity.path);
      if (name.startsWith('.backup-')) {
        backups.add(entity);
      } else if (name.startsWith('.staging-')) {
        staleStaging.add(entity);
      }
    }

    for (final staging in staleStaging) {
      try {
        if (await staging.exists()) {
          await staging.delete(recursive: true);
        }
      } on FileSystemException {
        // Best effort cleanup. A later launch can retry.
      }
    }

    for (final backup in backups) {
      final manifestFile = File(p.join(backup.path, 'addon.xml'));
      if (!await manifestFile.exists()) {
        await _deleteQuietly(backup);
        continue;
      }

      try {
        final manifest = manifestParser.parse(await manifestFile.readAsString());
        final target = Directory(p.join(addonsRoot.path, manifest.id));
        if (await target.exists()) {
          await _deleteQuietly(backup);
          continue;
        }
        await backup.rename(target.path);
      } on Object {
        // Never make startup fail because recovery data itself is damaged.
      }
    }
  }

  Future<void> _deleteQuietly(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on FileSystemException {
      // Best effort cleanup.
    }
  }

  Future<void> refresh() async {
    await addonsRoot.create(recursive: true);
    final discovered = <String, InstalledAddon>{};
    final normalized = <String, String>{};

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
        final normalizedId = manifest.id.toLowerCase();
        final existingId = normalized[normalizedId];
        if (existingId != null) {
          // Keep one logical addon even if a broken repository changed only the
          // casing of the folder/id between releases.
          final existing = discovered.remove(existingId);
          if (existing != null) {
            final existingDirectory = Directory(existing.installPath);
            if (existingDirectory.path != entity.path) {
              // Prefer the most recently discovered valid package. Do not
              // delete here; the package installer handles replacement safely.
            }
          }
        }

        discovered[manifest.id] = InstalledAddon(
          manifest: manifest,
          installPath: entity.path,
        );
        normalized[normalizedId] = manifest.id;
      } on Object {
        // A broken directory must not prevent other addons from loading.
      }
    }

    _addons
      ..clear()
      ..addAll(discovered);
    _normalizedIds
      ..clear()
      ..addAll(normalized);
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
    _normalizedIds.remove(addon.manifest.id.toLowerCase());
    notifyListeners();
  }
}
