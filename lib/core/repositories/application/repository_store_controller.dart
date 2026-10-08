import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/repository_catalog.dart';
import '../domain/repository_source.dart';
import '../infrastructure/repository_client.dart';

class RepositoryStoreController extends ChangeNotifier {
  RepositoryStoreController({RepositoryClient? client})
      : _client = client ?? RepositoryClient(),
        _ownsClient = client == null;

  static const Duration _syncTimeout = Duration(seconds: 30);

  final RepositoryClient _client;
  final bool _ownsClient;
  final Map<Uri, RepositorySyncState> _states = {};

  Iterable<RepositoryCatalog> get catalogs sync* {
    for (final state in _states.values) {
      final catalog = state.catalog;
      if (catalog != null) {
        yield catalog;
      }
    }
  }

  RepositorySyncState stateFor(Uri uri) {
    return _states[uri] ?? const RepositorySyncState.idle();
  }

  Future<void> synchronize(RepositorySource source) async {
    if (!source.enabled ||
        _states[source.uri]?.status == RepositorySyncStatus.syncing) {
      return;
    }

    _states[source.uri] = RepositorySyncState.syncing(
      previousCatalog: _states[source.uri]?.catalog,
    );
    notifyListeners();

    try {
      final catalog = await _client
          .synchronize(source)
          .timeout(_syncTimeout);
      _states[source.uri] = RepositorySyncState.ready(catalog);
    } on TimeoutException {
      _states[source.uri] = RepositorySyncState.failed(
        'A sincronização excedeu ${_syncTimeout.inSeconds} segundos. Verifique a URL ou a conexão.',
        previousCatalog: _states[source.uri]?.catalog,
      );
    } on Object catch (error) {
      _states[source.uri] = RepositorySyncState.failed(
        error.toString(),
        previousCatalog: _states[source.uri]?.catalog,
      );
    }

    notifyListeners();
  }

  Future<void> synchronizeAll(Iterable<RepositorySource> sources) async {
    await Future.wait([
      for (final source in sources)
        if (source.enabled) synchronize(source),
    ]);
  }

  void forget(Uri uri) {
    if (_states.remove(uri) != null) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
    super.dispose();
  }
}

enum RepositorySyncStatus {
  idle,
  syncing,
  ready,
  failed,
}

class RepositorySyncState {
  const RepositorySyncState._({
    required this.status,
    this.catalog,
    this.errorMessage,
  });

  const RepositorySyncState.idle()
      : this._(status: RepositorySyncStatus.idle);

  factory RepositorySyncState.syncing({RepositoryCatalog? previousCatalog}) {
    return RepositorySyncState._(
      status: RepositorySyncStatus.syncing,
      catalog: previousCatalog,
    );
  }

  factory RepositorySyncState.ready(RepositoryCatalog catalog) {
    return RepositorySyncState._(
      status: RepositorySyncStatus.ready,
      catalog: catalog,
    );
  }

  factory RepositorySyncState.failed(
    String errorMessage, {
    RepositoryCatalog? previousCatalog,
  }) {
    return RepositorySyncState._(
      status: RepositorySyncStatus.failed,
      catalog: previousCatalog,
      errorMessage: errorMessage,
    );
  }

  final RepositorySyncStatus status;
  final RepositoryCatalog? catalog;
  final String? errorMessage;
}
