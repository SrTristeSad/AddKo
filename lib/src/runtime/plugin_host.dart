typedef PluginEventDispatcher = Future<Object?> Function(
  int callbackId,
  List<Object?> arguments,
);

/// Generic services exposed by AddKo to a Lua plugin.
///
/// Implementations are intentionally unaware of Elementum, torrents or any
/// other plugin-specific protocol. A host operation is a versioned wire-level
/// request such as `http.request`, `fs.exists` or `player.play`.
abstract class PluginHost {
  /// Capabilities actually available in this host implementation.
  ///
  /// Lua code can use this to fail early instead of discovering an unsupported
  /// operation in the middle of a workflow.
  Map<String, bool> get capabilities;

  Future<Object?> invoke(String operation, Object? arguments);

  /// Long-lived host services (for example a local TCP server) use this
  /// callback to dispatch an event back into a Lua function captured by the
  /// runtime.
  void bindEventDispatcher(PluginEventDispatcher dispatcher) {}

  Future<void> close() async {}
}
