import 'dart:io';

import 'package:addko/core/addons/application/installed_addon_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('restores an orphan backup and removes stale staging on startup', () async {
    final root = await Directory.systemTemp.createTemp('addko-registry-recovery-');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final backup = Directory(
      p.join(root.path, '.backup-plugin.video.demo-123'),
    );
    await backup.create(recursive: true);
    await File(p.join(backup.path, 'addon.xml')).writeAsString('''
<addon id="plugin.video.demo" name="Demo" version="1.0.0" provider-name="AddKo">
  <requires><import addon="xbmc.python" version="3.0.0" /></requires>
  <extension point="xbmc.python.pluginsource" library="default.py"><provides>video</provides></extension>
</addon>
''');
    await File(p.join(backup.path, 'default.py')).writeAsString('print("ok")');

    final staging = Directory(
      p.join(root.path, '.staging-plugin.video.demo-456'),
    );
    await staging.create(recursive: true);
    await File(p.join(staging.path, 'partial.txt')).writeAsString('partial');

    final registry = InstalledAddonRegistry(addonsRoot: root);
    addTearDown(registry.dispose);
    await registry.initialize();

    final restored = registry.byId('PLUGIN.VIDEO.DEMO');
    expect(restored, isNotNull);
    expect(
      File(p.join(root.path, 'plugin.video.demo', 'default.py')).existsSync(),
      isTrue,
    );
    expect(await backup.exists(), isFalse);
    expect(await staging.exists(), isFalse);
  });
}
