import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../domain/repository_catalog.dart';
import '../domain/repository_descriptor.dart';
import '../domain/repository_source.dart';
import 'repository_checksum_verifier.dart';
import 'repository_descriptor_parser.dart';
import 'repository_index_parser.dart';

class RepositorySyncException implements Exception {
  const RepositorySyncException(this.message);

  final String message;

  @override
  String toString() => 'RepositorySyncException: $message';
}

class RepositoryClient {
  RepositoryClient({
    http.Client? client,
    this.descriptorParser = const RepositoryDescriptorParser(),
    this.indexParser = const RepositoryIndexParser(),
    this.checksumVerifier = const RepositoryChecksumVerifier(),
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  static const int _maxIndexBytes = 24 * 1024 * 1024;
  static const int _maxChecksumBytes = 64 * 1024;

  final http.Client _client;
  final bool _ownsClient;
  final RepositoryDescriptorParser descriptorParser;
  final RepositoryIndexParser indexParser;
  final RepositoryChecksumVerifier checksumVerifier;

  Future<RepositoryCatalog> synchronize(RepositorySource source) async {
    final candidates = _candidateUris(source.uri);
    Object? lastError;

    for (final candidate in candidates) {
      try {
        final document = await _downloadXml(candidate);
        final xml = document.xml;
        final parsed = XmlDocument.parse(xml);
        final rootName = parsed.rootElement.name.local;

        if (rootName == 'addons') {
          final result = indexParser.parse(xml);
          return RepositoryCatalog(
            repositoryName: source.displayName,
            sourceUri: source.uri,
            addons: result.addons,
            fetchedAt: DateTime.now().toUtc(),
            skippedAddons: result.skippedAddons,
          );
        }

        if (rootName == 'addon') {
          final descriptor = descriptorParser.parse(xml);
          return await _loadDescriptor(source, descriptor);
        }

        lastError = RepositorySyncException(
          'XML em ${candidate.toString()} não é um addon de repositório nem um índice addons.xml.',
        );
      } on Object catch (error) {
        lastError = error;
      }
    }

    throw RepositorySyncException(
      'Não foi possível sincronizar ${source.uri}. ${lastError ?? ''}'.trim(),
    );
  }

  Future<RepositoryCatalog> _loadDescriptor(
    RepositorySource source,
    RepositoryDescriptor descriptor,
  ) async {
    Object? lastError;

    for (final endpoint in descriptor.endpoints) {
      try {
        final document = await _downloadXml(endpoint.infoUri);
        await _validateChecksum(endpoint, document);
        final result = indexParser.parse(
          document.xml,
          packageBaseUri: endpoint.dataUri,
        );

        return RepositoryCatalog(
          repositoryName: descriptor.name,
          sourceUri: source.uri,
          packageBaseUri: endpoint.dataUri,
          addons: result.addons,
          fetchedAt: DateTime.now().toUtc(),
          skippedAddons: result.skippedAddons,
        );
      } on Object catch (error) {
        lastError = error;
      }
    }

    throw RepositorySyncException(
      'O repositório ${descriptor.name} não possui um endpoint utilizável. ${lastError ?? ''}'.trim(),
    );
  }

  Future<void> _validateChecksum(
    RepositoryEndpoint endpoint,
    _DownloadedXml document,
  ) async {
    final checksumUri = endpoint.checksumUri;
    if (checksumUri == null) {
      return;
    }

    final checksum = await _downloadChecksum(checksumUri);
    final rawMatches = checksumVerifier.matches(document.rawBytes, checksum);
    final decodedMatches = rawMatches
        ? true
        : checksumVerifier.matches(document.xmlBytes, checksum);

    if (!decodedMatches) {
      throw RepositorySyncException(
        'Checksum inválido para ${endpoint.infoUri}. O índice foi rejeitado.',
      );
    }
  }

  Future<_DownloadedXml> _downloadXml(Uri uri) async {
    final response = await _client.get(
      uri,
      headers: const {
        'Accept': 'application/xml,text/xml,application/gzip,*/*',
        'User-Agent': 'AddKo/0.1.0',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RepositorySyncException(
        'HTTP ${response.statusCode} ao acessar $uri.',
      );
    }

    if (response.bodyBytes.length > _maxIndexBytes) {
      throw const RepositorySyncException(
        'O índice do repositório ultrapassa o limite de 24 MB.',
      );
    }

    final rawBytes = List<int>.unmodifiable(response.bodyBytes);
    List<int> xmlBytes = rawBytes;
    if (_looksLikeGzip(xmlBytes)) {
      try {
        xmlBytes = gzip.decode(xmlBytes);
      } on Object catch (error) {
        throw RepositorySyncException('Falha ao descompactar GZip: $error');
      }
    }

    try {
      final xml = utf8.decode(xmlBytes);
      return _DownloadedXml(
        xml: xml,
        rawBytes: rawBytes,
        xmlBytes: List<int>.unmodifiable(xmlBytes),
      );
    } on FormatException catch (error) {
      throw RepositorySyncException('O XML não está em UTF-8 válido: $error');
    }
  }

  Future<String> _downloadChecksum(Uri uri) async {
    final response = await _client.get(
      uri,
      headers: const {
        'Accept': 'text/plain,*/*',
        'User-Agent': 'AddKo/0.1.0',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RepositorySyncException(
        'HTTP ${response.statusCode} ao acessar checksum $uri.',
      );
    }
    if (response.bodyBytes.length > _maxChecksumBytes) {
      throw const RepositorySyncException(
        'O arquivo de checksum ultrapassa o limite permitido.',
      );
    }

    try {
      return utf8.decode(response.bodyBytes);
    } on FormatException catch (error) {
      throw RepositorySyncException('Checksum não está em UTF-8 válido: $error');
    }
  }

  List<Uri> _candidateUris(Uri source) {
    final result = <Uri>[];

    void add(Uri candidate) {
      if (!result.contains(candidate)) {
        result.add(candidate);
      }
    }

    add(source);

    final directory = source.path.endsWith('/')
        ? source
        : source.replace(path: '${source.path}/');
    add(directory.resolve('addon.xml'));
    add(directory.resolve('addons.xml'));
    add(directory.resolve('addons.xml.gz'));

    return result;
  }

  bool _looksLikeGzip(List<int> bytes) {
    return bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

class _DownloadedXml {
  const _DownloadedXml({
    required this.xml,
    required this.rawBytes,
    required this.xmlBytes,
  });

  final String xml;
  final List<int> rawBytes;
  final List<int> xmlBytes;
}
