import 'dart:convert';

import 'package:addko/core/repositories/infrastructure/repository_checksum_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const verifier = RepositoryChecksumVerifier();
  final bytes = utf8.encode('hello');

  test('accepts Kodi-style MD5 checksum documents', () {
    expect(
      verifier.matches(
        bytes,
        '5d41402abc4b2a76b9719d911017c592  addons.xml',
      ),
      isTrue,
    );
  });

  test('accepts SHA-1 and SHA-256 digests', () {
    expect(
      verifier.matches(bytes, 'aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d'),
      isTrue,
    );
    expect(
      verifier.matches(
        bytes,
        '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
      ),
      isTrue,
    );
  });

  test('rejects mismatching digests', () {
    expect(
      verifier.matches(bytes, '00000000000000000000000000000000'),
      isFalse,
    );
  });

  test('rejects unknown checksum documents', () {
    expect(
      () => verifier.matches(bytes, 'not-a-checksum'),
      throwsA(isA<RepositoryChecksumException>()),
    );
  });
}
