import 'dart:convert';
import 'dart:io';

import 'package:addko/src/repositories/addko_repositories.dart';
import 'package:addko/src/repositories/catalog_version.dart';
import 'package:addko/src/ui/addko_repository_store.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  final url = Uri.parse('https://catalog.example.com/addko/index.json');
  final bytes = utf8.encode('pacote de teste');

  Map<String, Object?> catalog({
    String? checksum,
    String file = 'packages/demo.addko',
    String category = 'Outros',
  }) =>
      <String, Object?>{
        'schema': 1,
        'name': 'Catálogo da comunidade',
        'addons': <Object?>[
          <String, Object?>{
            'id': 'com.addko.demo',
            'name': 'Miniapp Demo',
            'version': '1.0.0',
            'description': 'Demo de repositório',
            'category': category,
            'file': file,
            'sha256': checksum ?? sha256.convert(bytes).toString(),
          },
        ],
      };

  AddKoRepositoryManager service(
    Map<String, Object?> index, {
    List<int>? downloaded,
  }) {
    return AddKoRepositoryManager(
      File('${temp.path}/repositories.json'),
      fetcher: (uri, limit) async =>
          uri.path.endsWith('.json')
              ? utf8.encode(jsonEncode(index))
              : downloaded ?? bytes,
    );
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('addko-repo-test-');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('requires a public HTTPS JSON index', () {
    for (final invalid in <String>[
      'http://catalog.example.com/index.json',
      'https://localhost/index.json',
      'https://127.0.0.1/index.json',
      'https://192.168.0.1/index.json',
      'https://catalog.local/index.json',
      'https://user:password@catalog.example.com/index.json',
      'https://catalog.example.com/index.json#hash',
      'https://catalog.example.com/index.json?token=secret',
      'https://catalog.example.com/catalog.zip',
    ]) {
      expect(
        () => AddKoRepositoryManager.parseRepositoryUrl(invalid),
        throwsA(isA<RepositoryException>()),
        reason: invalid,
      );
    }
    expect(AddKoRepositoryManager.parseRepositoryUrl(url.toString()), url);
  });

  test('validates catalog, persists source and removes it', () async {
    final manager = service(catalog());
    final added = await manager.add(url.toString());
    expect(added.name, 'Catálogo da comunidade');
    expect(added.addons.single.file.toString(),
        'https://catalog.example.com/addko/packages/demo.addko');
    expect(await manager.savedUrls(), <Uri>[url]);
    expect((await manager.refresh()).single.index!.addons, hasLength(1));

    await expectLater(
      manager.add(url.toString()),
      throwsA(isA<RepositoryException>()),
    );
    await manager.remove(url);
    expect(await manager.savedUrls(), isEmpty);
  });

  test('does not persist invalid catalog', () async {
    final manager = service(<String, Object?>{
      'schema': 99,
      'name': 'Incompatível',
      'addons': <Object?>[],
    });
    await expectLater(
      manager.add(url.toString()),
      throwsA(isA<RepositoryException>()),
    );
    expect(await manager.savedUrls(), isEmpty);
  });

  test('rejects duplicate IDs, unpinned and unsafe package paths', () async {
    final missingDigest = catalog()..['addons'] = <Object?>[
      <String, Object?>{
        'id': 'com.addko.demo',
        'name': 'Demo',
        'version': '1',
        'file': 'demo.addko',
      }
    ];
    await expectLater(
      service(missingDigest).loadIndex(url),
      throwsA(isA<RepositoryException>()),
    );

    await expectLater(
      service(catalog(file: '../outside.addko')).loadIndex(url),
      throwsA(isA<RepositoryException>()),
    );

    final duplicated = catalog();
    final entries = duplicated['addons'] as List<Object?>;
    entries.add(Map<String, Object?>.from(entries.single as Map));
    await expectLater(
      service(duplicated).loadIndex(url),
      throwsA(isA<RepositoryException>()),
    );
  });

  test('checks SHA-256 of downloaded package before installation', () async {
    final manager = service(catalog());
    final addon = (await manager.loadIndex(url)).addons.single;
    expect(await manager.download(addon), bytes);

    final tampered = service(catalog(), downloaded: utf8.encode('alterado'));
    await expectLater(
      tampered.download(addon),
      throwsA(isA<RepositoryException>()),
    );
  });

  test('a failing repository remains saved with an error state', () async {
    final manager = service(catalog());
    await manager.add(url.toString());
    final failing = AddKoRepositoryManager(
      File('${temp.path}/repositories.json'),
      fetcher: (uri, limit) async {
        throw const RepositoryException('Servidor indisponível.');
      },
    );
    final status = (await failing.refresh()).single;
    expect(status.url, url);
    expect(status.index, isNull);
    expect(status.error, contains('Servidor indisponível'));
    expect(await failing.savedUrls(), <Uri>[url]);
  });


  test('categorizes addons and validates checksum-pinned images', () async {
    final png = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1];
    final index = catalog(category: 'Jogos');
    final addon = (index['addons'] as List).first as Map<String, Object?>;
    addon['icon'] = 'icons/controller.png';
    addon['icon_sha256'] = sha256.convert(png).toString();
    final manager = AddKoRepositoryManager(
      File('${temp.path}/repositories.json'),
      fetcher: (uri, maxBytes) async {
        if (uri.path.endsWith('.json')) return utf8.encode(jsonEncode(index));
        if (uri.path.endsWith('.png')) return png;
        return bytes;
      },
    );
    final parsed = (await manager.loadIndex(url)).addons.single;
    expect(parsed.category, 'Jogos');
    expect(parsed.icon.toString(),
        'https://catalog.example.com/addko/icons/controller.png');
    expect(await manager.downloadIcon(parsed), png);

    final tampered = AddKoRepositoryManager(
      File('${temp.path}/tampered.json'),
      fetcher: (_, __) async => <int>[...png, 2],
    );
    await expectLater(
      tampered.downloadIcon(parsed),
      throwsA(isA<RepositoryException>()),
    );
    addon.remove('icon_sha256');
    await expectLater(
      manager.loadIndex(url),
      throwsA(isA<RepositoryException>()),
    );
    addon['icon_sha256'] = sha256.convert(png).toString();
    addon['icon'] = '../controller.png';
    await expectLater(
      manager.loadIndex(url),
      throwsA(isA<RepositoryException>()),
    );
  });

  test('compares update status only when version order is sound', () {
    expect(catalogVersionStatus('1.2.0', null),
        CatalogVersionStatus.notInstalled);
    expect(catalogVersionStatus('1.2.0', '1.2.0'),
        CatalogVersionStatus.installed);
    expect(catalogVersionStatus('1.10.0', '1.9.0'),
        CatalogVersionStatus.updateAvailable);
    expect(catalogVersionStatus('1.0.0', '2.0.0'),
        CatalogVersionStatus.installedNewer);
    expect(catalogVersionStatus('1.0.0', '1.0.0-beta.1'),
        CatalogVersionStatus.updateAvailable);
    expect(catalogVersionStatus('beta', 'alpha'),
        CatalogVersionStatus.differentVersion);
  });

  testWidgets('store distinguishes updates from installed versions',
      (tester) async {
    final repo = _MemoryRepositories(
      await service(catalog(category: 'Jogos')).loadIndex(url),
    )..added = true;
    await tester.pumpWidget(MaterialApp(
      home: AddKoRepositoryStore(
        repositories: repo,
        installedVersions: const <String, String>{
          'com.addko.demo': '0.9.0',
        },
        onInstallPackage: () {},
        onInstallAddon: (_) async => true,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Atualização disponível'), findsOneWidget);
    expect(find.text('Jogos'), findsWidgets);
    await tester.tap(find.text('Detalhes'));
    await tester.pumpAndSettle();
    expect(find.text('Versão instalada: 0.9.0'), findsOneWidget);
    expect(find.text('Atualizar'), findsOneWidget);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
  });

  testWidgets('store adds repository and installs a listed addon',
      (tester) async {
    final manager = _MemoryRepositories(await service(catalog()).loadIndex(url));
    RepositoryAddon? requested;
    await tester.pumpWidget(MaterialApp(
      home: AddKoRepositoryStore(
        repositories: manager,
        onInstallPackage: () {},
        onInstallAddon: (addon) async {
          requested = addon;
          return true;
        },
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Sua loja ainda está vazia'), findsOneWidget);
    await tester.tap(find.text('Adicionar repositório'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), url.toString());
    await tester.tap(find.text('Validar e adicionar'));
    await tester.pumpAndSettle();

    expect(find.text('Catálogo da comunidade'), findsOneWidget);
    expect(find.text('Miniapp Demo'), findsOneWidget);
    await tester.ensureVisible(find.text('Detalhes'));
    await tester.tap(find.text('Detalhes'));
    await tester.pumpAndSettle();
    expect(find.text('Versão instalada: Nenhuma'), findsOneWidget);
    await tester.ensureVisible(find.text('Instalar'));
    await tester.tap(find.text('Instalar'));
    await tester.pumpAndSettle();
    expect(requested?.id, 'com.addko.demo');
    expect(find.text('Instalado'), findsOneWidget);
  });
}

class _MemoryRepositories extends AddKoRepositoryManager {
  _MemoryRepositories(this.catalog) : super(File('not-used-in-widget-test.json'));

  final RepositoryIndex catalog;
  bool added = false;

  @override
  Future<RepositoryIndex> add(String source) async {
    if (source != catalog.url.toString()) {
      throw const RepositoryException('URL inesperada.');
    }
    added = true;
    return catalog;
  }

  @override
  Future<List<RepositoryStatus>> refresh() async => added
      ? <RepositoryStatus>[RepositoryStatus(url: catalog.url, index: catalog)]
      : <RepositoryStatus>[];
}
