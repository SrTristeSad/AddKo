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
