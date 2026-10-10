import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/kodi_system_repository.dart';
import '../domain/repository_catalog.dart';
import '../domain/repository_source.dart';
import '../infrastructure/repository_client.dart';

class RepositoryStoreController extends ChangeNotifier {
  RepositoryStoreController({RepositoryClient? client})
      : _client = client ?? RepositoryClient(),
        _ownsClient = client == null;

  static const Duration _syncTimeout = Duration(seconds: 45);

  final RepositoryClient _client;
  final bool _ownsClient;
  final Map<Uri, RepositorySyncState> _states = {};
  final Map<Uri, Future<void>> _inflight = {};
  bool _disposed = false;

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

  Future<void> ensureKodiSystemCatalog() async {
    if (_disposed) return;
    final source = KodiSystemRepository.omega;
    final state = stateFor(source.uri);
    if (state.status == RepositorySyncStatus.ready && state.catalog != null) {
      return;
    }
    await synchronize(source);
  }

  Future<void> synchronize(RepositorySource source) {
    if (_disposed || !source.enabled) {
      return Future<void>.value();
    }

    final active = _inflight[source.uri];
    if (active != null) {
      return active;
    }

    final operation = _synchronizeInternal(source);
    _inflight[source.uri] = operation;
    return operation.whenComplete(() {
      _inflight.remove(source.uri);
    });
  }

  Future<void> _synchronizeInternal(RepositorySource source) async {
    if (_disposed) return;
    _states[source.uri] = RepositorySyncState.syncing(
      previousCatalog: _states[source.uri]?.catalog,
    );
    _notifySafely();

    try {
      final catalog = await _client.synchronize(source).timeout(_syncTimeout);
      if (_disposed) return;
      _states[source.uri] = RepositorySyncState.ready(catalog);
    } on TimeoutException {
      if (_disposed) return;
      _states[source.uri] = RepositorySyncState.failed(
        'A sincronização excedeu ${_syncTimeout.inSeconds} segundos. Verifique a URL ou a conexão.',
        previousCatalog: _states[source.uri]?.catalog,
      );
    } on Object catch (error) {
      if (_disposed) return;
      _states[source.uri] = RepositorySyncState.failed(
        error.toString(),
        previousCatalog: _states[source.uri]?.catalog,
      );
    }

    _notifySafely();
  }

  Future<void> synchronizeAll(Iterable<RepositorySource> sources) async {
    if (_disposed) return;
    await Future.wait([
      for (final source in sources)
        if (source.enabled) synchronize(source),
    ]);
  }

  void forget(Uri uri) {
    if (_disposed) return;
    if (_states.remove(uri) != null) {
      _notifySafely();
    }
  }

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_ownsClient) {
      final pending = List<Future<void>>.of(_inflight.values);
      if (pending.isEmpty) {
        _client.close();
      } else {
        unawaited(
          Future.wait(pending.map((future) => future.catchError((Object _) {})))
              .whenComplete(_client.close),
        );
      }
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
