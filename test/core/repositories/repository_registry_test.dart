import 'package:addko/core/repositories/application/repository_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adds and deduplicates repository URLs', () {
    final registry = RepositoryRegistry();
    addTearDown(registry.dispose);

    registry.addUrl('https://example.com/repository/');
    expect(registry.sources, hasLength(1));

    expect(
      () => registry.addUrl('https://example.com/repository/'),
      throwsFormatException,
    );
  });

  test('rejects non HTTP repository URLs', () {
    final registry = RepositoryRegistry();
    addTearDown(registry.dispose);

    expect(
      () => registry.addUrl('file:///tmp/repository'),
      throwsFormatException,
    );
  });
}
