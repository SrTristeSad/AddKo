import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:addko/src/runtime/plugin_host.dart';

typedef PluginDependencyCaller = Future<Object?> Function(
  String targetPluginId,
  String method,
  Object? arguments,
);

/// Adds generic plugin-to-plugin calls on top of an existing host.
///
/// A plugin can call only IDs explicitly listed in its manifest dependencies.
/// No application-specific capability (torrent, manga, etc.) is introduced.
class PluginDependencyHost extends PluginHost {
  PluginDependencyHost({
    required this.inner,
    required this.manifest,
    required this.caller,
  });

  final PluginHost inner;
  final PluginManifest manifest;
  final PluginDependencyCaller caller;

  @override
  Map<String, bool> get capabilities => <String, bool>{
        ...inner.capabilities,
        'plugins': manifest.dependencies.isNotEmpty,
      };

  @override
  Future<Object?> invoke(String operation, Object? arguments) async {
    if (operation != 'plugins.call') {
      return inner.invoke(operation, arguments);
    }

    if (manifest.dependencies.isEmpty) {
      throw const PluginDependencyException(
        'Plugin não declarou dependências no manifest.',
      );
    }
    if (arguments is! Map) {
      throw const PluginDependencyException(
        'plugins.call espera um objeto de argumentos.',
      );
    }

    final id = arguments['id']?.toString().trim() ?? '';
    final method = arguments['method']?.toString().trim() ?? '';
    final payload = arguments['args'];

    if (id.isEmpty || method.isEmpty) {
      throw const PluginDependencyException(
        'plugins.call exige id e method.',
      );
    }
    if (!manifest.dependencies.contains(id)) {
      throw PluginDependencyException(
        'Plugin ${manifest.id} não declarou dependência de $id.',
      );
    }
    if (method.length > 128 ||
        !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(method)) {
      throw const PluginDependencyException('Método de serviço inválido.');
    }

    return caller(id, method, payload);
  }

  @override
  void bindEventDispatcher(PluginEventDispatcher dispatcher) {
    inner.bindEventDispatcher(dispatcher);
  }

  @override
  Future<void> close() => inner.close();
}

class PluginDependencyException implements Exception {
  const PluginDependencyException(this.message);

  final String message;

  @override
  String toString() => 'PluginDependencyException: $message';
}
