import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../../addons/domain/kodi_version.dart';
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
  static const int _maxHtmlBytes = 4 * 1024 * 1024;
  static const int _maxRepositoryZipBytes = 32 * 1024 * 1024;
  static const int _maxFileSourcePages = 12;
  static const Duration _requestTimeout = Duration(seconds: 12);

  static final KodiVersion _hostKodiVersion = KodiVersion('21.0.0');

  final http.Client _client;
  final bool _ownsClient;
  final RepositoryDescriptorParser descriptorParser;
  final RepositoryIndexParser indexParser;
  final RepositoryChecksumVerifier checksumVerifier;

  Future<RepositoryCatalog> synchronize(RepositorySource source) async {
    if (source.hasResolvedEndpoint) {
      return _loadResolvedSource(source);
    }

    RepositoryCatalog? emptyCatalog;
    Object? lastError;

    for (final candidate in _candidateUris(source.uri)) {
      try {
        final document = await _downloadXml(candidate);
        final xml = document.xml;
        final parsed = XmlDocument.parse(xml);
        final rootName = parsed.rootElement.name.local;

        if (rootName == 'addons') {
          final packageBaseUri = _directoryUri(candidate);
          final result = indexParser.parse(
            xml,
            packageBaseUri: packageBaseUri,
          );
          final catalog = RepositoryCatalog(
            repositoryName: source.displayName,
            sourceUri: source.uri,
            packageBaseUri: packageBaseUri,
            addons: result.addons,
            fetchedAt: DateTime.now().toUtc(),
            skippedAddons: result.skippedAddons,
          );

          if (catalog.addons.isNotEmpty || _looksLikeDirectXml(source.uri)) {
            return catalog;
          }
          emptyCatalog = catalog;
          continue;
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

    if (!_looksLikeDirectXml(source.uri)) {
      try {
        final descriptor = await _discoverRepositoryDescriptorFromFileSource(
          source.uri,
        );
        if (descriptor != null) {
          return _loadDescriptor(source, descriptor);
        }
      } on Object catch (error) {
        lastError = error;
      }
    }

    if (emptyCatalog != null) {
      return emptyCatalog;
    }

    throw RepositorySyncException(
      'Não foi possível sincronizar ${source.uri}. ${lastError ?? ''}'.trim(),
    );
  }

  Future<RepositoryCatalog> _loadResolvedSource(
    RepositorySource source,
  ) async {
    final document = await _downloadXml(source.uri);
    final checksumUri = source.checksumUri;
    if (checksumUri != null) {
      await _validateChecksumUri(
        checksumUri: checksumUri,
        infoUri: source.uri,
        document: document,
      );
    }

    final packageBaseUri = source.packageBaseUri!;
    final result = indexParser.parse(
      document.xml,
      packageBaseUri: packageBaseUri,
    );
    return RepositoryCatalog(
      repositoryName: source.displayName,
      sourceUri: source.uri,
      packageBaseUri: packageBaseUri,
      addons: result.addons,
      fetchedAt: DateTime.now().toUtc(),
      skippedAddons: result.skippedAddons,
    );
  }

  Future<RepositoryCatalog> _loadDescriptor(
    RepositorySource source,
    RepositoryDescriptor descriptor,
  ) async {
    final compatibleEndpoints = descriptor.endpoints
        .where(_isEndpointCompatible)
        .toList(growable: false);

    if (compatibleEndpoints.isEmpty) {
      throw RepositorySyncException(
        'O repositório ${descriptor.name} não possui endpoints compatíveis com Kodi 21/Python 3.',
      );
    }

    final selected = <String, RepositoryAddonEntry>{};
    var skippedAddons = 0;
    var successfulEndpoints = 0;
    Object? lastError;

    for (final endpoint in compatibleEndpoints) {
      try {
        final document = await _downloadXml(endpoint.infoUri);
        await _validateChecksum(endpoint, document);
        final result = indexParser.parse(
          document.xml,
          packageBaseUri: endpoint.dataUri,
        );

        successfulEndpoints += 1;
        skippedAddons += result.skippedAddons;
        for (final addon in result.addons) {
          final existing = selected[addon.manifest.id];
          if (existing == null ||
              KodiVersion(addon.manifest.version).compareTo(
                    KodiVersion(existing.manifest.version),
                  ) >
                  0) {
            selected[addon.manifest.id] = addon;
          }
        }
      } on Object catch (error) {
        lastError = error;
      }
    }

    if (successfulEndpoints == 0) {
      throw RepositorySyncException(
        'O repositório ${descriptor.name} não possui um endpoint utilizável. ${lastError ?? ''}'.trim(),
      );
    }

    final addons = selected.values.toList(growable: false)
      ..sort(
        (left, right) => left.manifest.name.toLowerCase().compareTo(
              right.manifest.name.toLowerCase(),
            ),
      );

    return RepositoryCatalog(
      repositoryName: descriptor.name,
      sourceUri: source.uri,
      packageBaseUri: compatibleEndpoints.length == 1
          ? compatibleEndpoints.first.dataUri
          : null,
      addons: List.unmodifiable(addons),
      fetchedAt: DateTime.now().toUtc(),
      skippedAddons: skippedAddons,
    );
  }

  bool _isEndpointCompatible(RepositoryEndpoint endpoint) {
    final minimum = endpoint.minimumVersion?.trim();
    if (minimum != null &&
        minimum.isNotEmpty &&
        _hostKodiVersion.compareTo(KodiVersion(minimum)) < 0) {
      return false;
    }

    final maximum = endpoint.maximumVersion?.trim();
    if (maximum != null &&
        maximum.isNotEmpty &&
        _hostKodiVersion.compareTo(KodiVersion(maximum)) > 0) {
      return false;
    }

    return true;
  }

  Future<RepositoryDescriptor?> _discoverRepositoryDescriptorFromFileSource(
    Uri sourceUri,
  ) async {
    final queue = <Uri>[_directoryUri(sourceUri)];
    final visited = <Uri>{};
    var pagesRead = 0;

    while (queue.isNotEmpty && pagesRead < _maxFileSourcePages) {
      final pageUri = queue.removeAt(0);
      if (!visited.add(pageUri)) {
        continue;
      }
      pagesRead += 1;

      final page = await _downloadHtml(pageUri);
      final links = _extractLinks(pageUri, page);
      final repositoryZips = links
          .where(_isRepositoryZipCandidate)
          .toList(growable: false);

      for (final zipUri in repositoryZips.reversed) {
        try {
          final descriptor = await _descriptorFromRepositoryZip(zipUri);
          if (descriptor != null) {
            return descriptor;
          }
        } on Object {
          // A file source can contain unrelated or old ZIPs. Keep looking.
        }
      }

      for (final link in links) {
        if (queue.length + visited.length >= _maxFileSourcePages) {
          break;
        }
        if (_isBrowsableFileSourcePage(sourceUri, link) &&
            !visited.contains(link) &&
            !queue.contains(link)) {
          queue.add(link);
        }
      }
    }

    return null;
  }

  Future<RepositoryDescriptor?> _descriptorFromRepositoryZip(Uri uri) async {
    late http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: const {
              'Accept': 'application/zip,application/octet-stream,*/*',
              'User-Agent': 'AddKo/0.1.0',
            },
          )
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw RepositorySyncException(
        'Tempo esgotado ao inspecionar o pacote de repositório $uri.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RepositorySyncException(
        'HTTP ${response.statusCode} ao inspecionar $uri.',
      );
    }
    if (response.bodyBytes.length > _maxRepositoryZipBytes) {
      throw const RepositorySyncException(
        'O pacote de repositório encontrado ultrapassa 32 MB.',
      );
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(response.bodyBytes, verify: true);
    } on Object catch (error) {
      throw RepositorySyncException('ZIP de repositório inválido: $error');
    }

    final manifests = archive.files.where((file) {
      if (!file.isFile) {
        return false;
      }
      final normalized = file.name.replaceAll('\\', '/').toLowerCase();
      return normalized == 'addon.xml' || normalized.endsWith('/addon.xml');
    }).toList(growable: false)
      ..sort((left, right) {
        final leftDepth = left.name.split('/').length;
        final rightDepth = right.name.split('/').length;
        return leftDepth.compareTo(rightDepth);
      });

    for (final file in manifests) {
      try {
        final content = List<int>.from(file.content as List<int>);
        final xml = utf8.decode(content);
        return descriptorParser.parse(xml);
      } on Object {
        // The ZIP may include non-repository addon.xml files. Try the next one.
      }
    }

    return null;
  }

  Future<String> _downloadHtml(Uri uri) async {
    late http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: const {
              'Accept': 'text/html,application/xhtml+xml,*/*',
              'User-Agent': 'AddKo/0.1.0',
            },
          )
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw RepositorySyncException(
        'Tempo esgotado ao ler a fonte Kodi $uri.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RepositorySyncException(
        'HTTP ${response.statusCode} ao ler a fonte Kodi $uri.',
      );
    }
    if (response.bodyBytes.length > _maxHtmlBytes) {
      throw const RepositorySyncException(
        'A página da fonte Kodi ultrapassa 4 MB.',
      );
    }

    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  List<Uri> _extractLinks(Uri pageUri, String html) {
    final links = <Uri>[];
    final seen = <Uri>{};
    final expression = RegExp(
      r'''href\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    );

    for (final match in expression.allMatches(html)) {
      final raw = match.group(1)?.trim();
      if (raw == null ||
          raw.isEmpty ||
          raw.startsWith('#') ||
          raw.toLowerCase().startsWith('javascript:') ||
          raw.toLowerCase().startsWith('mailto:')) {
        continue;
      }

      final resolved = pageUri.resolve(raw);
      if ((resolved.scheme != 'http' && resolved.scheme != 'https') ||
          !seen.add(resolved)) {
        continue;
      }
      links.add(resolved);
    }

    return links;
  }

  bool _isRepositoryZipCandidate(Uri uri) {
    final path = uri.path.toLowerCase();
    if (!path.endsWith('.zip')) {
      return false;
    }
    final name = uri.pathSegments.isEmpty
        ? path
        : uri.pathSegments.last.toLowerCase();
    return name.contains('repository') ||
        name.contains('.repo') ||
        name.startsWith('repo') ||
        name.contains('-repo');
  }

  bool _isBrowsableFileSourcePage(Uri root, Uri candidate) {
    if (candidate.host != root.host || candidate.scheme != root.scheme) {
      return false;
    }

    final path = candidate.path.toLowerCase();
    if (path.endsWith('.zip') ||
        path.endsWith('.xml') ||
        path.endsWith('.gz') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.webp')) {
      return false;
    }

    return path.endsWith('/') ||
        path.endsWith('/index.html') ||
        path.endsWith('index.html');
  }

  Future<void> _validateChecksum(
    RepositoryEndpoint endpoint,
    _DownloadedXml document,
  ) async {
    final checksumUri = endpoint.checksumUri;
    if (checksumUri == null) {
      return;
    }
    await _validateChecksumUri(
      checksumUri: checksumUri,
      infoUri: endpoint.infoUri,
      document: document,
    );
  }

  Future<void> _validateChecksumUri({
    required Uri checksumUri,
    required Uri infoUri,
    required _DownloadedXml document,
  }) async {
    final checksum = await _downloadChecksum(checksumUri);
    final rawMatches = checksumVerifier.matches(document.rawBytes, checksum);
    final decodedMatches = rawMatches
        ? true
        : checksumVerifier.matches(document.xmlBytes, checksum);

    if (!decodedMatches) {
      throw RepositorySyncException(
        'Checksum inválido para $infoUri. O índice foi rejeitado.',
      );
    }
  }

  Future<_DownloadedXml> _downloadXml(Uri uri) async {
    late http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: const {
              'Accept': 'application/xml,text/xml,application/gzip,*/*',
              'User-Agent': 'AddKo/0.1.0',
            },
          )
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw RepositorySyncException(
        'Tempo esgotado ao acessar $uri (${_requestTimeout.inSeconds}s).',
      );
    }

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
    late http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: const {
              'Accept': 'text/plain,*/*',
              'User-Agent': 'AddKo/0.1.0',
            },
          )
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw RepositorySyncException(
        'Tempo esgotado ao acessar checksum $uri (${_requestTimeout.inSeconds}s).',
      );
    }

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

    if (_looksLikeDirectXml(source)) {
      return result;
    }

    final directory = _directoryUri(source);
    add(directory.resolve('addon.xml'));
    add(directory.resolve('addons.xml'));
    add(directory.resolve('addons.xml.gz'));

    return result;
  }

  bool _looksLikeDirectXml(Uri source) {
    final path = source.path.toLowerCase();
    return path.endsWith('.xml') ||
        path.endsWith('.xml.gz') ||
        path.endsWith('.gz');
  }

  Uri _directoryUri(Uri uri) {
    if (uri.path.endsWith('/')) {
      return uri;
    }
    return uri.resolve('.');
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
