import 'dart:async';

import 'package:addko/core/repositories/application/repository_registry.dart';
import 'package:addko/core/repositories/domain/repository_source.dart';
import 'package:addko/core/repositories/domain/repository_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adds and deduplicates repository URLs', () async {
    final registry = RepositoryRegistry();
    addTearDown(registry.dispose);

    await registry.addUrl('https://example.com/repository/');
    expect(registry.sources, hasLength(1));

    await expectLater(
      registry.addUrl('https://example.com/repository/'),
      throwsFormatException,
    );
  });

  test('rejects non HTTP repository URLs', () async {
    final registry = RepositoryRegistry();
    addTearDown(registry.dispose);

    await expectLater(
      registry.addUrl('file:///tmp/repository'),
      throwsFormatException,
    );
  });

  test('loads and persists repository sources', () async {
    final storage = _MemoryRepositoryStorage([
      RepositorySource(
        uri: Uri.parse('https://example.com/repo/'),
        enabled: false,
      ),
    ]);
    final registry = RepositoryRegistry(storage: storage);
    addTearDown(registry.dispose);

    await registry.initialize();
    expect(registry.sources, hasLength(1));
    expect(registry.sources.single.enabled, isFalse);

    await registry.setEnabled(registry.sources.single.uri, true);
    expect(storage.saved.single.enabled, isTrue);
  });

  test('mutation waits for initialization instead of losing a new source', () async {
    final gate = Completer<void>();
    final storage = _DelayedRepositoryStorage(gate);
    final registry = RepositoryRegistry(storage: storage);
    addTearDown(registry.dispose);

    final initializing = registry.initialize();
    final adding = registry.addUrl('https://new.example/repository/');
    await Future<void>.delayed(Duration.zero);
    expect(registry.sources, isEmpty);

    gate.complete();
    await Future.wait([initializing, adding]);

    expect(registry.sources.map((source) => source.uri.toString()), contains(
      'https://new.example/repository/',
    ));
    expect(storage.saved, hasLength(2));
  });

  test('failed persistence does not corrupt in-memory sources', () async {
    final storage = _FailingRepositoryStorage([
      RepositorySource(
        uri: Uri.parse('https://existing.example/repo/'),
        enabled: true,
      ),
    ]);
    final registry = RepositoryRegistry(storage: storage);
    addTearDown(registry.dispose);
    await registry.initialize();

    storage.failWrites = true;
    await expectLater(
      registry.addUrl('https://new.example/repo/'),
      throwsA(isA<StateError>()),
    );

    expect(registry.sources, hasLength(1));
    expect(registry.sources.single.uri.host, 'existing.example');
  });

  test('persists resolved endpoints from repository addon packages', () async {
    final storage = _MemoryRepositoryStorage([]);
    final registry = RepositoryRegistry(storage: storage);
    addTearDown(registry.dispose);
    await registry.initialize();

    await registry.addResolvedEndpoint(
      infoUri: Uri.parse('https://repo.example/addons.xml.gz'),
      packageBaseUri: Uri.parse('https://repo.example/zips/'),
      checksumUri: Uri.parse('https://repo.example/addons.xml.gz.sha256'),
      name: 'Example Repository',
    );

    expect(registry.sources, hasLength(1));
    final source = registry.sources.single;
    expect(source.displayName, 'Example Repository');
    expect(source.packageBaseUri, Uri.parse('https://repo.example/zips/'));
    expect(
      source.checksumUri,
      Uri.parse('https://repo.example/addons.xml.gz.sha256'),
    );
    expect(storage.saved.single.hasResolvedEndpoint, isTrue);

    final restored = RepositorySource.fromJson(source.toJson());
    expect(restored.uri, source.uri);
    expect(restored.packageBaseUri, source.packageBaseUri);
    expect(restored.checksumUri, source.checksumUri);
    expect(restored.name, source.name);
  });
}

class _MemoryRepositoryStorage implements RepositoryStorage {
  _MemoryRepositoryStorage(this.saved);

  List<RepositorySource> saved;

  @override
  Future<List<RepositorySource>> load() async => List.of(saved);

  @override
  Future<void> save(List<RepositorySource> sources) async {
    saved = List.of(sources);
  }
}

class _DelayedRepositoryStorage implements RepositoryStorage {
  _DelayedRepositoryStorage(this.gate)
      : saved = [
          RepositorySource(
            uri: Uri.parse('https://existing.example/repo/'),
            enabled: true,
          ),
        ];

  final Completer<void> gate;
  List<RepositorySource> saved;

  @override
  Future<List<RepositorySource>> load() async {
    await gate.future;
    return List.of(saved);
  }

  @override
  Future<void> save(List<RepositorySource> sources) async {
    saved = List.of(sources);
  }
}

class _FailingRepositoryStorage extends _MemoryRepositoryStorage {
  _FailingRepositoryStorage(super.saved);

  bool failWrites = false;

  @override
  Future<void> save(List<RepositorySource> sources) async {
    if (failWrites) {
      throw StateError('simulated write failure');
    }
    await super.save(sources);
  }
}
