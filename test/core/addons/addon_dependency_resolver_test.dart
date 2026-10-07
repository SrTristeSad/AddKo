import 'package:addko/core/addons/application/addon_dependency_resolver.dart';
import 'package:addko/core/addons/infrastructure/addon_manifest_parser.dart';
import 'package:addko/core/repositories/domain/repository_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('orders required dependencies before the selected addon', () {
    final dependency = _entry(
      id: 'script.module.demo',
      version: '2.0.0',
      xml: '''
<addon id="script.module.demo" name="Module" version="2.0.0" provider-name="AddKo">
  <requires><import addon="xbmc.python" version="3.0.0" /></requires>
  <extension point="xbmc.python.module" library="lib" />
</addon>
''',
    );
    final root = _entry(
      id: 'plugin.video.demo',
      version: '1.0.0',
      xml: '''
<addon id="plugin.video.demo" name="Video" version="1.0.0" provider-name="AddKo">
  <requires>
    <import addon="xbmc.python" version="3.0.0" />
    <import addon="script.module.demo" version="2.0.0" />
  </requires>
  <extension point="xbmc.python.pluginsource" library="default.py"><provides>video</provides></extension>
</addon>
''',
    );

    final catalog = RepositoryCatalog(
      repositoryName: 'Repo',
      sourceUri: Uri.parse('https://repo.example/addon.xml'),
      packageBaseUri: Uri.parse('https://repo.example/zips/'),
      addons: [root, dependency],
      fetchedAt: DateTime.utc(2026),
    );

    final plan = const AddonDependencyResolver().resolve(
      root: root,
      catalogs: [catalog],
      installedAddons: const [],
    );

    expect(plan.canInstall, isTrue);
    expect(
      plan.installOrder.map((entry) => entry.manifest.id),
      ['script.module.demo', 'plugin.video.demo'],
    );
  });

  test('reports a missing required dependency', () {
    final root = _entry(
      id: 'plugin.video.demo',
      version: '1.0.0',
      xml: '''
<addon id="plugin.video.demo" name="Video" version="1.0.0" provider-name="AddKo">
  <requires><import addon="script.module.missing" version="1.0.0" /></requires>
  <extension point="xbmc.python.pluginsource" library="default.py"><provides>video</provides></extension>
</addon>
''',
    );

    final plan = const AddonDependencyResolver().resolve(
      root: root,
      catalogs: const [],
      installedAddons: const [],
    );

    expect(plan.canInstall, isFalse);
    expect(plan.issues.single.addonId, 'script.module.missing');
  });
}

RepositoryAddonEntry _entry({
  required String id,
  required String version,
  required String xml,
}) {
  final manifest = const AddonManifestParser().parse(xml);
  return RepositoryAddonEntry(
    manifest: manifest,
    category: RepositoryAddonCategory.video,
    packageUri: Uri.parse('https://repo.example/zips/$id/$id-$version.zip'),
  );
}
