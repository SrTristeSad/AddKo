import 'dart:convert';

import 'package:crypto/crypto.dart';

class RepositoryChecksumException implements Exception {
  const RepositoryChecksumException(this.message);

  final String message;

  @override
  String toString() => 'RepositoryChecksumException: $message';
}

class RepositoryChecksumVerifier {
  const RepositoryChecksumVerifier();

  bool matches(List<int> bytes, String checksumDocument) {
    final expected = _extractDigest(checksumDocument);
    if (expected == null) {
      throw const RepositoryChecksumException(
        'O arquivo de checksum não contém MD5, SHA-1 ou SHA-256 reconhecível.',
      );
    }

    final actual = switch (expected.length) {
      32 => md5.convert(bytes).toString(),
      40 => sha1.convert(bytes).toString(),
      64 => sha256.convert(bytes).toString(),
      _ => throw const RepositoryChecksumException(
          'Algoritmo de checksum não suportado.',
        ),
    };

    return actual.toLowerCase() == expected.toLowerCase();
  }

  String? _extractDigest(String source) {
    final normalized = const LineSplitter()
        .convert(source)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join(' ');

    final match = RegExp(
      r'(?<![0-9a-fA-F])([0-9a-fA-F]{64}|[0-9a-fA-F]{40}|[0-9a-fA-F]{32})(?![0-9a-fA-F])',
    ).firstMatch(normalized);
    return match?.group(1);
  }
}
