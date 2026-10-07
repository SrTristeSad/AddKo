import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../domain/repository_catalog.dart';
import '../domain/repository_descriptor.dart';
import '../domain/repository_source.dart';
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
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  static const int _maxIndexBytes = 24 * 1024 * 1024;

  final http.Client _client;
  final bool _ownsClient;
  final RepositoryDescriptorParser descriptorParser;
  final RepositoryIndexParser indexParser;

  Future<RepositoryCatalog> synchronize(RepositorySource source) async {
    final candidates = _candidateUris(source.uri);
    Object? lastError;

    for (final candidate in candidates) {
      try {
        final xml = await _downloadXml(candidate);
        final document = XmlDocument.parse(xml);
        final rootName = document.rootElement.name.local;

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
          return _loadDescriptor(source, descriptor);
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
        final xml = await _downloadXml(endpoint.infoUri);
        final result = indexParser.parse(
          xml,
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

  Future<String> _downloadXml(Uri uri) async {
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

    var bytes = response.bodyBytes;
    if (_looksLikeGzip(bytes)) {
      try {
        bytes = gzip.decode(bytes);
      } on Object catch (error) {
        throw RepositorySyncException('Falha ao descompactar GZip: $error');
      }
    }

    try {
      return utf8.decode(bytes);
    } on FormatException catch (error) {
      throw RepositorySyncException('O XML não está em UTF-8 válido: $error');
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
