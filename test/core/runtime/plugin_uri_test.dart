import 'package:addko/core/runtime/plugin_uri.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses Kodi plugin URI', () {
    final uri = PluginUri.parse(
      'plugin://plugin.video.example/movies?page=2&genre=action',
    );

    expect(uri.addonId, 'plugin.video.example');
    expect(uri.path, '/movies');
    expect(uri.queryParameters['page'], '2');
    expect(uri.queryParameters['genre'], 'action');
  });
}
