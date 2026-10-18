import 'dart:convert';
import 'dart:io';

import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:addko/src/runtime/basic_plugin_host.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory pluginDirectory;
  late Directory dataDirectory;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('addko-host-test-');
    pluginDirectory = Directory(
      '${root.path}${Platform.pathSeparator}plugin',
    );
    dataDirectory = Directory(
      '${root.path}${Platform.pathSeparator}data',
    );
    await pluginDirectory.create(recursive: true);
    await dataDirectory.create(recursive: true);
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('storage permission can write inside plugin data directory', () async {
    final host = BasicPluginHost(
      manifest: _manifest(<PluginPermission>{PluginPermission.storage}),
      pluginDirectory: pluginDirectory,
      dataDirectory: dataDirectory,
    );
    addTearDown(host.close);

    final target = File(
      '${dataDirectory.path}${Platform.pathSeparator}nested'
      '${Platform.pathSeparator}value.txt',
    );

    await host.invoke('fs.write_text', <String, Object?>{
      'path': target.path,
      'text': 'safe',
    });

    expect(await target.readAsString(), 'safe');
  });

  test('storage path traversal cannot escape plugin data directory', () async {
    final host = BasicPluginHost(
      manifest: _manifest(<PluginPermission>{PluginPermission.storage}),
      pluginDirectory: pluginDirectory,
      dataDirectory: dataDirectory,
    );
    addTearDown(host.close);

    final escaped = File(
      '${dataDirectory.path}${Platform.pathSeparator}..'
      '${Platform.pathSeparator}escaped.txt',
    );

    await expectLater(
      host.invoke('fs.write_text', <String, Object?>{
        'path': escaped.path,
        'text': 'nope',
      }),
      throwsA(isA<PluginHostException>()),
    );

    expect(
      await File(
        '${root.path}${Platform.pathSeparator}escaped.txt',
      ).exists(),
      isFalse,
    );
  });


  test('header-only HTTP receives redirect without buffering video', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set('location', '/files/demo.mp4');
      request.response.write('not-video-data');
      await request.response.close();
    });
    final host = BasicPluginHost(
      manifest: _manifest(<PluginPermission>{PluginPermission.network}),
      pluginDirectory: pluginDirectory,
      dataDirectory: dataDirectory,
    );
    addTearDown(host.close);
    final result = await host.invoke('http.request', <String, Object?>{
      'url': 'http://127.0.0.1:${server.port}/play',
      'follow_redirects': false,
      'headers_only': true,
    }) as Map;
    expect(result['status'], 302);
    expect(result['body'], '');
    expect((result['headers'] as Map)['location'], '/files/demo.mp4');
  });

test('TCP client transports bytes over loopback and frees the handle', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close());
    server.listen((socket) {
      socket.listen((data) => socket.add(data));
    });
    final host = BasicPluginHost(
      manifest: _manifest(<PluginPermission>{PluginPermission.network}),
      pluginDirectory: pluginDirectory,
      dataDirectory: dataDirectory,
    );
    addTearDown(host.close);

    expect(host.capabilities['tcp_client'], isTrue);
    final handle = await host.invoke('net.tcp.connect', <String, Object?>{
      'host': '127.0.0.1',
      'port': server.port,
    }) as int;
    expect(await host.invoke('net.tcp.write', <String, Object?>{
      'handle': handle,
      'data': 'hello',
    }), 5);
    final reply = await host.invoke('net.tcp.read', <String, Object?>{
      'handle': handle,
      'max_bytes': 5,
    }) as Map;
    expect(utf8.decode((reply['bytes'] as List).cast<int>()), 'hello');
    expect(reply['timed_out'], false);
    expect(await host.invoke('net.tcp.disconnect', <String, Object?>{
      'handle': handle,
    }), true);
    await expectLater(
      host.invoke('net.tcp.read', <String, Object?>{'handle': handle}),
      throwsA(isA<PluginHostException>()),
    );
  });

  test('TCP client times out without treating it as EOF', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close());
    server.listen((socket) {});
    final host = BasicPluginHost(
      manifest: _manifest(<PluginPermission>{PluginPermission.network}),
      pluginDirectory: pluginDirectory,
      dataDirectory: dataDirectory,
    );
    addTearDown(host.close);

    final handle = await host.invoke('net.tcp.connect', <String, Object?>{
      'host': '127.0.0.1',
      'port': server.port,
    }) as int;
    final reply = await host.invoke('net.tcp.read', <String, Object?>{
      'handle': handle,
      'timeout_ms': 20,
    }) as Map;
    expect(reply['bytes'], isEmpty);
    expect(reply['timed_out'], true);
    expect(reply['eof'], false);
  });

  test('TCP client permission and write limits are enforced', () async {
    final restricted = BasicPluginHost(
      manifest: _manifest(const <PluginPermission>{}),
      pluginDirectory: pluginDirectory,
      dataDirectory: dataDirectory,
    );
    addTearDown(restricted.close);
    expect(restricted.capabilities['tcp_client'], false);
    await expectLater(
      restricted.invoke('net.tcp.connect', <String, Object?>{
        'host': '127.0.0.1', 'port': 9000,
      }),
      throwsA(isA<PluginHostException>()),
    );

    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close());
    server.listen((socket) {});
    final allowed = BasicPluginHost(
      manifest: _manifest(<PluginPermission>{PluginPermission.network}),
      pluginDirectory: pluginDirectory,
      dataDirectory: dataDirectory,
    );
    addTearDown(allowed.close);
    final handle = await allowed.invoke('net.tcp.connect', <String, Object?>{
      'host': '127.0.0.1',
      'port': server.port,
    }) as int;
    await expectLater(
      allowed.invoke('net.tcp.write', <String, Object?>{
        'handle': handle,
        'data': List<int>.filled(BasicPluginHost.maxTcpTransferBytes + 1, 1),
      }),
      throwsA(isA<PluginHostException>()),
    );
    await expectLater(
      allowed.invoke('net.tcp.read', <String, Object?>{
        'handle': handle,
        'max_bytes': BasicPluginHost.maxTcpTransferBytes + 1,
      }),
      throwsA(isA<PluginHostException>()),
    );
  });

  test('network operations require network permission', () async {
    final host = BasicPluginHost(
      manifest: _manifest(const <PluginPermission>{}),
      pluginDirectory: pluginDirectory,
      dataDirectory: dataDirectory,
    );
    addTearDown(host.close);

    await expectLater(
      host.invoke('http.request', <String, Object?>{
        'url': 'https://example.invalid/',
      }),
      throwsA(isA<PluginHostException>()),
    );
  });

  test('system.open_uri is generic and does not require a new permission', () async {
    Uri? opened;
    final host = BasicPluginHost(
      manifest: _manifest(const <PluginPermission>{}),
      pluginDirectory: pluginDirectory,
      dataDirectory: dataDirectory,
      externalUriOpener: (uri) async {
        opened = uri;
        return true;
      },
    );
    addTearDown(host.close);

    expect(host.capabilities['open_uri'], isTrue);
    expect(
      await host.invoke('system.open_uri', <String, Object?>{
        'uri': 'luelement-engine://start',
      }),
      isTrue,
    );
    expect(opened.toString(), 'luelement-engine://start');
  });

  test('system.open_uri rejects local file and content schemes', () async {
    final host = BasicPluginHost(
      manifest: _manifest(const <PluginPermission>{}),
      pluginDirectory: pluginDirectory,
      dataDirectory: dataDirectory,
      externalUriOpener: (_) async => true,
    );
    addTearDown(host.close);

    for (final uri in <String>[
      'file:///tmp/private',
      'content://com.example/private',
      'data:text/plain,secret',
      'javascript:alert(1)',
      'intent://example/#Intent;end',
    ]) {
      await expectLater(
        host.invoke('system.open_uri', <String, Object?>{'uri': uri}),
        throwsA(isA<PluginHostException>()),
      );
    }
  });

  test('generic UI operations are delegated without a new permission', () async {
    String? operation;
    Map<String, Object?>? arguments;
    final host = BasicPluginHost(
      manifest: _manifest(const <PluginPermission>{}),
      pluginDirectory: pluginDirectory,
      dataDirectory: dataDirectory,
      uiHandler: (op, args) async {
        operation = op;
        arguments = args;
        return 2;
      },
    );
    addTearDown(host.close);

    expect(host.capabilities['ui'], isTrue);
    final result = await host.invoke('ui.select', <String, Object?>{
      'title': 'Arquivo',
      'items': <String>['A', 'B', 'C'],
    });

    expect(result, 2);
    expect(operation, 'ui.select');
    expect(arguments?['title'], 'Arquivo');
  });
}

PluginManifest _manifest(Set<PluginPermission> permissions) {
  return PluginManifest(
    id: 'com.addko.hosttest',
    name: 'Host Test',
    version: '1.0.0',
    entry: 'main.lua',
    permissions: permissions,
  );
}
