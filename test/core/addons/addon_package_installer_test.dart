import 'dart:convert';
import 'dart:io';

import 'package:addko/core/addons/infrastructure/addon_package_installer.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('installs a Kodi addon ZIP into its addon id directory', () async {
    final root = await Directory.systemTemp.createTemp('addko-installer-');
    addTearDown(() => root.delete(recursive: true));

    final bytes = _zip({
      'plugin.video.demo/addon.xml': _manifest('plugin.video.demo', '1.0.0'),
      'plugin.video.demo/default.py': 'print("hello")',
    });

    final installer = AddonPackageInstaller();
    addTearDown(installer.close);

    final installed = await installer.installBytes(
      bytes: bytes,
      addonsRoot: root,
      expectedAddonId: 'plugin.video.demo',
      expectedVersion: '1.0.0',
    );

    expect(installed.manifest.id, 'plugin.video.demo');
    expect(
      File(p.join(root.path, 'plugin.video.demo', 'default.py')).existsSync(),
      isTrue,
    );
  });

  test('replaces an existing addon even when only id casing changed', () async {
    final root = await Directory.systemTemp.createTemp('addko-installer-');
    addTearDown(() => root.delete(recursive: true));

    final existing = Directory(p.join(root.path, 'plugin.video.BrazucaPlay.Matrix'));
    await existing.create(recursive: true);
    await File(p.join(existing.path, 'addon.xml')).writeAsString(
      _manifest('plugin.video.BrazucaPlay.Matrix', '1.0.0'),
    );
    await File(p.join(existing.path, 'old.txt')).writeAsString('old');

    final installer = AddonPackageInstaller();
    addTearDown(installer.close);
    final installed = await installer.installBytes(
      bytes: _zip({
        'plugin.video.brazucaplay.matrix/addon.xml':
            _manifest('plugin.video.brazucaplay.matrix', '2.0.0'),
        'plugin.video.brazucaplay.matrix/default.py': 'print("new")',
      }),
      addonsRoot: root,
      expectedAddonId: 'plugin.video.BrazucaPlay.Matrix',
      expectedVersion: '2.0.0',
    );

    expect(installed.installPath, existing.path);
    expect(File(p.join(existing.path, 'old.txt')).existsSync(), isFalse);
    expect(File(p.join(existing.path, 'default.py')).existsSync(), isTrue);
  });

  test('rejects ZIP traversal outside the addon root', () async {
    final root = await Directory.systemTemp.createTemp('addko-installer-');
    addTearDown(() => root.delete(recursive: true));

    final bytes = _zip({
      'plugin.video.demo/addon.xml': _manifest('plugin.video.demo', '1.0.0'),
      'plugin.video.demo/../escaped.txt': 'nope',
    });

    final installer = AddonPackageInstaller();
    addTearDown(installer.close);

    await expectLater(
      installer.installBytes(bytes: bytes, addonsRoot: root),
      throwsA(isA<AddonInstallException>()),
    );
    expect(File(p.join(root.parent.path, 'escaped.txt')).existsSync(), isFalse);
  });

  test('rejects a package whose id differs from repository metadata', () async {
    final root = await Directory.systemTemp.createTemp('addko-installer-');
    addTearDown(() => root.delete(recursive: true));

    final installer = AddonPackageInstaller();
    addTearDown(installer.close);

    await expectLater(
      installer.installBytes(
        bytes: _zip({
          'plugin.video.evil/addon.xml': _manifest('plugin.video.evil', '1.0.0'),
        }),
        addonsRoot: root,
        expectedAddonId: 'plugin.video.expected',
      ),
      throwsA(isA<AddonInstallException>()),
    );
  });
}

List<int> _zip(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final content = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, content.length, content));
  }
  return ZipEncoder().encode(archive)!;
}

String _manifest(String id, String version) => '''
<addon id="$id" name="Demo" version="$version" provider-name="AddKo">
  <requires><import addon="xbmc.python" version="3.0.0" /></requires>
  <extension point="xbmc.python.pluginsource" library="default.py">
    <provides>video</provides>
  </extension>
</addon>
''';
