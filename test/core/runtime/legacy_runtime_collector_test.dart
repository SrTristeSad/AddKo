import 'dart:convert';

import 'package:addko/core/runtime/legacy/legacy_runtime_collector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('collects directory items emitted by xbmcplugin shim', () {
    final collector = LegacyRuntimeCollector();
    collector.consumeStdoutLine(
      '${LegacyRuntimeCollector.protocolPrefix}${jsonEncode({
        'method': 'xbmcplugin.addDirectoryItem',
        'params': {
          'url': 'plugin://plugin.video.demo/?action=movies',
          'is_folder': true,
          'item': {
            'label': 'Filmes',
            'path': '',
            'art': {'icon': 'https://example.com/icon.png'},
            'properties': {},
          },
        },
      })}',
    );

    final result = collector.build(exitCode: 0);
    expect(result.succeeded, isTrue);
    expect(result.items, hasLength(1));
    expect(result.items.single.label, 'Filmes');
    expect(result.items.single.isFolder, isTrue);
    expect(
      result.items.single.url,
      'plugin://plugin.video.demo/?action=movies',
    );
  });

  test('captures resolved playback items', () {
    final collector = LegacyRuntimeCollector();
    collector.consumeStdoutLine(
      '${LegacyRuntimeCollector.protocolPrefix}${jsonEncode({
        'method': 'xbmcplugin.setResolvedUrl',
        'params': {
          'succeeded': true,
          'item': {
            'label': 'Video',
            'path': 'https://media.example/video.m3u8',
            'properties': {
              'inputstream': 'inputstream.adaptive',
            },
          },
        },
      })}',
    );

    final result = collector.build(exitCode: 0);
    expect(result.resolvedItem?.path, 'https://media.example/video.m3u8');
    expect(
      result.resolvedItem?.properties['inputstream'],
      'inputstream.adaptive',
    );
  });
}
