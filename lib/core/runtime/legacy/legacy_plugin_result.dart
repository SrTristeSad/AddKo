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
  final List<String> builtins;
}
