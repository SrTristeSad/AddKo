import 'dart:io';

import 'package:addko/app/addko_app.dart';
import 'package:addko/core/addons/application/addon_install_controller.dart';
import 'package:addko/core/addons/infrastructure/addon_directories.dart';
import 'package:addko/core/repositories/application/repository_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('launcher exposes visual Exit, Store and Settings actions', (tester) async {
    final support = await Directory.systemTemp.createTemp('addko-widget-');
    final registry = RepositoryRegistry();
    final installer = AddonInstallController(
      directories: AddonDirectories(
        supportDirectoryProvider: () async => support,
      ),
    );
    addTearDown(() async {
      registry.dispose();
      installer.dispose();
      if (await support.exists()) {
        await support.delete(recursive: true);
      }
    });

    await tester.pumpWidget(
      AddKoApp(
        repositoryRegistry: registry,
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
    expect(find.text('Serviços'), findsOneWidget);
    expect(find.text('Compatibilidade Kodi'), findsOneWidget);
  });
}
