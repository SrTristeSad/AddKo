import 'package:flutter/foundation.dart';

import '../domain/repository_source.dart';
import '../domain/repository_storage.dart';

class RepositoryRegistry extends ChangeNotifier {
  RepositoryRegistry({RepositoryStorage? storage}) : _storage = storage;

  final RepositoryStorage? _storage;
  final List<RepositorySource> _sources = [];

  bool _initialized = false;
  Future<void>? _initialization;

  List<RepositorySource> get sources => List.unmodifiable(_sources);
  bool get initialized => _initialized;

  Future<void> initialize() {
    if (_initialized) {
      return Future<void>.value();
    }
    return _initialization ??= _initializeInternal();
  }

  Future<void> _initializeInternal() async {
    try {
      final storage = _storage;
      if (storage != null) {
        final loaded = await storage.load();
        _sources
          ..clear()
          ..addAll(_deduplicated(loaded));
      }
      _initialized = true;
      notifyListeners();
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  Future<void> addUrl(String rawUrl) async {
    await initialize();

    final value = rawUrl.trim();
    if (value.isEmpty) {
      throw const FormatException('Informe a URL do repositório.');
    }

    final uri = Uri.tryParse(value);
    if (!_isHttpUri(uri)) {
      throw const FormatException(
        'Use uma URL HTTP ou HTTPS válida para o repositório.',
      );
    }

    await _addSource(RepositorySource(uri: uri!, enabled: true));
  }

  Future<void> addResolvedEndpoint({
    required Uri infoUri,
    required Uri packageBaseUri,
    Uri? checksumUri,
    String? name,
  }) async {
    await initialize();

    if (!_isHttpUri(infoUri) || !_isHttpUri(packageBaseUri)) {
      throw const FormatException(
        'O addon de repositório publicou um endpoint HTTP/HTTPS inválido.',
      );
    }
    if (checksumUri != null && !_isHttpUri(checksumUri)) {
      throw const FormatException(
        'O addon de repositório publicou um checksum HTTP/HTTPS inválido.',
      );
    }

    await _addSource(
      RepositorySource(
        uri: infoUri,
        enabled: true,
        packageBaseUri: packageBaseUri,
        checksumUri: checksumUri,
        name: name,
      ),
    );
  }

  Future<void> _addSource(RepositorySource source) async {
    if (_sources.any((existing) => existing.uri == source.uri)) {
      throw const FormatException('Este repositório já foi adicionado.');
    }

    final next = [..._sources, source];
    await _commit(next);
  }

  Future<void> remove(Uri uri) async {
    await initialize();

    final next = _sources.where((source) => source.uri != uri).toList();
    if (next.length == _sources.length) {
      return;
    }

    await _commit(next);
  }

  Future<void> setEnabled(Uri uri, bool enabled) async {
    await initialize();

    final index = _sources.indexWhere((source) => source.uri == uri);
    if (index == -1 || _sources[index].enabled == enabled) {
      return;
    }

    final next = List<RepositorySource>.of(_sources);
    next[index] = next[index].copyWith(enabled: enabled);
    await _commit(next);
  }

  Future<void> _commit(List<RepositorySource> next) async {
    final deduplicated = _deduplicated(next);
    final storage = _storage;
    if (storage != null) {
      await storage.save(List.unmodifiable(deduplicated));
    }

    _sources
      ..clear()
      ..addAll(deduplicated);
    notifyListeners();
  }

  List<RepositorySource> _deduplicated(List<RepositorySource> sources) {
    final seen = <Uri>{};
    return [
      for (final source in sources)
        if (seen.add(source.uri)) source,
    ];
  }

  bool _isHttpUri(Uri? uri) {
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }
}
