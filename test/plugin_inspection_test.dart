import 'dart:convert';
import 'dart:typed_data';

import 'package:addko/src/plugins/plugin_inspection.dart';
import 'package:addko/src/plugins/plugin_manager.dart';
import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preview exposes permissions without installing package', () {
    final preview = inspectAddkoBytes(
      _package(
        permissions: const <String>['network', 'storage'],
      ),
    );

    expect(preview.manifest.id, 'com.addko.preview');
    expect(
      preview.manifest.permissions,
      containsAll(<PluginPermission>[
        PluginPermission.network,
        PluginPermission.storage,
      ]),
    );
    expect(preview.entryCount, 2);
  });

  test('preview rejects unsafe archive paths before confirmation', () {
    final archive = Archive()
      ..add(
        ArchiveFile.string(
          'manifest.json',
          jsonEncode(_manifest(const <String>[])),
        ),
      )
      ..add(ArchiveFile.string('main.lua', 'return true'))
      ..add(ArchiveFile.string('../outside.txt', 'nope'));

    expect(
      () => inspectAddkoBytes(ZipEncoder().encodeBytes(archive)),
      throwsA(isA<PluginPackageException>()),
    );
  });
}

Uint8List _package({required List<String> permissions}) {
  final archive = Archive()
    ..add(
      ArchiveFile.string(
        'manifest.json',
        jsonEncode(_manifest(permissions)),
      ),
    )
    ..add(ArchiveFile.string('main.lua', 'return true'));
  return ZipEncoder().encodeBytes(archive);
}

Map<String, Object?> _manifest(List<String> permissions) {
  return <String, Object?>{
    'id': 'com.addko.preview',
    'name': 'Preview',
    'version': '1.0.0',
    'entry': 'main.lua',
    'permissions': permissions,
  };
}
