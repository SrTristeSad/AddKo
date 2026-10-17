import 'dart:io';

import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:addko/src/runtime/basic_plugin_host.dart';
import 'package:addko/src/runtime/native_engine_plugin_host.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory scratch;
  setUp(() async => scratch =
      await Directory.systemTemp.createTemp('addko-native-host-'));
  tearDown(() async => scratch.delete(recursive: true));

  PluginManifest makeManifest({
    bool permission = true,
    Set<String> engines = const <String>{'elementum'},
  }) => PluginManifest(
        id: 'io.addko.native.demo',
        name: 'Demo',
        version: '1',
        entry: 'main.lua',
        permissions: permission
            ? const <PluginPermission>{PluginPermission.nativeEngine}
            : const <PluginPermission>{},
        nativeEngines: engines,
      );

  NativeEnginePluginHost host(
    PluginManifest manifest,
    List<String> calls,
  ) => NativeEnginePluginHost(
        inner: BasicPluginHost(
          manifest: manifest,
          pluginDirectory: scratch,
          dataDirectory: scratch,
        ),
        manifest: manifest,
        platformSupported: true,
        invoker: (action, engine) async {
          calls.add('$action:$engine');
          return action == 'available';
        },
      );

  test('dispatches allowed operations and rejects unlisted engines', () async {
    final calls = <String>[];
    final wrapped = host(makeManifest(), calls);
    expect(wrapped.capabilities['native_engines'], isTrue);
    expect(
      await wrapped.invoke(
        'native_engine.available', <String, Object?>{'engine': 'elementum'},
      ),
      isTrue,
    );
    expect(calls, <String>['available:elementum']);
    await expectLater(
      wrapped.invoke('native_engine.start', <String, Object?>{'engine': 'other'}),
      throwsStateError,
    );
    await expectLater(
      wrapped.invoke('native_engine.load', <String, Object?>{'engine': 'elementum'}),
      throwsStateError,
    );
    expect(calls, hasLength(1));
    await wrapped.close();
  });

  test('denies undeclared permission and non-Android hosts', () async {
    final calls = <String>[];
    final wrapped = host(makeManifest(permission: false), calls);
    expect(wrapped.capabilities['native_engines'], isFalse);
    await expectLater(
      wrapped.invoke('native_engine.start', <String, Object?>{'engine': 'elementum'}),
      throwsStateError,
    );
    expect(calls, isEmpty);
    await wrapped.close();

    final offHost = NativeEnginePluginHost(
      inner: BasicPluginHost(
        manifest: makeManifest(),
        pluginDirectory: scratch,
        dataDirectory: scratch,
      ),
      manifest: makeManifest(),
      platformSupported: false,
      invoker: (_, __) async => true,
    );
    expect(offHost.capabilities['native_engines'], isFalse);
    await offHost.close();
  });
}
