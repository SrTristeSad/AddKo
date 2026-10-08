import 'package:addko/core/player/playback_host_controller.dart';
import 'package:addko/core/player/playback_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('routes open and transport commands to active player host', () async {
    final host = PlaybackHostController.shared;
    var opened = '';
    var played = 0;
    var paused = 0;
    var stopped = 0;
    var seek = Duration.zero;

    final token = host.attach(
      onOpen: (request) async => opened = request.uri,
      onPlay: () async => played += 1,
      onPause: () async => paused += 1,
      onStop: () async => stopped += 1,
      onSeek: (position) async => seek = position,
    );
    addTearDown(() => host.detach(token));

    const request = PlaybackRequest(
      uri: 'https://example.com/video.m3u8',
      headers: {},
      properties: {},
      subtitles: [],
    );

    expect(await host.open(request), isTrue);
    expect(await host.play(), isTrue);
    expect(await host.pause(), isTrue);
    expect(await host.stop(), isTrue);
    expect(await host.seek(const Duration(seconds: 12)), isTrue);

    expect(opened, request.uri);
    expect(played, 1);
    expect(paused, 1);
    expect(stopped, 1);
    expect(seek, const Duration(seconds: 12));
  });

  test('ignores commands after player host detaches', () async {
    final host = PlaybackHostController.shared;
    final token = host.attach(
      onOpen: (_) async {},
      onPlay: () async {},
      onPause: () async {},
      onStop: () async {},
      onSeek: (_) async {},
    );
    host.detach(token);

    expect(host.isAttached, isFalse);
    expect(await host.pause(), isFalse);
    expect(await host.stop(), isFalse);
  });
}
