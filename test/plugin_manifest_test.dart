import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a minimal valid manifest', () {
    final manifest = PluginManifest.fromJson(<String, Object?>{
      'id': 'com.addko.hello',
      'name': 'Hello AddKo',
      'version': '1.0.0',
      'entry': 'main.lua',
      'permissions': <Object?>['storage'],
    });

    expect(manifest.id, 'com.addko.hello');
    expect(manifest.permissions, contains(PluginPermission.storage));
    expect(manifest.dependencies, isEmpty);
  });

  test('parses declared plugin dependencies', () {
    final manifest = PluginManifest.fromJson(<String, Object?>{
      'id': 'com.addko.catalog',
      'name': 'Catalog',
      'version': '1.0.0',
      'entry': 'main.lua',
      'permissions': <Object?>['network'],
      'dependencies': <Object?>[
        'io.addko.luelement',
        'com.example.metadata',
      ],
    });

    expect(
      manifest.dependencies,
      containsAll(<String>['io.addko.luelement', 'com.example.metadata']),
    );
  });

  test('rejects path traversal in entry', () {
    expect(
      () => PluginManifest.fromJson(<String, Object?>{
        'id': 'com.addko.bad',
        'name': 'Bad',
        'version': '1.0.0',
        'entry': '../main.lua',
        'permissions': <Object?>[],
      }),
      throwsFormatException,
    );
  });

  test('rejects unknown permissions', () {
    expect(
      () => PluginManifest.fromJson(<String, Object?>{
        'id': 'com.addko.bad',
        'name': 'Bad',
        'version': '1.0.0',
        'entry': 'main.lua',
        'permissions': <Object?>['root'],
      }),
      throwsFormatException,
    );
  });

  test('rejects self dependency', () {
    expect(
      () => PluginManifest.fromJson(<String, Object?>{
        'id': 'com.addko.self',
        'name': 'Self',
        'version': '1.0.0',
        'entry': 'main.lua',
        'permissions': <Object?>[],
        'dependencies': <Object?>['com.addko.self'],
      }),
      throwsFormatException,
    );
  });

  test('rejects duplicated dependency', () {
    expect(
      () => PluginManifest.fromJson(<String, Object?>{
        'id': 'com.addko.duplicate',
        'name': 'Duplicate',
        'version': '1.0.0',
        'entry': 'main.lua',
        'permissions': <Object?>[],
        'dependencies': <Object?>[
          'io.addko.luelement',
          'io.addko.luelement',
        ],
      }),
      throwsFormatException,
    );
  });

  test('native engines require a declared permission and bounded IDs', () {
    final manifest = <String, Object?>{
      'id': 'io.addko.native.test',
      'name': 'Engine example',
      'version': '1.0.0',
      'entry': 'main.lua',
      'permissions': <String>['native_engine'],
      'native_engines': <String>['elementum'],
    };
    expect(
      PluginManifest.fromJson(manifest).nativeEngines,
      contains('elementum'),
    );
    expect(
      () => PluginManifest.fromJson(<String, Object?>{
        ...manifest,
        'permissions': <String>[],
      }),
      throwsFormatException,
    );
    expect(
      () => PluginManifest.fromJson(<String, Object?>{
        ...manifest,
        'native_engines': <String>['../../unsafe'],
      }),
      throwsFormatException,
    );
    expect(
      () => PluginManifest.fromJson(<String, Object?>{
        ...manifest,
        'native_engines': <String>['elementum', 'elementum'],
      }),
      throwsFormatException,
    );
  });


}
