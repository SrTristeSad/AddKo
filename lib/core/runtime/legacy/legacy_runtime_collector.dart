import 'dart:convert';

import 'legacy_plugin_item.dart';
import 'legacy_plugin_result.dart';

class LegacyRuntimeCollector {
  static const protocolPrefix = 'ADDKO_RPC ';

  final List<LegacyPluginItem> _items = [];
  final List<String> _logs = [];
  final List<String> _builtins = [];
  String? _contentType;
  String? _category;
  LegacyPluginItem? _resolvedItem;
  bool _succeeded = true;
  String? _errorMessage;

  void consumeStdoutLine(String line) {
    if (!line.startsWith(protocolPrefix)) {
      if (line.trim().isNotEmpty) {
        _logs.add(line);
      }
      return;
    }

    final payload = line.substring(protocolPrefix.length);
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      _logs.add('Protocol parse error: $payload');
      return;
    }

    if (decoded is! Map) {
      return;
    }

    final event = Map<String, Object?>.from(decoded);
    final method = event['method']?.toString();
    final params = event['params'];
    final map = params is Map
        ? Map<String, Object?>.from(params)
        : const <String, Object?>{};

    switch (method) {
      case 'xbmcplugin.addDirectoryItem':
        final rawItem = map['item'];
        if (rawItem is Map) {
          final itemJson = Map<String, Object?>.from(rawItem);
          itemJson['url'] = map['url']?.toString() ?? '';
          itemJson['is_folder'] = map['is_folder'] == true;
          _items.add(LegacyPluginItem.fromJson(itemJson));
        }
        break;
      case 'xbmcplugin.addDirectoryItems':
        final rawItems = map['items'];
        if (rawItems is List) {
          for (final raw in rawItems) {
            if (raw is! Map) {
              continue;
            }
            final entry = Map<String, Object?>.from(raw);
            final rawItem = entry['item'];
            if (rawItem is! Map) {
              continue;
            }
            final itemJson = Map<String, Object?>.from(rawItem);
            itemJson['url'] = entry['url']?.toString() ?? '';
            itemJson['is_folder'] = entry['is_folder'] == true;
            _items.add(LegacyPluginItem.fromJson(itemJson));
          }
        }
        break;
      case 'xbmcplugin.setContent':
        _contentType = map['content']?.toString();
        break;
      case 'xbmcplugin.setPluginCategory':
        _category = map['category']?.toString();
        break;
      case 'xbmcplugin.setResolvedUrl':
        _succeeded = map['succeeded'] != false;
        final rawItem = map['item'];
        if (rawItem is Map) {
          _resolvedItem = LegacyPluginItem.fromJson(
            Map<String, Object?>.from(rawItem),
          );
        }
        break;
      case 'xbmc.executebuiltin':
        final function = map['function']?.toString().trim();
        if (function != null && function.isNotEmpty) {
          _builtins.add(function);
        }
        break;
      case 'xbmcaddon.openSettings':
        final addonId = map['addon_id']?.toString().trim();
        if (addonId != null && addonId.isNotEmpty) {
          _builtins.add('Addon.OpenSettings($addonId)');
        }
        break;
      case 'xbmc.log':
        final message = map['message']?.toString();
        if (message != null && message.isNotEmpty) {
          _logs.add(message);
        }
        break;
      case 'invocation.error':
        _succeeded = false;
        _errorMessage = map['message']?.toString() ?? 'Unknown Python error';
        final traceback = map['traceback']?.toString();
        if (traceback != null && traceback.isNotEmpty) {
          _logs.add(traceback);
        }
        break;
      default:
        if (method?.startsWith('kodi.compat.') == true) {
          final module = map['module']?.toString() ?? 'kodi';
          final symbol = map['name']?.toString() ??
              map['method']?.toString() ??
              map['class_name']?.toString() ??
              '?';
          _logs.add('[Kodi compat] $module.$symbol via fallback');
        }
        break;
    }
  }

  void consumeStderrLine(String line) {
    if (line.trim().isNotEmpty) {
      _logs.add('[stderr] $line');
    }
  }

  LegacyPluginResult build({int? exitCode}) {
    var succeeded = _succeeded;
    var error = _errorMessage;
    if (exitCode != null && exitCode != 0) {
      succeeded = false;
      error ??= 'Python runtime exited with code $exitCode.';
    }

    return LegacyPluginResult(
      items: List.unmodifiable(_items),
      logs: List.unmodifiable(_logs),
      succeeded: succeeded,
      contentType: _contentType,
      category: _category,
      resolvedItem: _resolvedItem,
      errorMessage: error,
      builtins: List.unmodifiable(_builtins),
    );
  }
}
