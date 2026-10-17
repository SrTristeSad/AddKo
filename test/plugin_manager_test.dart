import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:addko/src/plugins/plugin_manager.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late PluginManager manager;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('addko-plugin-test-');
    manager = PluginManager(root);
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('installs a valid .addko package and discovers it', () async {
    final installed = await manager.installBytes(
      _package(
        manifest: _manifest(version: '1.0.0'),
        files: <String, String>{
          'main.lua': 'return "hello"',
          'assets/readme.txt': 'asset',
        },
      ),
    );

    expect(installed.manifest.id, 'com.addko.test');
    expect(await installed.entryFile.exists(), isTrue);

    final plugins = await manager.listInstalled();
    expect(plugins, hasLength(1));
    expect(plugins.single.manifest.version, '1.0.0');
  });

  test('replaces an existing plugin only after staging succeeds', () async {
    await manager.installBytes(
      _package(
        manifest: _manifest(version: '1.0.0'),
        files: <String, String>{'main.lua': 'return "one"'},
      ),
    );

    await manager.installBytes(
      _package(
        manifest: _manifest(version: '2.0.0'),
        files: <String, String>{'main.lua': 'return "two"'},
      ),
    );

    final plugins = await manager.listInstalled();
    expect(plugins, hasLength(1));
    expect(plugins.single.manifest.version, '2.0.0');
    expect(await plugins.single.entryFile.readAsString(), 'return "two"');
  });

  test('rejects path traversal before writing files', () async {
    final archive = Archive()
      ..add(ArchiveFile.string('manifest.json', jsonEncode(_manifest())))
      ..add(ArchiveFile.string('main.lua', 'return true'))
      ..add(ArchiveFile.string('../escape.txt', 'nope'));

    expect(
      () => manager.installBytes(ZipEncoder().encodeBytes(archive)),
      throwsA(isA<PluginPackageException>()),
    );

    final escaped = File(
      '${root.parent.path}${Platform.pathSeparator}escape.txt',
    );
    expect(await escaped.exists(), isFalse);
  });

  test('rejects package whose declared entrypoint is missing', () async {
    expect(
      () => manager.installBytes(
        _package(
          manifest: _manifest(),
          files: <String, String>{'other.lua': 'return false'},
        ),
      ),
      throwsA(isA<PluginPackageException>()),
    );
  });

  test('rejects symbolic links', () async {
    final archive = Archive()
      ..add(ArchiveFile.string('manifest.json', jsonEncode(_manifest())))
      ..add(ArchiveFile.string('main.lua', 'return true'))
      ..add(ArchiveFile.symlink('assets/link', '../../outside'));

    expect(
      () => manager.installBytes(ZipEncoder().encodeBytes(archive)),
      throwsA(isA<PluginPackageException>()),
    );
  });
}

Map<String, Object?> _manifest({String version = '1.0.0'}) {
  return <String, Object?>{
    'id': 'com.addko.test',
    'name': 'Test Plugin',
    'version': version,
    'entry': 'main.lua',
    'permissions': <Object?>[],
  };
}

Uint8List _package({
  required Map<String, Object?> manifest,
  required Map<String, String> files,
}) {
  final archive = Archive()
    ..add(ArchiveFile.string('manifest.json', jsonEncode(manifest)));

  for (final entry in files.entries) {
    archive.add(ArchiveFile.string(entry.key, entry.value));
  }

  return ZipEncoder().encodeBytes(archive);
}
