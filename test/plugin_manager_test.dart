import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:addko/src/plugins/plugin_manager.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory sandbox;
  late PluginManager manager;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('addko-plugin-test-');
    root = Directory('${sandbox.path}${Platform.pathSeparator}plugins');
    await root.create();
    manager = PluginManager(root);
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
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


  test('uninstall preserves private data unless explicitly cleared', () async {
    await manager.installBytes(
      _package(
        manifest: _manifest(),
        files: <String, String>{'main.lua': 'return 1'},
      ),
    );
    final data = Directory(
      '${sandbox.path}${Platform.pathSeparator}plugin-data'
      '${Platform.pathSeparator}com.addko.test',
    );
    await data.create(recursive: true);
    final settings = File('${data.path}${Platform.pathSeparator}favorites.json');
    await settings.writeAsString('{"items":[1]}');

    await manager.uninstall('com.addko.test');
    expect(await manager.listInstalled(), isEmpty);
    expect(await settings.readAsString(), '{"items":[1]}');

    await manager.installBytes(
      _package(
        manifest: _manifest(),
        files: <String, String>{'main.lua': 'return 2'},
      ),
    );
    expect(await settings.readAsString(), '{"items":[1]}');

    await manager.uninstall('com.addko.test', deleteData: true);
    expect(await data.exists(), isFalse);
    expect(await manager.listInstalled(), isEmpty);
  });

  test('uninstall refuses addon required by another installed addon',
      () async {
    await manager.installBytes(
      _package(
        manifest: _manifest(),
        files: <String, String>{'main.lua': 'return 1'},
      ),
    );
    await manager.installBytes(
      _package(
        manifest: <String, Object?>{
          ..._manifest(),
          'id': 'com.addko.client',
          'name': 'Client',
          'dependencies': <Object?>['com.addko.test'],
        },
        files: <String, String>{'main.lua': 'return 2'},
      ),
    );
    expect((await manager.dependentsOf('com.addko.test')).single.manifest.id,
        'com.addko.client');
    await expectLater(
      manager.uninstall('com.addko.test'),
      throwsA(isA<PluginPackageException>()),
    );
    expect(await manager.listInstalled(), hasLength(2));
    await manager.uninstall('com.addko.client');
    await manager.uninstall('com.addko.test');
    expect(await manager.listInstalled(), isEmpty);
  });

  test('uninstall blocks unsafe IDs and symbolic-link data directories',
      () async {
    await expectLater(
      manager.uninstall('../evil'),
      throwsA(isA<PluginPackageException>()),
    );
    await manager.installBytes(
      _package(
        manifest: _manifest(),
        files: <String, String>{'main.lua': 'return 1'},
      ),
    );
    final data = Directory(
      '${sandbox.path}${Platform.pathSeparator}plugin-data'
      '${Platform.pathSeparator}com.addko.test',
    );
    await data.parent.create(recursive: true);
    final outside = await Directory.systemTemp.createTemp('addko-outside-');
    try {
      await Link(data.path).create(outside.path);
      await expectLater(
        manager.uninstall('com.addko.test', deleteData: true),
        throwsA(isA<PluginPackageException>()),
      );
      expect(await outside.exists(), isTrue);
      expect(await manager.listInstalled(), hasLength(1));
    } finally {
      if (await Link(data.path).exists()) await Link(data.path).delete();
      await outside.delete(recursive: true);
    }
  });

  test('rejects symbolic links', () async {
    expect(
      () => manager.installBytes(base64Decode(_symlinkPackageBase64)),
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

const _symlinkPackageBase64 =
    'UEsDBBQAAAAIAPyUUV02+0GgWgAAAGsAAAANAAAAbWFuaWZlc3QuanNvbhXKuwqAMAyF4VcpmSXU1adwcBOHYoME21R6EUR8d5vxfP95gT1MBvYU0Xl/JqxUKgwGxEXSsvRt5tAOFuWbcuEkWka0aNVIan5UomPB0JziRTly0W/pad2+H1BLAwQUAAAACAD8lFFdeouI5w0AAAALAAAACAAAAG1haW4ubHVhK0otKS3KUygpKk0FAFBLAwQUAAAAAAAAACEAQEr/sQ0AAAANAAAACwAAAGFzc2V0cy9saW5rLi4vLi4vb3V0c2lkZVBLAQIUAxQAAAAIAPyUUV02+0GgWgAAAGsAAAANAAAAAAAAAAAAAACAAQAAAABtYW5pZmVzdC5qc29uUEsBAhQDFAAAAAgA/JRRXXqLiOcNAAAACwAAAAgAAAAAAAAAAAAAAIABhQAAAG1haW4ubHVhUEsBAhQDFAAAAAAAAAAhAEBK/7ENAAAADQAAAAsAAAAAAAAAAAAAAP+huAAAAGFzc2V0cy9saW5rUEsFBgAAAAADAAMAqgAAAO4AAAAAAA==';
