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
    this.builtins = const [],
  });

  final List<LegacyPluginItem> items;
  final List<String> logs;
  final bool succeeded;
  final String? contentType;
  final String? category;
  final LegacyPluginItem? resolvedItem;
  final String? errorMessage;
  final List<String> builtins;
}
