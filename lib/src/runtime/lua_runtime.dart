import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _CreateNative = Pointer<Void> Function();
typedef _CreateDart = Pointer<Void> Function();
typedef _DestroyNative = Void Function(Pointer<Void> runtime);
typedef _DestroyDart = void Function(Pointer<Void> runtime);
typedef _VersionNative = Pointer<Utf8> Function();
typedef _VersionDart = Pointer<Utf8> Function();
typedef _SetPluginRootNative = Int32 Function(
  Pointer<Void> runtime,
  Pointer<Utf8> pluginRoot,
);
typedef _SetPluginRootDart = int Function(
  Pointer<Void> runtime,
  Pointer<Utf8> pluginRoot,
);
typedef _EvalNative = Int32 Function(
  Pointer<Void> runtime,
  Pointer<Utf8> source,
  Pointer<Utf8> output,
  IntPtr outputSize,
);
typedef _EvalDart = int Function(
  Pointer<Void> runtime,
  Pointer<Utf8> source,
  Pointer<Utf8> output,
  int outputSize,
);

class LuaRuntime {
  LuaRuntime._(
    this._handle,
    this._destroy,
    this._evaluate,
    this._version,
  );

  // Plugin routes can return full catalog pages. 16 KiB was enough for the
  // original smoke test but not for a real Plugin v2 response.
  static const int _outputCapacity = 1024 * 1024;

  final Pointer<Void> _handle;
  final _DestroyDart _destroy;
  final _EvalDart _evaluate;
  final _VersionDart _version;
  bool _disposed = false;

  static LuaRuntime open({
    String? pluginRoot,
    DynamicLibrary? testLibrary,
  }) {
    if (!Platform.isAndroid && testLibrary == null) {
      throw UnsupportedError('O runtime nativo inicial suporta Android.');
    }

    // A caller-supplied library is used only by trusted Dart integration tests.
    // Lua plugins cannot provide native executable paths or shared libraries.
    final library = testLibrary ?? DynamicLibrary.open('libaddko_lua.so');
    final create = library.lookupFunction<_CreateNative, _CreateDart>(
      'addko_lua_create',
    );
    final destroy = library.lookupFunction<_DestroyNative, _DestroyDart>(
      'addko_lua_destroy',
    );
    final evaluate = library.lookupFunction<_EvalNative, _EvalDart>(
      'addko_lua_eval',
    );
    final version = library.lookupFunction<_VersionNative, _VersionDart>(
      'addko_lua_version',
    );
    final setPluginRoot =
        library.lookupFunction<_SetPluginRootNative, _SetPluginRootDart>(
      'addko_lua_set_plugin_root',
    );

    final handle = create();
    if (handle == nullptr) {
      throw StateError('Não foi possível criar o estado Lua.');
    }

    try {
      if (pluginRoot != null) {
        final rootPointer = pluginRoot.toNativeUtf8();
        try {
          final status = setPluginRoot(handle, rootPointer);
          if (status != 0) {
            throw StateError(
              'Não foi possível configurar a raiz do plugin Lua (erro $status).',
            );
          }
        } finally {
          calloc.free(rootPointer);
        }
      }

      return LuaRuntime._(handle, destroy, evaluate, version);
    } on Object {
      destroy(handle);
      rethrow;
    }
  }

  String get version {
    _ensureAlive();
    return _version().toDartString();
  }

  String evaluate(String source) {
    _ensureAlive();
    final sourcePointer = source.toNativeUtf8();
    final output = calloc<Uint8>(_outputCapacity).cast<Utf8>();
    try {
      final status = _evaluate(
        _handle,
        sourcePointer,
        output,
        _outputCapacity,
      );
      final message = output.toDartString();
      if (status != 0) {
        throw LuaException(message.isEmpty ? 'Erro Lua $status' : message);
      }
      return message;
    } finally {
      calloc.free(sourcePointer);
      calloc.free(output);
    }
  }

  void dispose() {
    if (_disposed) return;
    _destroy(_handle);
    _disposed = true;
  }

  void _ensureAlive() {
    if (_disposed) {
      throw StateError('O runtime Lua já foi encerrado.');
    }
  }
}

class LuaException implements Exception {
  const LuaException(this.message);

  final String message;

  @override
  String toString() => 'LuaException: $message';
}
