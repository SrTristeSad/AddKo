import 'dart:io';

import 'package:addko/app/addko_app.dart';
import 'package:addko/core/addons/application/addon_install_controller.dart';
import 'package:addko/core/addons/infrastructure/addon_directories.dart';
import 'package:addko/core/repositories/application/repository_registry.dart';
import 'package:addko/core/repositories/application/repository_store_controller.dart';
import 'package:addko/core/repositories/domain/repository_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('launcher exposes visual Exit, Store and Settings actions', (tester) async {
    final support = await Directory.systemTemp.createTemp('addko-widget-');
    final registry = RepositoryRegistry();
    final store = _NoopRepositoryStoreController();
    final installer = AddonInstallController(
      directories: AddonDirectories(
        supportDirectoryProvider: () async => support,
      ),
    );
    addTearDown(() async {
      registry.dispose();
      store.dispose();
      installer.dispose();
      if (await support.exists()) {
        await support.delete(recursive: true);
      }
    });

    await tester.pumpWidget(
      AddKoApp(
        repositoryRegistry: registry,
        repositoryStoreController: store,
        addonInstallController: installer,
      ),
    );
    await tester.pump();

    expect(find.text('AddKo'), findsOneWidget);
    expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
    expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
    expect(find.text('Loja'), findsNothing);
    expect(find.text('CONFIGURAÇÕES'), findsNothing);

    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Configurações'), findsOneWidget);
    expect(find.text('Addons instalados'), findsOneWidget);
    expect(find.text('Repositórios'), findsOneWidget);
    expect(find.text('Componentes de addons'), findsOneWidget);
    expect(find.text('Serviços'), findsOneWidget);
    expect(find.text('Player'), findsOneWidget);
    expect(find.text('Compatibilidade Kodi'), findsOneWidget);

    await tester.tap(find.text('Addons instalados'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum addon encontrado'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Componentes de addons'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum componente instalado'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Player'));
    await tester.pumpAndSettle();
    expect(find.text('Backend de reprodução'), findsOneWidget);
  });

  testWidgets('repository dialog can add a URL without lifecycle assertions', (tester) async {
    final support = await Directory.systemTemp.createTemp('addko-store-widget-');
    final registry = RepositoryRegistry();
    final store = _NoopRepositoryStoreController();
    final installer = AddonInstallController(
      directories: AddonDirectories(
        supportDirectoryProvider: () async => support,
      ),
    );
    addTearDown(() async {
      registry.dispose();
      store.dispose();
      installer.dispose();
      if (await support.exists()) {
        await support.delete(recursive: true);
      }
    });

    await tester.pumpWidget(
      AddKoApp(
        repositoryRegistry: registry,
        repositoryStoreController: store,
        addonInstallController: installer,
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.storefront_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum repositório configurado'), findsOneWidget);

    await tester.tap(find.text('Adicionar repositório'));
    await tester.pumpAndSettle();
    expect(find.text('Adicionar repositório'), findsNWidgets(2));

    await tester.enterText(
      find.byType(TextField),
      'https://example.com/addons.xml',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Adicionar'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('https://example.com/addons.xml'), findsOneWidget);
    expect(registry.sources, hasLength(1));
  });
}

class _NoopRepositoryStoreController extends RepositoryStoreController {
  @override
  Future<void> synchronize(RepositorySource source) async {}

  @override
  Future<void> synchronizeAll(Iterable<RepositorySource> sources) async {}
}
