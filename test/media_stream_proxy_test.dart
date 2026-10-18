import 'dart:convert';
import 'dart:io';

import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:addko/src/runtime/basic_plugin_host.dart';
import 'package:addko/src/runtime/media_stream_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory sandbox;
  late HttpServer upstream;
  late String upstreamUrl;
  final bytes = utf8.encode('abcdefghijklmnopqrstuvwxyz');
  final seenRanges = <String?>[];
  final seenAuthorization = <String?>[];

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('addko-media-');
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstreamUrl = 'http://127.0.0.1:' + upstream.port.toString();
    seenRanges.clear();
    seenAuthorization.clear();
    upstream.listen((request) async {
      seenRanges.add(request.headers.value(HttpHeaders.rangeHeader));
      seenAuthorization.add(
          request.headers.value(HttpHeaders.authorizationHeader));
      if (request.uri.path == '/redirect') {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(HttpHeaders.locationHeader, '/video');
        await request.response.close();
        return;
      }
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.contentType = ContentType('video', 'mp4');
      final range = request.headers.value(HttpHeaders.rangeHeader);
      List<int> body = bytes;
      if (range != null) {
        if (range == 'bytes=4-9') {
          body = bytes.sublist(4, 10);
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes 4-9/26',
          );
        } else {
          request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          await request.response.close();
          return;
        }
      }
      request.response.headers.contentLength = body.length;
      if (request.method == 'GET') request.response.add(body);
      await request.response.close();
    });
  });

  tearDown(() async {
    await upstream.close(force: true);
    await sandbox.delete(recursive: true);
  });

  Future<(int, Map<String, String>, List<int>)> read(
    String url, {
    String method = 'GET',
    String? range,
  }) async {
    final client = HttpClient()..autoUncompress = false;
    try {
      final request = await client.openUrl(method, Uri.parse(url));
      if (range != null) {
        request.headers.set(HttpHeaders.rangeHeader, range);
      }
      final result = await request.close();
      final headers = <String, String>{};
      result.headers.forEach((key, values) {
        headers[key] = values.join(', ');
      });
      final chunks = await result.fold<List<int>>(
        <int>[],
        (all, chunk) => all..addAll(chunk),
      );
      return (result.statusCode, headers, chunks);
    } finally {
      client.close(force: true);
    }
  }

  test('Lua host stream proxy forwards range headers and body without buffering',
      () async {
    final host = BasicPluginHost(
      manifest: const PluginManifest(
        id: 'io.addko.testmedia', name: 'Media test', version: '1.0.0',
        entry: 'main.lua',
        permissions: <PluginPermission>{PluginPermission.network},
      ),
      pluginDirectory: sandbox,
      dataDirectory: sandbox,
    );
    addTearDown(host.close);
    expect(host.capabilities['media_stream_proxy'], true);

    final registered = await host.invoke(
      'stream.register',
      <String, Object?>{
        'url': upstreamUrl + '/video',
        'headers': <String, String>{'Authorization': 'Bearer secret'},
      },
    ) as Map;
    final url = registered['url'] as String;
    expect(url, startsWith('http://127.0.0.1:'));
    expect(url, isNot(contains('secret')));

    final response = await read(url, range: 'bytes=4-9');
    expect(response.$1, HttpStatus.partialContent);
    expect(response.$2['content-range'], 'bytes 4-9/26');
    expect(response.$2['accept-ranges'], 'bytes');
    expect(utf8.decode(response.$3), 'efghij');
    expect(seenRanges, contains('bytes=4-9'));
    expect(seenAuthorization, contains('Bearer secret'));

    final head = await read(url, method: 'HEAD');
    expect(head.$1, HttpStatus.ok);
    expect(head.$2['content-length'], '26');
    expect(head.$3, isEmpty);

    final revoked = await host.invoke(
      'stream.revoke', <String, Object?>{'id': registered['id']},
    );
    expect(revoked, true);
    expect((await read(url)).$1, HttpStatus.notFound);
    expect((await read(url.replaceFirst('/media/', '/unknown/'))).$1,
        HttpStatus.notFound);
  });

  test('same-origin redirects work and retain required source authorization',
      () async {
    final proxy = MediaStreamProxy();
    addTearDown(proxy.close);
    final source = await proxy.register(<String, Object?>{
      'url': upstreamUrl + '/redirect',
      'headers': <String, String>{'Authorization': 'Bearer local'},
    });
    final response = await read(source['url'] as String);
    expect(response.$1, HttpStatus.ok);
    expect(response.$3, bytes);
    expect(seenAuthorization, contains('Bearer local'));
  });

  test('custom credentials are not forwarded across redirect origins',
      () async {
    final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => other.close(force: true));
    String? redirectedAuth;
    other.listen((request) async {
      redirectedAuth = request.headers.value(HttpHeaders.authorizationHeader);
      request.response.write('safe');
      await request.response.close();
    });
    final first = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => first.close(force: true));
    first.listen((request) async {
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set(HttpHeaders.locationHeader,
          'http://127.0.0.1:' + other.port.toString() + '/video');
      await request.response.close();
    });
    final proxy = MediaStreamProxy();
    addTearDown(proxy.close);
    final source = await proxy.register(<String, Object?>{
      'url': 'http://127.0.0.1:' + first.port.toString() + '/start',
      'headers': <String, String>{'Authorization': 'Bearer do-not-leak'},
    });
    final response = await read(source['url'] as String);
    expect(response.$1, HttpStatus.ok);
    expect(utf8.decode(response.$3), 'safe');
    expect(redirectedAuth, isNull);
  });

  test('only network-authorized plugins can register a source', () async {
    final host = BasicPluginHost(
      manifest: const PluginManifest(
        id: 'io.addko.no-network', name: 'Restricted',
        version: '1.0.0', entry: 'main.lua',
        permissions: <PluginPermission>{},
      ),
      pluginDirectory: sandbox,
      dataDirectory: sandbox,
    );
    addTearDown(host.close);
    expect(host.capabilities['media_stream_proxy'], false);
    await expectLater(
      host.invoke('stream.register', <String, Object?>{
        'url': upstreamUrl + '/video',
      }),
      throwsA(isA<PluginHostException>()),
    );
  });

  test('reject unsafe source URLs, source headers and invalid range syntax',
      () async {
    final proxy = MediaStreamProxy();
    addTearDown(proxy.close);
    for (final invalid in <String>['file:///private', 'ftp://example.com/',
      'http://user:pass@example.com/video']) {
      await expectLater(
        proxy.register(<String, Object?>{'url': invalid}),
        throwsA(isA<MediaStreamException>()),
      );
    }
    await expectLater(
      proxy.register(<String, Object?>{
        'url': upstreamUrl + '/video',
        'headers': <String, String>{'Range': 'bytes=0-5'},
      }),
      throwsA(isA<MediaStreamException>()),
    );
    await expectLater(
      proxy.register(<String, Object?>{
        'url': upstreamUrl + '/video',
        'headers': <String, String>{'Authorization': 'bad\r\nX-Injected: yes'},
      }),
      throwsA(isA<MediaStreamException>()),
    );
    final registered = await proxy.register(<String, Object?>{
      'url': upstreamUrl + '/video',
    });
    expect((await read(registered['url'] as String,
        range: 'bytes=0-1,4-5')).$1,
        HttpStatus.requestedRangeNotSatisfiable);
    expect(seenRanges, isEmpty);
  });

  test('source limit and shutdown invalidate the active bridge', () async {
    final proxy = MediaStreamProxy();
    addTearDown(proxy.close);
    final sources = <Map<String, Object?>>[];
    for (var i = 0; i < MediaStreamProxy.maxSources; i++) {
      sources.add(await proxy.register(
        <String, Object?>{'url': upstreamUrl + '/video'},
      ));
    }
    await expectLater(
      proxy.register(<String, Object?>{'url': upstreamUrl + '/video'}),
      throwsA(isA<MediaStreamException>()),
    );
    await proxy.close();
    await expectLater(
      proxy.register(<String, Object?>{'url': upstreamUrl + '/video'}),
      throwsA(isA<MediaStreamException>()),
    );
  });
}
