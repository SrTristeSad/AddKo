import 'dart:io';

import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:addko/src/plugins/plugin_package.dart';
import 'package:addko/src/ui/addko_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('launcher stays minimal and opens installed addons', (tester) async {
    final plugin = InstalledPlugin(
      directory: Directory.systemTemp,
      manifest: const PluginManifest(
        id: 'com.example.demo',
        name: 'Demo App',
        version: '1.0.0',
        entry: 'main.lua',
        permissions: <PluginPermission>{},
      ),
    );
    InstalledPlugin? opened;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: AddKoLauncher(
          plugins: <InstalledPlugin>[plugin],
          busy: false,
          activePluginIds: const <String>{},
          onOpenPlugin: (value) => opened = value,
          onOpenStore: () {},
          onOpenSettings: () {},
          onExit: () {},
        ),
      ),
    );

    expect(find.text('AddKo'), findsOneWidget);
    expect(find.text('Demo App'), findsOneWidget);
    expect(find.text('ENTRAR'), findsOneWidget);
    expect(find.text('Apps, jogos e experiências Lua'), findsNothing);
    expect(find.textContaining('Runtime Lua'), findsNothing);

    await tester.tap(find.text('ENTRAR'));
    await tester.pump();
    expect(opened, same(plugin));
  });


  testWidgets('a service addon stays off the launcher', (tester) async {
    final service = InstalledPlugin(
      directory: Directory.systemTemp,
      manifest: const PluginManifest(
        id: 'io.addko.luelement',
        name: 'Luelement',
        version: '0.2.0-dev',
        entry: 'main.lua',
        permissions: <PluginPermission>{PluginPermission.background},
        kind: PluginKind.service,
      ),
    );
    final consumer = InstalledPlugin(
      directory: Directory.systemTemp,
      manifest: const PluginManifest(
        id: 'io.addko.movie',
        name: 'Cinema',
        version: '1.0.0',
        entry: 'main.lua',
        permissions: <PluginPermission>{},
        dependencies: <String>{'io.addko.luelement'},
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: AddKoLauncher(
        plugins: <InstalledPlugin>[service, consumer],
        busy: false,
        activePluginIds: const <String>{},
        onOpenPlugin: (_) {},
        onOpenStore: () {},
        onOpenSettings: () {},
        onExit: () {},
      ),
    ));
    expect(find.text('Cinema'), findsOneWidget);
    expect(find.text('Luelement'), findsNothing);
    expect(find.text('ENTRAR'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: AddKoLauncher(
        plugins: <InstalledPlugin>[service],
        busy: false,
        activePluginIds: const <String>{},
        onOpenPlugin: (_) {},
        onOpenStore: () {},
        onOpenSettings: () {},
        onExit: () {},
      ),
    ));
    expect(find.text('Nenhum aplicativo instalado'), findsOneWidget);
    expect(find.textContaining('Gerenciar addons'), findsOneWidget);
    expect(find.text('Luelement'), findsNothing);
  });

  testWidgets('empty launcher points the user to the store', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: AddKoLauncher(
          plugins: const <InstalledPlugin>[],
          busy: false,
          activePluginIds: const <String>{},
          onOpenPlugin: (_) {},
          onOpenStore: () {},
          onOpenSettings: () {},
          onExit: () {},
        ),
      ),
    );

    expect(find.text('Nenhum addon instalado'), findsOneWidget);
    expect(find.text('Abra a Loja para começar.'), findsOneWidget);
  });

  testWidgets('store shell does not invent repository catalog data',
      (tester) async {
    var installRequested = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: AddKoStoreShell(
          busy: false,
          onInstallPackage: () => installRequested = true,
        ),
      ),
    );

    expect(find.text('Repositórios'), findsOneWidget);
    expect(find.text('Adicionar repositório'), findsOneWidget);
    expect(find.text('Instalar arquivo .addko'), findsOneWidget);
    expect(find.textContaining('128 addons'), findsNothing);

    final storeList = find.byType(ListView).first;
    await tester.drag(storeList, const Offset(0, -180));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Escolher arquivo'));
    await tester.pump();
    expect(installRequested, isTrue);

    await tester.drag(storeList, const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(find.text('Sua loja ainda está vazia'), findsOneWidget);
  });
}
