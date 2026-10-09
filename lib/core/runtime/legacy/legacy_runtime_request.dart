import 'dart:convert';

import 'legacy_runtime_collector.dart';

typedef LegacyRuntimeRequestHandler = Future<Object?> Function(
  LegacyRuntimeRequest request,
);

class LegacyRuntimeRequest {
  const LegacyRuntimeRequest({
    required this.id,
    required this.method,
    required this.params,
    this.defaultValue,
  });

  final int id;
  final String method;
  final Map<String, Object?> params;
  final Object? defaultValue;

  static LegacyRuntimeRequest? tryParse(String line) {
    if (!line.startsWith(LegacyRuntimeCollector.protocolPrefix)) {
      return null;
    }

    final payload = line.substring(LegacyRuntimeCollector.protocolPrefix.length);
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      return null;
    }

    if (decoded is! Map) {
      return null;
    }
    final event = Map<String, Object?>.from(decoded);
    if (event['expects_response'] != true || event['request_id'] is! num) {
      return null;
    }

    final rawParams = event['params'];
    return LegacyRuntimeRequest(
      id: (event['request_id']! as num).toInt(),
      method: event['method']?.toString() ?? '',
      params: rawParams is Map
          ? Map<String, Object?>.from(rawParams)
          : const <String, Object?>{},
      defaultValue: event['default'],
    );
  }
}
