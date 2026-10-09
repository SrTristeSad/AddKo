import 'dart:convert';

class KodiJsonRpcCompat {
  const KodiJsonRpcCompat();

  String handle(String rawRequest) {
    Object? decoded;
    try {
      decoded = jsonDecode(rawRequest);
    } on FormatException {
      return _error(null, -32700, 'Parse error');
    }

    if (decoded is List) {
      if (decoded.isEmpty) {
        return _error(null, -32600, 'Invalid Request');
      }
      final responses = decoded
          .whereType<Map>()
          .map((request) => _handleRequest(Map<String, Object?>.from(request)))
          .whereType<Map<String, Object?>>()
          .toList(growable: false);
      return jsonEncode(responses);
    }

    if (decoded is! Map) {
      return _error(null, -32600, 'Invalid Request');
    }

    return jsonEncode(
      _handleRequest(Map<String, Object?>.from(decoded)) ?? const {},
    );
  }

  Map<String, Object?>? _handleRequest(Map<String, Object?> request) {
    final id = request['id'];
    final isNotification = !request.containsKey('id');
    final method = request['method']?.toString();
    if (request['jsonrpc'] != '2.0' || method == null || method.isEmpty) {
      return _errorMap(id, -32600, 'Invalid Request');
    }

    final result = switch (method) {
      'JSONRPC.Ping' => 'pong',
      'JSONRPC.Version' => {
          'version': {
            'major': 13,
            'minor': 5,
            'patch': 0,
          },
        },
      'Application.GetProperties' => _applicationProperties(request['params']),
      'GUI.GetProperties' => _guiProperties(request['params']),
      'Player.GetActivePlayers' => const <Object?>[],
      'Files.GetSources' => {
          'sources': const <Object?>[],
          'limits': {'start': 0, 'end': 0, 'total': 0},
        },
      _ => null,
    };

    if (isNotification) {
      return null;
    }
    if (result == null) {
      return _errorMap(id, -32601, 'Method not found');
    }
    return {'jsonrpc': '2.0', 'id': id, 'result': result};
  }

  Map<String, Object?> _applicationProperties(Object? params) {
    final requested = _requestedProperties(params);
    final available = <String, Object?>{
      'name': 'AddKo',
      'version': {
        'major': 0,
        'minor': 1,
        'revision': '0',
        'tag': 'prealpha',
      },
      'volume': 100,
      'muted': false,
      'language': 'resource.language.en_gb',
    };
    return _select(available, requested);
  }

  Map<String, Object?> _guiProperties(Object? params) {
    final requested = _requestedProperties(params);
    final available = <String, Object?>{
      'fullscreen': true,
      'currentwindow': {'id': 10000, 'label': 'AddKo'},
      'currentcontrol': {'label': ''},
      'skin': {'id': 'skin.addko', 'name': 'AddKo'},
    };
    return _select(available, requested);
  }

  List<String> _requestedProperties(Object? params) {
    if (params is! Map) {
      return const [];
    }
    final value = params['properties'];
    if (value is! List) {
      return const [];
    }
    return value.map((entry) => entry.toString()).toList(growable: false);
  }

  Map<String, Object?> _select(
    Map<String, Object?> available,
    List<String> requested,
  ) {
    if (requested.isEmpty) {
      return available;
    }
    return {
      for (final name in requested)
        if (available.containsKey(name)) name: available[name],
    };
  }

  String _error(Object? id, int code, String message) {
    return jsonEncode(_errorMap(id, code, message));
  }

  Map<String, Object?> _errorMap(Object? id, int code, String message) {
    return {
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': code, 'message': message},
    };
  }
}
