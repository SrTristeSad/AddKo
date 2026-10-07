import 'dart:convert';

import 'package:addko/core/runtime/legacy/kodi_json_rpc_compat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const compat = KodiJsonRpcCompat();

  test('responds to JSONRPC.Ping', () {
    final response = jsonDecode(
      compat.handle('{"jsonrpc":"2.0","id":7,"method":"JSONRPC.Ping"}'),
    ) as Map<String, Object?>;

    expect(response['id'], 7);
    expect(response['result'], 'pong');
  });

  test('filters Application.GetProperties', () {
    final response = jsonDecode(
      compat.handle(
        '{"jsonrpc":"2.0","id":1,"method":"Application.GetProperties",'
        '"params":{"properties":["name","version"]}}',
      ),
    ) as Map<String, Object?>;
    final result = response['result'] as Map<String, dynamic>;

    expect(result['name'], 'AddKo');
    expect(result['version'], isA<Map>());
    expect(result.containsKey('volume'), isFalse);
  });

  test('returns Kodi-compatible method-not-found errors', () {
    final response = jsonDecode(
      compat.handle('{"jsonrpc":"2.0","id":9,"method":"Nope.Unknown"}'),
    ) as Map<String, Object?>;
    final error = response['error'] as Map<String, dynamic>;

    expect(error['code'], -32601);
  });

  test('returns parse errors for invalid json', () {
    final response = jsonDecode(compat.handle('{')) as Map<String, Object?>;
    final error = response['error'] as Map<String, dynamic>;

    expect(error['code'], -32700);
  });
}
