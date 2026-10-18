import 'dart:convert';
import 'dart:io';

import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:addko/src/runtime/basic_plugin_host.dart';
import 'package:addko/src/runtime/media_plugin_host.dart';
import 'package:addko/src/runtime/plugin_dependency_host.dart';
import 'package:addko/src/runtime/plugin_player.dart';
import 'package:flutter_test/flutter_test.dart';

/// Uses actual AddKo plugin hosts and HTTP sockets. Only the native video
/// decoder is replaced with a Range-reading test double.
class _RangeProbePlayer implements PluginPlayer {
  _RangeProbePlayer(this.events);

  final List<String> events;
  String _url = '';
  bool _playing = false;
  int? headStatus;
  int? rangeStatus;
  String? contentRange;
  List<int> received = <int>[];

  @override
  Future<bool> play(Object? item) async {
    if (item is! String) throw ArgumentError('Expected media URL');
    events.add('player.play');
    _url = item;
    final client = HttpClient()..autoUncompress = false;
    try {
      final target = Uri.parse(item);
      final head = await (await client.openUrl('HEAD', target)).close();
      headStatus = head.statusCode;
      await head.drain<void>();

      final request = await client.getUrl(target);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=2-5');
      final result = await request.close();
      rangeStatus = result.statusCode;
      contentRange = result.headers.value(HttpHeaders.contentRangeHeader);
      received = await result.fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      );
      _playing = result.statusCode == HttpStatus.partialContent;
      return _playing;
    } finally {
      client.close(force: true);
    }
  }

  @override
  String get currentUrl => _url;
  @override
  bool get isPlaying => _playing;
  @override
  bool get isPaused => !_playing;
  @override
  Map<String, Object?> get times =>
      const <String, Object?>{'position': 2.0, 'duration': 12.0};
  @override
  List<String> get subtitles => const <String>[];
  @override
  Future<void> seek(double seconds) async {
    events.add('player.seek:$seconds');
  }
  @override
  Future<void> setSubtitles(List<String> urls) async {}
  @override
  Future<void> close() async {}
}

void main() {
  late Directory sandbox;
  late HttpServer origin;
  late String originUrl;
  final upstreamRequests = <String>[];
  final upstreamRanges = <String?>[];

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('addko-integration-');
    origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    originUrl = 'http://127.0.0.1:' + origin.port.toString() + '/video.mp4';
    upstreamRequests.clear();
    upstreamRanges.clear();
    origin.listen((request) async {
      upstreamRequests.add(request.method);
      upstreamRanges.add(request.headers.value(HttpHeaders.rangeHeader));
      final response = request.response;
      if (request.uri.path != '/video.mp4') {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }

      const bytes = <int>[97, 98, 99, 100, 101, 102, 103, 104, 105, 106,
        107, 108];
      final range = request.headers.value(HttpHeaders.rangeHeader);
      final body = range == 'bytes=2-5' ? bytes.sublist(2, 6) : bytes;
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.contentType = ContentType('video', 'mp4');
      response.headers.contentLength = body.length;
      if (range != null) {
        if (range != 'bytes=2-5') {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          await response.close();
          return;
        }
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes 2-5/12');
      }
      if (request.method != 'HEAD') response.add(body);
      await response.close();
    });
  });

  tearDown(() async {
    await origin.close(force: true);
    await sandbox.delete(recursive: true);
  });

  test('service → declared addon → HTTP Range → player via real hosts',
      () async {
    final serviceManifest = PluginManifest(
      id: 'io.addko.tests.media_source',
      name: 'Media source', version: '1.0.0', entry: 'main.lua',
      permissions: const <PluginPermission>{PluginPermission.network},
      kind: PluginKind.service,
    );
    final addonManifest = PluginManifest(
      id: 'io.addko.tests.media_consumer',
      name: 'Media consumer', version: '1.0.0', entry: 'main.lua',
      permissions: const <PluginPermission>{PluginPermission.media},
      dependencies: const <String>{'io.addko.tests.media_source'},
    );
    final service = BasicPluginHost(
      manifest: serviceManifest, pluginDirectory: sandbox,
      dataDirectory: sandbox,
    );
    addTearDown(service.close);

    final events = <String>[];
    final player = _RangeProbePlayer(events);
    final mediaHost = MediaPluginHost(
      manifest: addonManifest, pluginDirectory: sandbox,
      dataDirectory: sandbox, player: player,
      uiHandler: (operation, arguments) async {
        events.add(operation);
        return operation == 'ui.player_open';
      },
    );
    final addon = PluginDependencyHost(
      inner: mediaHost,
      manifest: addonManifest,
      caller: (id, method, arguments) async {
        expect(id, serviceManifest.id);
        if (method != 'open') throw StateError('Unknown service method');
        return service.invoke('stream.register', arguments);
      },
    );
    addTearDown(addon.close);

    expect(service.capabilities['player'], false);
    expect(addon.capabilities['player'], true);
    expect(addon.capabilities['http'], false);
    expect(addon.capabilities['plugins'], true);
    await expectLater(
      addon.invoke('stream.register', <String, Object?>{'url': originUrl}),
      throwsA(isA<PluginHostException>()),
    );
    await expectLater(
      addon.invoke('plugins.call', <String, Object?>{
        'id': 'io.addko.other', 'method': 'open',
        'args': <String, Object?>{'url': originUrl},
      }),
      throwsA(isA<PluginDependencyException>()),
    );

    final source = await addon.invoke('plugins.call', <String, Object?>{
      'id': serviceManifest.id, 'method': 'open',
      'args': <String, Object?>{'url': originUrl},
    }) as Map;
    final localUrl = source['url'] as String;
    expect(localUrl, startsWith('http://127.0.0.1:'));
    expect(localUrl, isNot(originUrl));

    final started = await addon.invoke('player.play', <String, Object?>{
      'item': localUrl,
    });
    expect(started, true);
    expect(events, <String>['ui.player_open', 'player.play']);
    expect(player.headStatus, HttpStatus.ok);
    expect(player.rangeStatus, HttpStatus.partialContent);
    expect(player.contentRange, 'bytes 2-5/12');
    expect(utf8.decode(player.received), 'cdef');
    expect(upstreamRequests, <String>['HEAD', 'GET']);
    expect(upstreamRanges, <String?>[null, 'bytes=2-5']);
    expect(await addon.invoke('player.is_playing', null), true);
    expect(await addon.invoke('player.times', null),
        containsPair('duration', 12.0));
    expect(await addon.invoke('player.seek',
        <String, Object?>{'seconds': 7.0}), true);
    expect(events, contains('player.seek:7.0'));

    final stats = await service.invoke('stream.stats', <String, Object?>{
      'id': source['id'],
    }) as Map;
    expect(stats['requests'], 2);
    expect(stats['head_requests'], 1);
    expect(stats['range_requests'], 1);
    expect(stats['bytes_forwarded'], 4);
    expect(stats['active_requests'], 0);
    expect(stats['last_http_status'], HttpStatus.partialContent);
    expect(stats.toString(), isNot(contains(originUrl)));

    expect(await service.invoke('stream.revoke',
        <String, Object?>{'id': source['id']}), true);
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(localUrl));
      final response = await request.close();
      expect(response.statusCode, HttpStatus.notFound);
      await response.drain<void>();
    } finally {
      client.close(force: true);
    }
  });

  test('media permission is required before opening player UI', () async {
    final host = MediaPluginHost(
      manifest: const PluginManifest(
        id: 'io.addko.tests.no_media',
        name: 'No media', version: '1.0.0', entry: 'main.lua',
        permissions: <PluginPermission>{},
      ),
      pluginDirectory: sandbox, dataDirectory: sandbox,
      player: _RangeProbePlayer(<String>[]),
      uiHandler: (operation, arguments) async {
        fail('Unprivileged service opened player UI: $operation');
      },
    );
    addTearDown(host.close);
    await expectLater(
      host.invoke('player.play', <String, Object?>{'item': originUrl}),
      throwsA(isA<PluginHostException>()),
    );
  });
}
