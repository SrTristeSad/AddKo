import 'package:addko/core/addons/infrastructure/addon_manifest_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = AddonManifestParser();

  test('parses a legacy Kodi video plugin manifest', () {
    const xml = '''
<addon id="plugin.video.example" name="Example" version="1.2.3" provider-name="AddKo">
  <requires>
    <import addon="xbmc.python" version="3.0.0" />
    <import addon="script.module.example" version="2.0.0" optional="true" />
  </requires>
  <extension point="xbmc.python.pluginsource" library="default.py">
    <provides>video</provides>
  </extension>
  <extension point="xbmc.addon.metadata">
    <summary lang="pt_BR">Plugin de exemplo</summary>
    <description lang="pt_BR">Descrição.</description>
    <assets>
      <icon>icon.png</icon>
      <fanart>fanart.jpg</fanart>
    </assets>
  </extension>
</addon>
''';

    final manifest = parser.parse(xml);

    expect(manifest.id, 'plugin.video.example');
    expect(manifest.name, 'Example');
    expect(manifest.version, '1.2.3');
    expect(manifest.isPythonPlugin, isTrue);
    expect(manifest.pythonEntrypoint, 'default.py');
    expect(manifest.dependencies, hasLength(2));
    expect(manifest.dependencies.last.optional, isTrue);
    expect(manifest.iconPath, 'icon.png');
  });

  test('recognizes xbmc.python.script entrypoints', () {
    const xml = '''
<addon id="script.example" name="Script Example" version="1.0.0" provider-name="AddKo">
  <extension point="xbmc.python.script" library="service.py" />
</addon>
''';

    final manifest = parser.parse(xml);

    expect(manifest.isPythonPlugin, isFalse);
    expect(manifest.isPythonScript, isTrue);
    expect(manifest.pythonScriptEntrypoint, 'service.py');
  });
}
