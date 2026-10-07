import 'package:flutter/foundation.dart';

import '../domain/repository_source.dart';
import '../domain/repository_storage.dart';

class RepositoryRegistry extends ChangeNotifier {
  RepositoryRegistry({RepositoryStorage? storage}) : _storage = storage;

  final RepositoryStorage? _storage;
  final List<RepositorySource> _sources = [];

  bool _initialized = false;

  List<RepositorySource> get sources => List.unmodifiable(_sources);
  bool get initialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    final storage = _storage;
    if (storage != null) {
      final loaded = await storage.load();
      _sources
        ..clear()
        ..addAll(_deduplicated(loaded));
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> addUrl(String rawUrl) async {
    final value = rawUrl.trim();
    if (value.isEmpty) {
      throw const FormatException('Informe a URL do repositório.');
    }

    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const FormatException(
        'Use uma URL HTTP ou HTTPS válida para o repositório.',
      );
    }

    if (_sources.any((source) => source.uri == uri)) {
      throw const FormatException('Este repositório já foi adicionado.');
    }

    _sources.add(RepositorySource(uri: uri, enabled: true));
    await _persist();
    notifyListeners();
  }

  Future<void> remove(Uri uri) async {
    final oldLength = _sources.length;
    _sources.removeWhere((source) => source.uri == uri);
    if (_sources.length == oldLength) {
      return;
    }

    await _persist();
    notifyListeners();
  }

  Future<void> setEnabled(Uri uri, bool enabled) async {
    final index = _sources.indexWhere((source) => source.uri == uri);
    if (index == -1 || _sources[index].enabled == enabled) {
      return;
    }

    _sources[index] = _sources[index].copyWith(enabled: enabled);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final storage = _storage;
    if (storage == null) {
      return;
    }
    await storage.save(sources);
  }

  List<RepositorySource> _deduplicated(List<RepositorySource> sources) {
    final seen = <Uri>{};
    return [
      for (final source in sources)
        if (seen.add(source.uri)) source,
    ];
  }
}
