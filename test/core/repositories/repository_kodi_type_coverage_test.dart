import 'package:addko/core/repositories/domain/repository_catalog.dart';
import 'package:addko/core/repositories/infrastructure/repository_index_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = RepositoryIndexParser();

  test('classifies the Kodi Omega addon families instead of flattening them', () {
    final cases = <String, RepositoryAddonCategory>{
      '<extension point="xbmc.python.weather" library="default.py" />':
          RepositoryAddonCategory.weather,
      '<extension point="xbmc.python.lyrics" library="default.py" />':
          RepositoryAddonCategory.lyrics,
      '<extension point="xbmc.subtitle.module" library="default.py" />':
          RepositoryAddonCategory.subtitles,
      '<extension point="xbmc.metadata.scraper.movies" library="movie.xml" />':
          RepositoryAddonCategory.metadata,
      '<extension point="xbmc.gui.skin" />': RepositoryAddonCategory.skins,
      '<extension point="xbmc.webinterface" entry="index.html" />':
          RepositoryAddonCategory.webInterfaces,
      '<extension point="kodi.resource.language" />':
          RepositoryAddonCategory.resources,
      '<extension point="kodi.inputstream" library_android="input.so" />':
          RepositoryAddonCategory.inputStream,
      '<extension point="kodi.pvrclient" library_android="pvr.so" />':
          RepositoryAddonCategory.pvr,
      '<extension point="kodi.gameclient" library_android="game.so" />':
          RepositoryAddonCategory.games,
      '<extension point="kodi.game.controller" />':
          RepositoryAddonCategory.gameControllers,
      '<extension point="kodi.peripheral" library_android="peripheral.so" />':
          RepositoryAddonCategory.peripherals,
      '<extension point="kodi.audiodecoder" library_android="audio.so" />':
          RepositoryAddonCategory.audioCodecs,
      '<extension point="kodi.audioencoder" library_android="audio.so" />':
          RepositoryAddonCategory.audioCodecs,
      '<extension point="kodi.imagedecoder" library_android="image.so" />':
          RepositoryAddonCategory.imageDecoders,
      '<extension point="kodi.vfs" library_android="vfs.so" />':
          RepositoryAddonCategory.vfs,
      '<extension point="xbmc.ui.screensaver" library_android="screen.so" />':
          RepositoryAddonCategory.screensavers,
      '<extension point="xbmc.player.musicviz" library_android="viz.so" />':
          RepositoryAddonCategory.visualizations,
    };

    var index = 0;
    for (final entry in cases.entries) {
      index += 1;
      final xml = '''
<addons>
  <addon id="test.addon.$index" name="Test $index" version="1.0.0" provider-name="AddKo">
    ${entry.key}
  </addon>
</addons>
''';
      final result = parser.parse(xml);
      expect(result.addons, hasLength(1), reason: entry.key);
      expect(result.addons.single.category, entry.value, reason: entry.key);
    }
  });

  test('preserves plugin provides categories used by classic Kodi addons', () {
    const xml = '''
<addons>
  <addon id="plugin.video.demo" name="Video" version="1.0.0">
    <extension point="xbmc.python.pluginsource" library="default.py">
      <provides>video</provides>
    </extension>
  </addon>
  <addon id="plugin.audio.demo" name="Audio" version="1.0.0">
    <extension point="xbmc.python.pluginsource" library="default.py">
      <provides>audio</provides>
    </extension>
  </addon>
  <addon id="plugin.image.demo" name="Image" version="1.0.0">
    <extension point="xbmc.python.pluginsource" library="default.py">
      <provides>image</provides>
    </extension>
  </addon>
</addons>
''';

    final categories = parser
        .parse(xml)
        .addons
        .map((addon) => addon.category)
        .toSet();

    expect(categories, contains(RepositoryAddonCategory.video));
    expect(categories, contains(RepositoryAddonCategory.audio));
    expect(categories, contains(RepositoryAddonCategory.images));
  });
}
