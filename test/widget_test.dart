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
  testWidgets(
    'launcher exposes visual Exit, Store and Settings actions',
    (tester) async {
      final support = await Directory.systemTemp.createTemp('addko-widget-');
      final registry = RepositoryRegistry();
      final store = _NoopRepositoryStoreController();
      final installer = AddonInstallController(
        directories: AddonDirectories(
          supportDirectoryProvider: () async => support,
        ),
      );

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
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
      await _pumpRoute(tester);

      expect(find.text('Configurações'), findsOneWidget);
      expect(find.text('Addons instalados'), findsOneWidget);
      expect(find.text('Repositórios'), findsOneWidget);
      expect(find.text('Componentes de addons'), findsOneWidget);
      expect(find.text('Serviços'), findsOneWidget);
      expect(find.text('Player'), findsOneWidget);
      expect(find.text('Compatibilidade Kodi'), findsOneWidget);

      await tester.tap(find.text('Addons instalados'));
      await _pumpRoute(tester);
      expect(find.text('Nenhum addon encontrado'), findsOneWidget);
      await tester.pageBack();
      await _pumpRoute(tester);

      await tester.tap(find.text('Componentes de addons'));
      await _pumpRoute(tester);
      expect(find.text('Nenhum componente instalado'), findsOneWidget);
      await tester.pageBack();
      await _pumpRoute(tester);

      await tester.tap(find.text('Player'));
      await _pumpRoute(tester);
      expect(find.text('Backend de reprodução'), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'repository dialog can add a URL without lifecycle assertions',
    (tester) async {
      final support =
          await Directory.systemTemp.createTemp('addko-store-widget-');
      final registry = RepositoryRegistry();
      final store = _NoopRepositoryStoreController();
      final installer = AddonInstallController(
        directories: AddonDirectories(
          supportDirectoryProvider: () async => support,
        ),
      );

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
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
      await _pumpRoute(tester);
      expect(find.text('Nenhum repositório configurado'), findsOneWidget);

      await tester.tap(find.text('Adicionar repositório'));
      await _pumpRoute(tester);
      expect(find.text('Adicionar repositório'), findsNWidgets(2));

      await tester.enterText(
        find.byType(TextField),
        'https://example.com/addons.xml',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Adicionar'));
      await _pumpRoute(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('https://example.com/addons.xml'), findsOneWidget);
      expect(registry.sources, hasLength(1));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

Future<void> _pumpRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
}

class _NoopRepositoryStoreController extends RepositoryStoreController {
  @override
  Future<void> ensureKodiSystemCatalog() async {}

  @override
  Future<void> synchronize(RepositorySource source) async {}

  @override
  Future<void> synchronizeAll(Iterable<RepositorySource> sources) async {}
}
