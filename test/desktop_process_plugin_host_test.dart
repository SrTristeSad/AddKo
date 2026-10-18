import 'dart:io';

import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:addko/src/runtime/desktop_process_plugin_host.dart';
import 'package:addko/src/runtime/plugin_host.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop process host exposes process only with background+storage', () async {
    final root = await Directory.systemTemp.createTemp('addko-process-host-');
    addTearDown(() => root.delete(recursive: true));

    final plugin = Directory('${root.path}${Platform.pathSeparator}plugin');
    final data = Directory('${root.path}${Platform.pathSeparator}data');
    await plugin.create();
    await data.create();

    final host = DesktopProcessPluginHost(
      inner: _FakeHost(),
      manifest: const PluginManifest(
        id: 'com.example.process',
        name: 'Process',
        version: '1.0.0',
        entry: 'main.lua',
        permissions: <PluginPermission>{
          PluginPermission.storage,
          PluginPermission.background,
        },
      ),
      pluginDirectory: plugin,
      dataDirectory: data,
    );

    expect(host.capabilities['process'], !Platform.isAndroid && !Platform.isIOS);
    await host.close();
  });

  test('desktop process host rejects executable outside plugin sandbox', () async {
    if (Platform.isAndroid || Platform.isIOS) return;

    final root = await Directory.systemTemp.createTemp('addko-process-host-');
    addTearDown(() => root.delete(recursive: true));

    final plugin = Directory('${root.path}${Platform.pathSeparator}plugin');
    final data = Directory('${root.path}${Platform.pathSeparator}data');
    await plugin.create();
    await data.create();

    final host = DesktopProcessPluginHost(
      inner: _FakeHost(),
      manifest: const PluginManifest(
        id: 'com.example.process',
        name: 'Process',
        version: '1.0.0',
        entry: 'main.lua',
        permissions: <PluginPermission>{
          PluginPermission.storage,
          PluginPermission.background,
        },
      ),
      pluginDirectory: plugin,
      dataDirectory: data,
    );

    final outside = File('${root.path}${Platform.pathSeparator}outside-bin');
    await outside.writeAsString('not executable');

    await expectLater(
      host.invoke('process.spawn', <String, Object?>{
        'path': outside.path,
        'args': const <String>[],
      }),
      throwsA(isA<DesktopProcessHostException>()),
    );

    await host.close();
  });
}

class _FakeHost extends PluginHost {
  @override
  Map<String, bool> get capabilities => const <String, bool>{};

  @override
  Future<Object?> invoke(String operation, Object? arguments) async => true;
}
