import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:addko/core/runtime/kodi/kodi_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <Map<String, dynamic>>[];
  dynamic Function(Map<String, dynamic>) respond = (_) => 'OK';
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(KodiCore.channel, (call) async {
      if (call.method == 'status') return {'ready': true};
      final request = Map<String, dynamic>.from(
          jsonDecode((call.arguments as Map)['request'] as String) as Map);
      calls.add(request);
      return jsonEncode(
          {'jsonrpc': '2.0', 'id': request['id'], 'result': respond(request)});
    });
    respond = (_) => 'OK';
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(KodiCore.channel, null));
  test('native directory preserves plugin folder URLs and content order',
      () async {
    respond = (_) => {
          'files': [
            {
              'label': 'B',
              'file': 'plugin://plugin.video.example/?page=2',
              'filetype': 'directory'
            },
            {
              'label': 'A',
              'file': 'plugin://plugin.video.example/?play=9',
              'filetype': 'file'
            }
          ]
        };
    final items = await KodiCore.directory('plugin://plugin.video.example/');
    expect(items.first['filetype'], 'directory');
    expect(items.last['file'], 'plugin://plugin.video.example/?play=9');
    expect(calls.single['method'], 'Files.GetDirectory');
    expect((calls.single['params'] as Map)['sort'], {'method': 'none'});
  });
  test('enabling scans native manager without activating Kodi menus', () async {
    await KodiCore.prepareAddon('plugin.video.example');
    expect(calls.map((e) => e['method']), [
      'Addons.ExecuteAddon',
      'Addons.GetAddonDetails',
      'Addons.SetAddonEnabled'
    ]);
    expect((calls.first['params'] as Map)['params'], ['refresh', '']);
  });
  test('invalid directory result produces visible failure', () async {
    respond = (_) => 'OK';
    await expectLater(
        KodiCore.directory('plugin://example/'), throwsStateError);
  });
  test('playback gives unresolved plugin URL to the native player', () async {
    await KodiCore.rpc('Player.Open', {
      'item': {'file': 'plugin://example/?play=1'}
    });
    expect((calls.single['params'] as Map)['item'],
        {'file': 'plugin://example/?play=1'});
  });
  test('native errors are propagated, not converted to success', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(KodiCore.channel, (call) async {
      final request =
          jsonDecode((call.arguments as Map)['request'] as String) as Map;
      return jsonEncode({
        'jsonrpc': '2.0',
        'id': request['id'],
        'error': {'code': -32602, 'message': 'Invalid params'}
      });
    });
    await expectLater(KodiCore.rpc('Player.Open'), throwsStateError);
  });
  test('rejects mismatched native response IDs', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            KodiCore.channel,
            (call) async =>
                jsonEncode({'jsonrpc': '2.0', 'id': -1, 'result': 'OK'}));
    await expectLater(KodiCore.rpc('JSONRPC.Version'), throwsStateError);
  });
}
