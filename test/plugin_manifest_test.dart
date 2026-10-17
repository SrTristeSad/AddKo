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
}
