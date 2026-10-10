import 'package:addko/core/addons/application/addon_dependency_resolver.dart';
import 'package:addko/core/addons/infrastructure/addon_manifest_parser.dart';
import 'package:addko/core/repositories/domain/repository_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts Kodi Omega host capabilities at supported versions', () {
    final root = _entry('''
<addon id="plugin.video.demo" name="Demo" version="1.0.0" provider-name="AddKo">
  <requires>
    <import addon="xbmc.python" version="3.0.0" />
    <import addon="xbmc.addon" version="12.0.0" />
  </requires>
  <extension point="xbmc.python.pluginsource" library="default.py">
    <provides>video</provides>
  </extension>
</addon>
''');

    final plan = const AddonDependencyResolver().resolve(
      root: root,
      catalogs: const [],
      installedAddons: const [],
    );

    expect(plan.canInstall, isTrue);
  });

  test('treats Kodi Omega binary globals as host-provided virtual addons', () {
    final root = _entry('''
<addon id="inputstream.demo" name="Binary Demo" version="1.0.0" provider-name="AddKo">
  <requires>
    <import addon="kodi.binary.global.main" version="2.0.2" />
    <import addon="kodi.binary.global.general" version="1.0.5" />
    <import addon="kodi.binary.global.gui" version="5.15.0" />
    <import addon="kodi.binary.global.filesystem" version="1.1.9" />
    <import addon="kodi.binary.global.tools" version="1.0.4" />
    <import addon="kodi.binary.instance.inputstream" version="3.3.0" />
  </requires>
  <extension point="kodi.inputstream" library_android-aarch64="inputstream.demo.so" />
</addon>
''');

    final plan = const AddonDependencyResolver().resolve(
      root: root,
      catalogs: const [],
      installedAddons: const [],
    );

    expect(plan.canInstall, isTrue);
    expect(plan.issues, isEmpty);
  });

  test('rejects an xbmc host API version newer than AddKo provides', () {
    final root = _entry('''
<addon id="plugin.video.future" name="Future" version="1.0.0" provider-name="AddKo">
  <requires>
    <import addon="xbmc.python" version="9.0.0" />
  </requires>
  <extension point="xbmc.python.pluginsource" library="default.py">
    <provides>video</provides>
  </extension>
</addon>
''');

    final plan = const AddonDependencyResolver().resolve(
      root: root,
      catalogs: const [],
      installedAddons: const [],
    );

    expect(plan.canInstall, isFalse);
    expect(plan.issues.single.addonId, 'xbmc.python');
    expect(plan.issues.single.message, contains('3.0.1'));
  });
}

RepositoryAddonEntry _entry(String xml) {
  final manifest = const AddonManifestParser().parse(xml);
  return RepositoryAddonEntry(
    manifest: manifest,
    category: RepositoryAddonCategory.video,
    packageUri: Uri.parse(
      'https://repo.example/${manifest.id}/${manifest.id}-${manifest.version}.zip',
    ),
  );
}
