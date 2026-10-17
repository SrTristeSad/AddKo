import 'dart:io';

import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:addko/src/runtime/media_plugin_host.dart';
import 'package:addko/src/runtime/plugin_player.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePlayer implements PluginPlayer {
  _FakePlayer(this.events, {this.failPlayback = false});

  final List<String> events;
  final bool failPlayback;

  @override
  Future<bool> play(Object? item) async {
    events.add('player.play');
    if (failPlayback) throw StateError('media stream unavailable');
    return true;
  }

  @override
  String get currentUrl => '';
  @override
  bool get isPlaying => false;
  @override
  bool get isPaused => false;
  @override
  Map<String, Object?> get times => const <String, Object?>{};
  @override
  List<String> get subtitles => const <String>[];
  @override
  Future<void> seek(double seconds) async {}
  @override
  Future<void> setSubtitles(List<String> urls) async {}
  @override
  Future<void> close() async {}
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('addko-media-host-test-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  MediaPluginHost host(
    _FakePlayer player,
    Future<Object?> Function(String, Map<String, Object?>) uiHandler,
  ) {
    return MediaPluginHost(
      manifest: const PluginManifest(
        id: 'io.addko.tests.video',
        name: 'Video',
        version: '1.0.0',
        entry: 'main.lua',
        permissions: <PluginPermission>{PluginPermission.media},
      ),
      pluginDirectory: root,
      dataDirectory: root,
      player: player,
      uiHandler: uiHandler,
    );
  }

  test('player UI opens before waiting for stream initialization', () async {
    final events = <String>[];
    final mediaHost = host(
      _FakePlayer(events),
      (operation, arguments) async {
        expect(operation, 'ui.player_open');
        events.add(operation);
        return true;
      },
    );

    try {
      final result = await mediaHost.invoke('player.play', <String, Object?>{
        'item': 'http://127.0.0.1:65220/files/video.mp4',
      });
      expect(result, true);
      expect(events, <String>['ui.player_open', 'player.play']);
    } finally {
      await mediaHost.close();
    }
  });

  test('playback failure is propagated after the player UI opens', () async {
    final events = <String>[];
    final mediaHost = host(
      _FakePlayer(events, failPlayback: true),
      (operation, arguments) async {
        events.add(operation);
        return true;
      },
    );

    try {
      await expectLater(
        mediaHost.invoke('player.play', <String, Object?>{'item': 'http://localhost/video'}),
        throwsA(isA<StateError>()),
      );
      expect(events, <String>['ui.player_open', 'player.play']);
    } finally {
      await mediaHost.close();
    }
  });

  test('cancelled player navigation blocks playback', () async {
    final events = <String>[];
    final mediaHost = host(
      _FakePlayer(events),
      (operation, arguments) async {
        events.add(operation);
        return false;
      },
    );

    try {
      await expectLater(
        mediaHost.invoke('player.play', <String, Object?>{'item': 'http://localhost/video'}),
        throwsA(isA<Exception>()),
      );
      expect(events, <String>['ui.player_open']);
    } finally {
      await mediaHost.close();
    }
  });
}
