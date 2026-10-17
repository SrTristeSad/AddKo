import 'dart:io';

import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:addko/src/plugins/plugin_package.dart';
import 'package:addko/src/repositories/addko_repositories.dart';
import 'package:addko/src/ui/addko_installed_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _StaticRepositories extends AddKoRepositoryManager {
  _StaticRepositories() : super(File('not-used-for-widget-test.json'));

  @override
  Future<List<RepositoryStatus>> refresh() async => <RepositoryStatus>[];
}

InstalledPlugin _installed({
  String id = 'com.addko.demo',
  String name = 'Demo',
  Set<String> dependencies = const <String>{},
}) =>
    InstalledPlugin(
      directory: Directory.systemTemp,
      manifest: PluginManifest(
        id: id,
        name: name,
        version: '1.0.0',
        entry: 'main.lua',
        permissions: const <PluginPermission>{
          PluginPermission.storage,
          PluginPermission.network,
        },
        dependencies: dependencies,
      ),
    );

void main() {
  testWidgets('shows real manifest permissions and supports safe removal',
      (tester) async {
    final item = _installed();
    bool? deleteData;
    var remaining = <InstalledPlugin>[item];
    await tester.pumpWidget(MaterialApp(
      home: AddKoInstalledManager(
        installed: remaining,
        repositories: _StaticRepositories(),
        onRemove: (plugin, erase) async {
          expect(plugin, same(item));
          deleteData = erase;
          remaining = <InstalledPlugin>[];
        },
        onReload: () async => remaining,
        onOpenStore: () async {},
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo'));
    await tester.pumpAndSettle();
    expect(find.text('Rede — acesso HTTP/HTTPS.'), findsOneWidget);
    expect(find.text('Armazenamento — arquivos próprios e dados privados.'),
        findsOneWidget);
    await tester.tap(find.text('Desinstalar'));
    await tester.pumpAndSettle();
    expect(find.text('Apagar também os dados do addon'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desinstalar').last);
    await tester.pumpAndSettle();
    expect(deleteData, isTrue);
    expect(find.text('Nenhum addon instalado.'), findsOneWidget);
  });

  testWidgets('prevents removal while an installed addon depends on it',
      (tester) async {
    final core = _installed();
    final client = _installed(
      id: 'com.addko.client',
      name: 'Cliente',
      dependencies: const <String>{'com.addko.demo'},
    );
    var removalCalled = false;
    await tester.pumpWidget(MaterialApp(
      home: AddKoInstalledManager(
        installed: <InstalledPlugin>[core, client],
        repositories: _StaticRepositories(),
        onRemove: (_, __) async => removalCalled = true,
        onReload: () async => <InstalledPlugin>[core, client],
        onOpenStore: () async {},
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo'));
    await tester.pumpAndSettle();
    expect(find.text('• Cliente'), findsOneWidget);
    final removeButton = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Desinstalar'),
        matching: find.byType(TextButton),
      ),
    );
    expect(removeButton.onPressed, isNull);
    expect(removalCalled, isFalse);
  });
}
