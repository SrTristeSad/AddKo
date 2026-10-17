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
