import 'package:addko/core/repositories/domain/repository_catalog.dart';
import 'package:addko/core/repositories/infrastructure/repository_index_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses addons.xml and groups plugin types', () {
    const source = '''
<addons>
  <addon id="plugin.video.demo" name="Demo Video" version="1.2.3" provider-name="AddKo">
    <extension point="xbmc.python.pluginsource" library="default.py">
      <provides>video</provides>
    </extension>
    <extension point="xbmc.addon.metadata">
      <summary lang="en_GB">Demo</summary>
      <assets><icon>icon.png</icon></assets>
    </extension>
  </addon>
  <addon id="script.module.demo" name="Demo Module" version="2.0.0" provider-name="AddKo">
    <extension point="xbmc.python.module" library="lib" />
  </addon>
</addons>
''';

    final result = const RepositoryIndexParser().parse(
      source,
      packageBaseUri: Uri.parse('https://repo.example/zips/'),
    );

    expect(result.addons, hasLength(2));
    expect(result.skippedAddons, 0);

    final video = result.addons.firstWhere(
      (entry) => entry.manifest.id == 'plugin.video.demo',
    );
    expect(video.category, RepositoryAddonCategory.video);
    expect(
      video.packageUri.toString(),
      'https://repo.example/zips/plugin.video.demo/plugin.video.demo-1.2.3.zip',
    );

    final module = result.addons.firstWhere(
      (entry) => entry.manifest.id == 'script.module.demo',
    );
    expect(module.category, RepositoryAddonCategory.modules);
  });

  test('skips malformed addon entries without dropping the repository', () {
    const source = '''
<addons>
  <addon id="broken" />
  <addon id="plugin.video.ok" name="OK" version="1.0.0" provider-name="">
    <extension point="xbmc.python.pluginsource" library="default.py">
      <provides>video</provides>
    </extension>
  </addon>
</addons>
''';

    final result = const RepositoryIndexParser().parse(source);
    expect(result.addons, hasLength(1));
    expect(result.skippedAddons, 1);
  });
}
