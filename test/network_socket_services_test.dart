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
    root = await Directory.systemTemp.createTemp('addko-network-');
    pluginDirectory = await Directory(
      root.uri.resolve('plugin/').toFilePath(),
    ).create(recursive: true);
    dataDirectory = await Directory(
      root.uri.resolve('data/').toFilePath(),
    ).create(recursive: true);
  });

  tearDown(() async => root.delete(recursive: true));

  BasicPluginHost host({bool network = true, bool background = false}) {
    final permissions = <PluginPermission>{
      if (network) PluginPermission.network,
      if (background) PluginPermission.background,
    };
    final instance = BasicPluginHost(
      manifest: PluginManifest(
        id: 'com.addko.networktest',
        name: 'Network test',
        version: '1.0.0',
        entry: 'main.lua',
        permissions: permissions,
      ),
      pluginDirectory: pluginDirectory,
      dataDirectory: dataDirectory,
    );
    addTearDown(instance.close);
    return instance;
  }

  test('DNS resolution and all new transports require network permission',
      () async {
    final restricted = host(network: false);
    expect(restricted.capabilities['dns_lookup'], false);
    expect(restricted.capabilities['udp'], false);
    expect(restricted.capabilities['websocket'], false);
    for (final request in <(String, Map<String, Object?>)>[
      ('net.dns.lookup', <String, Object?>{'host': 'localhost'}),
      ('net.udp.open', <String, Object?>{}),
      ('net.websocket.connect',
          <String, Object?>{'url': 'ws://127.0.0.1:1234'}),
    ]) {
      await expectLater(
        restricted.invoke(request.$1, request.$2),
        throwsA(isA<PluginHostException>()),
      );
    }

    final allowed = host();
    expect(allowed.capabilities['dns_lookup'], true);
    final result = await allowed.invoke('net.dns.lookup', <String, Object?>{
      'host': 'localhost',
      'family': 'ipv4',
    }) as List;
    expect(result, contains('127.0.0.1'));
  });

  test('UDP sends and receives datagrams with address and port', () async {
    final server = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4, 0,
    );
    addTearDown(server.close);
    server.listen((event) {
      if (event == RawSocketEvent.read) {
        final request = server.receive();
        if (request != null) {
          server.send(request.data, request.address, request.port);
        }
      }
    });
    final client = host();
    final handle = await client.invoke('net.udp.open', <String, Object?>{
      'bind': 'loopback',
    }) as int;
    final sent = await client.invoke('net.udp.send', <String, Object?>{
      'handle': handle,
      'host': '127.0.0.1',
      'port': server.port,
      'data': <int>[0, 1, 127, 255],
    }) as Map;
    expect(sent['sent'], 4);
    final received = await client.invoke('net.udp.receive',
        <String, Object?>{'handle': handle}) as Map;
    expect(received['bytes'], <int>[0, 1, 127, 255]);
    expect(received['port'], server.port);
    expect(received['host'], '127.0.0.1');
    expect(received['timed_out'], false);
    expect(await client.invoke('net.udp.close',
        <String, Object?>{'handle': handle}), true);
    await expectLater(
      client.invoke('net.udp.receive', <String, Object?>{'handle': handle}),
      throwsA(isA<Exception>()),
    );
  });

  test('UDP timeout is separate from a closed socket', () async {
    final client = host();
    final handle = await client.invoke('net.udp.open', <String, Object?>{
      'bind': 'loopback',
    }) as int;
    final result = await client.invoke('net.udp.receive',
        <String, Object?>{'handle': handle, 'timeout_ms': 25}) as Map;
    expect(result['bytes'], isEmpty);
    expect(result['timed_out'], true);
    expect(result['closed'], false);
  });

  test('fixed-port public UDP listener requires background permission',
      () async {
    final client = host();
    await expectLater(
      client.invoke('net.udp.open', <String, Object?>{
        'port': 12345, 'bind': 'any',
      }),
      throwsA(isA<PluginHostException>()),
    );
  });

  test('WebSocket carries UTF-8 text and arbitrary binary messages', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.transform(WebSocketTransformer()).listen((socket) {
      socket.listen(socket.add);
    });
    final client = host();
    final handle = await client.invoke('net.websocket.connect',
        <String, Object?>{
      'url': 'ws://127.0.0.1:' + server.port.toString(),
    }) as int;
    expect(client.capabilities['websocket'], true);
    expect(await client.invoke('net.websocket.send',
        <String, Object?>{'handle': handle, 'data': 'olá'}), true);
    final textMessage = await client.invoke('net.websocket.receive',
        <String, Object?>{'handle': handle}) as Map;
    expect(textMessage['type'], 'text');
    expect(textMessage['text'], 'olá');
    expect(textMessage['timed_out'], false);

    expect(await client.invoke('net.websocket.send', <String, Object?>{
      'handle': handle,
      'data': <int>[0, 8, 128, 255],
    }), true);
    final binaryMessage = await client.invoke('net.websocket.receive',
        <String, Object?>{'handle': handle}) as Map;
    expect(binaryMessage['type'], 'binary');
    expect(binaryMessage['bytes'], <int>[0, 8, 128, 255]);

    expect(await client.invoke('net.websocket.close',
        <String, Object?>{'handle': handle}), true);
  });

  test('WebSocket rejects oversized payload and unsafe headers', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.transform(WebSocketTransformer()).listen((socket) {
      socket.listen((_) {});
    });
    final client = host();
    final url = 'ws://127.0.0.1:' + server.port.toString();
    await expectLater(
      client.invoke('net.websocket.connect', <String, Object?>{
        'url': url,
        'headers': <String, String>{'Host': 'example.org'},
      }),
      throwsA(isA<Exception>()),
    );
    final handle = await client.invoke('net.websocket.connect',
        <String, Object?>{'url': url}) as int;
    await expectLater(
      client.invoke('net.websocket.send', <String, Object?>{
        'handle': handle,
        'data': List<int>.filled(65537, 1),
      }),
      throwsA(isA<Exception>()),
    );
    final timed = await client.invoke('net.websocket.receive',
        <String, Object?>{'handle': handle, 'timeout_ms': 25}) as Map;
    expect(timed['timed_out'], true);
    expect(timed['closed'], false);
  });

  test('websocket/dns enforce structured arguments', () async {
    final client = host();
    for (final url in <String>['http://example.org', 'file:///private']) {
      await expectLater(
        client.invoke('net.websocket.connect',
            <String, Object?>{'url': url}),
        throwsA(isA<Exception>()),
      );
    }
    await expectLater(
      client.invoke('net.dns.lookup', <String, Object?>{
        'host': '127.0.0.1',
        'family': 'invalid',
      }),
      throwsA(isA<Exception>()),
    );
  });
}
