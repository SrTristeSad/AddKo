import 'package:flutter/foundation.dart';

import '../domain/repository_source.dart';

class RepositoryRegistry extends ChangeNotifier {
  final List<RepositorySource> _sources = [];

  List<RepositorySource> get sources => List.unmodifiable(_sources);

  void addUrl(String rawUrl) {
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
    notifyListeners();
  }

  void remove(Uri uri) {
    _sources.removeWhere((source) => source.uri == uri);
    notifyListeners();
  }

  void setEnabled(Uri uri, bool enabled) {
    final index = _sources.indexWhere((source) => source.uri == uri);
    if (index == -1) {
      return;
    }

    _sources[index] = _sources[index].copyWith(enabled: enabled);
    notifyListeners();
  }
}
