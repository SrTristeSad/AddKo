import 'package:addko/core/player/playback_request.dart';
import 'package:addko/core/runtime/legacy/legacy_plugin_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts Kodi pipe HTTP headers from a resolved media URL', () {
    const item = LegacyPluginItem(
      label: 'Video',
      path:
          'https://media.example/video.m3u8|User-Agent=AddKo%2F1.0&Referer=https%3A%2F%2Fexample.com%2F',
      url: '',
      isFolder: false,
    );

    final request = PlaybackRequest.fromLegacyItem(item);

    expect(request.uri, 'https://media.example/video.m3u8');
    expect(request.headers['User-Agent'], 'AddKo/1.0');
    expect(request.headers['Referer'], 'https://example.com/');
  });

  test('preserves InputStream Adaptive properties instead of losing them', () {
    const item = LegacyPluginItem(
      label: 'DASH',
      path: 'https://media.example/manifest.mpd',
      url: '',
      isFolder: false,
      properties: {
        'inputstream': 'inputstream.adaptive',
        'inputstream.adaptive.manifest_type': 'mpd',
        'inputstream.adaptive.license_key': 'https://license.example/wv',
      },
    );

    final request = PlaybackRequest.fromLegacyItem(item);

    expect(request.inputStreamAddon, 'inputstream.adaptive');
    expect(request.manifestType, 'mpd');
    expect(request.requiresKodiInputStream, isTrue);
    expect(request.hasDrmConfiguration, isTrue);
  });
}
