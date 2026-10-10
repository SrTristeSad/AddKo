import 'dart:io';

import 'package:addko/core/addons/application/addon_install_controller.dart';
import 'package:addko/core/addons/infrastructure/addon_directories.dart';
import 'package:addko/core/addons/infrastructure/addon_package_installer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('blocks removal of a required dependency and can remove addon data', () async {
    final support = await Directory.systemTemp.createTemp('addko-uninstall-test-');
    addTearDown(() async {
      if (await support.exists()) {
        await support.delete(recursive: true);
      }
    });

    final addonsRoot = Directory(p.join(support.path, 'addons'));
    final dependencyDirectory = Directory(
      p.join(addonsRoot.path, 'script.module.dep'),
    );
    final consumerDirectory = Directory(
      p.join(addonsRoot.path, 'plugin.video.consumer'),
    );
    await dependencyDirectory.create(recursive: true);
    await consumerDirectory.create(recursive: true);

    await File(p.join(dependencyDirectory.path, 'addon.xml')).writeAsString('''
<addon id="script.module.dep" name="Dependency" version="1.0.0" provider-name="AddKo Test">
  <extension point="xbmc.python.module" library="lib" />
</addon>
''');

    await File(p.join(consumerDirectory.path, 'addon.xml')).writeAsString('''
<addon id="plugin.video.consumer" name="Consumer" version="1.0.0" provider-name="AddKo Test">
  <requires>
    <import addon="script.module.dep" version="1.0.0" />
  </requires>
  <extension point="xbmc.python.pluginsource" library="default.py">
    <provides>video</provides>
  </extension>
</addon>
''');

    final dataDirectory = Directory(
      p.join(support.path, 'addon_data', 'script.module.dep'),
    );
    await dataDirectory.create(recursive: true);
    await File(p.join(dataDirectory.path, 'settings.json')).writeAsString('{}');

    final controller = AddonInstallController(
      directories: AddonDirectories(
        supportDirectoryProvider: () async => support,
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    expect(controller.requiredBy('script.module.dep'), hasLength(1));
    await expectLater(
      controller.uninstall('script.module.dep'),
      throwsA(isA<AddonInstallException>()),
    );
    expect(await dependencyDirectory.exists(), isTrue);

    await controller.uninstall('plugin.video.consumer');
    expect(controller.requiredBy('script.module.dep'), isEmpty);

    await controller.uninstall('script.module.dep', removeData: true);
    expect(await dependencyDirectory.exists(), isFalse);
    expect(await dataDirectory.exists(), isFalse);
  });

  test('detects a missing transitive required dependency', () async {
    final support = await Directory.systemTemp.createTemp('addko-deps-test-');
    addTearDown(() async {
      if (await support.exists()) {
        await support.delete(recursive: true);
      }
    });

    final addonsRoot = Directory(p.join(support.path, 'addons'));
    final module = Directory(p.join(addonsRoot.path, 'script.module.middle'));
    final plugin = Directory(p.join(addonsRoot.path, 'plugin.video.root'));
    await module.create(recursive: true);
    await plugin.create(recursive: true);

    await File(p.join(module.path, 'addon.xml')).writeAsString('''
<addon id="script.module.middle" name="Middle" version="1.0.0" provider-name="AddKo Test">
  <requires><import addon="script.module.missing" version="1.0.0" /></requires>
  <extension point="xbmc.python.module" library="lib" />
</addon>
''');
    await File(p.join(plugin.path, 'addon.xml')).writeAsString('''
<addon id="plugin.video.root" name="Root" version="1.0.0" provider-name="AddKo Test">
  <requires><import addon="script.module.middle" version="1.0.0" /></requires>
  <extension point="xbmc.python.pluginsource" library="default.py"><provides>video</provides></extension>
</addon>
''');

    final controller = AddonInstallController(
      directories: AddonDirectories(
        supportDirectoryProvider: () async => support,
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    final root = controller.installedById('PLUGIN.VIDEO.ROOT');
    expect(root, isNotNull);
    expect(controller.hasRequiredDependencies(root!), isFalse);
  });
}
