import 'dart:convert';

import 'package:addko/src/runtime/lua_host_bootstrap.dart';
import 'package:addko/src/runtime/lua_runtime.dart';
import 'package:addko/src/runtime/plugin_host.dart';

class LuaPluginSession {
  LuaPluginSession._({
    required LuaRuntime runtime,
    required PluginHost host,
  })  : _runtime = runtime,
        _host = host;

  final LuaRuntime _runtime;
  final PluginHost _host;
  bool _closed = false;

  static Future<LuaPluginSession> open({
    required String pluginRoot,
    required String dataRoot,
    required String entry,
    required Map<String, Object?> platform,
    required Map<String, Object?> locale,
    required PluginHost host,
  }) async {
    final runtime = LuaRuntime.open(pluginRoot: pluginRoot);
    final session = LuaPluginSession._(runtime: runtime, host: host);

    try {
      runtime.evaluate(luaHostBootstrap);
      final bootstrapConfig = <String, Object?>{
        'plugin_root': pluginRoot,
        'data_root': dataRoot,
        'platform': platform,
        'locale': locale,
        'capabilities': host.capabilities,
      };

      runtime.evaluate(
        'return __addko_bootstrap('
        '${_luaQuote(jsonEncode(bootstrapConfig))}'
        ')',
      );

      final module = _entryModule(entry);
      runtime.evaluate(
        'return __addko_load_plugin(${_luaQuote(module)})',
      );

      host.bindEventDispatcher(session.dispatchEvent);
      return session;
    } on Object {
      runtime.dispose();
      rethrow;
    }
  }

  Future<Object?> start() => call('start');

  Future<Object?> route(String name, [Map<String, Object?>? parameters]) {
    return call('route', <Object?>[
      name,
      parameters ?? const <String, Object?>{},
    ]);
  }

  Future<Object?> stop() => call('stop');

  Future<Object?> call(String method, [List<Object?> arguments = const []]) async {
    _ensureOpen();
    final wire = _runtime.evaluate(
      'return __addko_start_plugin_call('
      '${_luaQuote(method)}, '
      '${_luaQuote(jsonEncode(arguments))}'
      ')',
    );
    return _drive(wire);
  }

  Future<Object?> dispatchEvent(
    int callbackId,
    List<Object?> arguments,
  ) async {
    _ensureOpen();
    final wire = _runtime.evaluate(
      'return __addko_start_event('
      '$callbackId, '
      '${_luaQuote(jsonEncode(arguments))}'
      ')',
    );
    return _drive(wire);
  }

  Future<Object?> _drive(String initialWire) async {
    var wire = initialWire;

    while (true) {
      final decoded = jsonDecode(wire);
      if (decoded is! Map) {
        throw LuaPluginProtocolException(
          'Resposta do scheduler Lua não é um objeto JSON.',
        );
      }

      final state = decoded['state'];
      if (state == 'done') {
        return decoded['value'];
      }
      if (state == 'error') {
        throw LuaPluginException(
          decoded['error']?.toString() ?? 'Erro Lua sem mensagem.',
        );
      }
      if (state != 'yield') {
        throw LuaPluginProtocolException(
          'Estado desconhecido do scheduler Lua: $state',
        );
      }

      final callId = decoded['call_id'];
      final operation = decoded['op'];
      if (callId is! num || operation is! String || operation.isEmpty) {
        throw LuaPluginProtocolException(
          'Pedido de host Lua incompleto: $decoded',
        );
      }

      final Map<String, Object?> reply;
      try {
        final value = await _host.invoke(operation, decoded['args']);
        reply = <String, Object?>{
          'ok': true,
          'value': value,
        };
      } on Object catch (error) {
        reply = <String, Object?>{
          'ok': false,
          'error': error.toString(),
        };
      }

      wire = _runtime.evaluate(
        'return __addko_resume_call('
        '${callId.toInt()}, '
        '${_luaQuote(jsonEncode(reply))}'
        ')',
      );
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    try {
      _runtime.evaluate('return __addko_shutdown()');
    } on Object {
      // The runtime is being torn down anyway.
    }

    try {
      await _host.close();
    } finally {
      _runtime.dispose();
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('Sessão Lua já encerrada.');
    }
  }
}

class LuaPluginException implements Exception {
  const LuaPluginException(this.message);

  final String message;

  @override
  String toString() => 'LuaPluginException: $message';
}

class LuaPluginProtocolException implements Exception {
  const LuaPluginProtocolException(this.message);

  final String message;

  @override
  String toString() => 'LuaPluginProtocolException: $message';
}

String _entryModule(String entry) {
  if (!entry.endsWith('.lua')) {
    throw ArgumentError.value(entry, 'entry', 'Entrypoint deve terminar em .lua');
  }
  final withoutExtension = entry.substring(0, entry.length - 4);
  if (withoutExtension.isEmpty || withoutExtension.contains('..')) {
    throw ArgumentError.value(entry, 'entry', 'Entrypoint inseguro');
  }
  return withoutExtension.split('/').join('.');
}

String _luaQuote(String value) {
  final buffer = StringBuffer('"');
  for (final rune in value.runes) {
    switch (rune) {
      case 0x22:
        buffer.write(r'\"');
      case 0x5c:
        buffer.write(r'\\');
      case 0x08:
        buffer.write(r'\b');
      case 0x0c:
        buffer.write(r'\f');
      case 0x0a:
        buffer.write(r'\n');
      case 0x0d:
        buffer.write(r'\r');
      case 0x09:
        buffer.write(r'\t');
      default:
        if (rune < 0x20) {
          buffer.write('\\${rune.toRadixString(10).padLeft(3, '0')}');
        } else {
          buffer.writeCharCode(rune);
        }
    }
  }
  buffer.write('"');
  return buffer.toString();
}
