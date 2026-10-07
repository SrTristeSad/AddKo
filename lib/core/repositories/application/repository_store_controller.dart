import 'package:flutter/foundation.dart';

import '../domain/repository_catalog.dart';
import '../domain/repository_source.dart';
import '../infrastructure/repository_client.dart';

class RepositoryStoreController extends ChangeNotifier {
  RepositoryStoreController({RepositoryClient? client})
      : _client = client ?? RepositoryClient(),
        _ownsClient = client == null;

  final RepositoryClient _client;
  final bool _ownsClient;
  final Map<Uri, RepositorySyncState> _states = {};

  RepositorySyncState stateFor(Uri uri) {
    return _states[uri] ?? const RepositorySyncState.idle();
  }

  Future<void> synchronize(RepositorySource source) async {
    if (!source.enabled) {
      return;
    }

    _states[source.uri] = RepositorySyncState.syncing(
      previousCatalog: _states[source.uri]?.catalog,
    );
    notifyListeners();

    try {
      final catalog = await _client.synchronize(source);
      _states[source.uri] = RepositorySyncState.ready(catalog);
    } on Object catch (error) {
      _states[source.uri] = RepositorySyncState.failed(
        error.toString(),
        previousCatalog: _states[source.uri]?.catalog,
      );
    }

    notifyListeners();
  }

  Future<void> synchronizeAll(Iterable<RepositorySource> sources) async {
    for (final source in sources) {
      if (source.enabled) {
        await synchronize(source);
      }
    }
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
