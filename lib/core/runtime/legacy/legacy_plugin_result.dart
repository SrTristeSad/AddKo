import 'legacy_plugin_item.dart';

class LegacyPluginResult {
  const LegacyPluginResult({
    required this.items,
    required this.logs,
    required this.succeeded,
    this.contentType,
    this.category,
    this.resolvedItem,
    this.errorMessage,
    this.errorType,
    this.errorLocation,
    this.errorTraceback,
    this.directoryEnded = false,
    this.directorySucceeded = true,
    this.updateListing = false,
    this.cacheToDisc = true,
    this.builtins = const [],
  });

  final List<LegacyPluginItem> items;
  final List<String> logs;
  final bool succeeded;
  final String? contentType;
  final String? category;
  final LegacyPluginItem? resolvedItem;
  final String? errorMessage;
  final String? errorType;
  final String? errorLocation;
  final String? errorTraceback;

  /// Whether the addon called xbmcplugin.endOfDirectory for this invocation.
  final bool directoryEnded;

  /// Kodi's `succeeded` flag from endOfDirectory. A false value means the
  /// directory retrieval failed; it is not a successful empty listing.
  final bool directorySucceeded;

  /// Kodi's `updateListing` flag. When true the current container is replaced
  /// instead of creating a normal navigation-history entry.
  final bool updateListing;

  /// Kodi's `cacheToDisc` hint. AddKo can use it for a conservative listing
  /// cache without changing addon semantics.
  final bool cacheToDisc;

  final List<String> builtins;
}
