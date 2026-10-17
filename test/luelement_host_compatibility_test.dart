import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:addko/src/runtime/lua_plugin_session.dart';
import 'package:addko/src/runtime/native_engine_plugin_host.dart';
import 'package:addko/src/runtime/plugin_host.dart';
import 'package:flutter_test/flutter_test.dart';

const String _sourcePath = String.fromEnvironment('LUELEMENT_PATH');
const String _nativeTestPath = String.fromEnvironment('LUA_TEST_LIBRARY');

class _FakeElementumHost extends PluginHost {
  bool running = false;
  int starts = 0;
  int stops = 0;
  int? callbackId;
  String? played;
  bool closed = false;
  final List<String> calls = <String>[];

  @override
  Map<String, bool> get capabilities => <String, bool>{
    'http': true, 'tcp_server': true, 'player': true,
    'filesystem': true, 'sleep': true, 'ui': true, 'process': false,
    'native_engines': false,
  };

  @override
  Future<Object?> invoke(String operation, Object? arguments) async {
    calls.add(operation);
    final raw = arguments as Map?;
    final args = raw == null
        ? <String, Object?>{}
        : raw.map<String, Object?>(
            (dynamic key, dynamic value) =>
                MapEntry<String, Object?>(key.toString(), value),
          );
    switch (operation) {
      case 'log':
      case 'sleep':
      case 'net.tcp.close':
        return true;
      case 'net.tcp.listen':
        callbackId = (args['callback_id'] as num).toInt();
        expect(args['host'], '127.0.0.1');
        expect(args['port'], 65221);
        return 1;
      case 'http.request':
        final url = Uri.parse(args['url'] as String);
        expect(url.host, '127.0.0.1');
        expect(url.port, 65220);
        if (!running) throw StateError('Elementum offline');
        if (url.path == '/torrents/list') {
          return <String, Object?>{'status': 200, 'body': '[]',
            'headers': <String, String>{}, 'url': url.toString()};
        }
        if (url.path == '/play') {
          expect(args['follow_redirects'], false);
          return <String, Object?>{'status': 302, 'body': '',
            'headers': <String, String>{'location': '/files/legal-test.mp4'},
            'url': url.toString()};
        }
        return <String, Object?>{'status': 200, 'body': '',
          'headers': <String, String>{}, 'url': url.toString()};
      case 'player.play':
        played = args['item'] as String?;
        return true;
      case 'player.is_playing':
      case 'player.is_paused':
        return false;
      case 'player.times':
        return <String, Object?>{'position': 0, 'duration': 60};
      case 'player.current_url':
        return played ?? '';
      case 'ui.refresh':
      case 'ui.navigate':
      case 'ui.notify':
        return true;
      case 'ui.confirm':
        return false;
      default:
        throw StateError('Unexpected host operation: $operation');
    }
  }

  @override
  Future<void> close() async { closed = true; }
}

void main() {
  test('real Luelement Lua runs through AddKo host, RPC and player', () async {
    final root = Directory(_sourcePath).absolute;
    expect(await File('${root.path}/main.lua').exists(), true);
    final json = jsonDecode(
      await File('${root.path}/manifest.json').readAsString(),
    );
    final manifest = PluginManifest.fromJson(
      (json as Map<String, dynamic>).cast<String, Object?>(),
    );
    expect(manifest.nativeEngines, contains('elementum'));
    expect(manifest.permissions, contains(PluginPermission.nativeEngine));

    final sandbox = await Directory.systemTemp.createTemp('addko-luelement-');
    final fake = _FakeElementumHost();
    final wrapped = NativeEnginePluginHost(
      inner: fake, manifest: manifest, platformSupported: true,
      invoker: (action, engine) async {
        expect(engine, 'elementum');
        fake.calls.add('native_engine.$action');
        switch (action) {
          case 'available':
            return true;
          case 'start':
            fake.running = true;
            fake.starts++;
            return true;
          case 'status':
            return <String, String>{'state': fake.running ? 'running' : 'stopped'};
          case 'stop':
            fake.running = false;
            fake.stops++;
            return true;
          default:
            throw StateError('Invalid operation: $action');
        }
      },
    );
    LuaPluginSession? session;
    try {
      session = await LuaPluginSession.open(
        pluginRoot: root.path, dataRoot: sandbox.path, entry: manifest.entry,
        platform: <String, Object?>{'os': 'android', 'arch': 'arm64'},
        locale: <String, Object?>{
          'language': 'pt', 'region': 'BR', 'second_language': '',
        },
        host: wrapped,
        testLibrary: DynamicLibrary.open(_nativeTestPath),
      );
      final result = await session.start();
      expect(result, isA<Map>());
      final doc = result as Map;
      expect(doc['type'], 'page');
      expect(doc['title'], 'Luelement');
      expect(fake.starts, 1);
      expect(fake.callbackId, isNotNull);

      final health = await session.call('service',
          <Object?>['health', <String, Object?>{}]);
      expect((health as Map)['ready'], true);

      final rpcResponse = await session.dispatchEvent(fake.callbackId!, <Object?>[
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0', 'id': 7, 'method': 'Ping',
          'params': <Object?>[],
        }),
      ]);
      expect(jsonDecode(rpcResponse as String), containsPair('result', true));

      const magnet = 'magnet:?xt=urn:btih:0123456789abcdef';
      final stream = await session.call('service',
          <Object?>['stream', <String, Object?>{'uri': magnet}]);
      expect(stream, 'http://127.0.0.1:65220/files/legal-test.mp4');

      final played = await session.call('service',
          <Object?>['play', <String, Object?>{'uri': magnet}]);
      expect((played as Map)['started'], true);
      expect(fake.played, stream);

      final stopped = await session.stop();
      expect((stopped as Map)['stopped'], true);
      expect(fake.stops, 1);
      expect(fake.calls, contains('net.tcp.close'));
    } finally {
      await session?.close();
      await sandbox.delete(recursive: true);
    }
    expect(fake.closed, true);
  }, skip: _sourcePath.isEmpty || _nativeTestPath.isEmpty
      ? 'Requires pinned Luelement and sandbox Lua test library.' : null);
}
