import 'package:addko/src/platform/native_engine_platform.dart';
import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:addko/src/runtime/plugin_host.dart';

typedef NativeEngineInvoker = Future<Object?> Function(
  String action,
  String engine,
);

/// Permission/manifest scoped dispatcher for APK-bundled native engines.
/// Arbitrary .so/.dll/.exe loading is deliberately unsupported.
class NativeEnginePluginHost extends PluginHost {
  NativeEnginePluginHost({
    required this.inner,
    required this.manifest,
    NativeEngineInvoker? invoker,
    bool? platformSupported,
  })  : _invoker = invoker ?? const NativeEnginePlatform().invoke,
        _platformSupported =
            platformSupported ?? const NativeEnginePlatform().supported;

  final PluginHost inner;
  final PluginManifest manifest;
  final NativeEngineInvoker _invoker;
  final bool _platformSupported;

  bool get _permitted =>
      _platformSupported &&
      manifest.permissions.contains(PluginPermission.nativeEngine) &&
      manifest.nativeEngines.isNotEmpty;

  @override
  Map<String, bool> get capabilities => <String, bool>{
        ...inner.capabilities,
        'native_engines': _permitted,
      };

  @override
  Future<Object?> invoke(String operation, Object? arguments) async {
    if (!operation.startsWith('native_engine.')) {
      return inner.invoke(operation, arguments);
    }
    if (!_permitted) {
      throw StateError('Addon sem permissão para motores nativos aprovados.');
    }
    if (arguments is! Map || arguments['engine'] is! String) {
      throw ArgumentError('Informe o ID do motor.');
    }
    final engine = arguments['engine'] as String;
    if (!manifest.nativeEngines.contains(engine)) {
      throw StateError('Motor não declarado no manifesto: $engine');
    }
    final action = operation.substring('native_engine.'.length);
    if (action != 'available' && action != 'start' &&
        action != 'stop' && action != 'status') {
      throw StateError('Operação nativa desconhecida: $action');
    }
    return _invoker(action, engine);
  }

  @override
  void bindEventDispatcher(PluginEventDispatcher dispatcher) {
    inner.bindEventDispatcher(dispatcher);
  }

  @override
  Future<void> close() => inner.close();
}
