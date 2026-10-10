import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Android bridge for the isolated Kodi legacy runtime.
///
/// The Flutter shell deliberately does not share a renderer/process with Kodi.
/// This keeps the Store and the rest of AddKo alive even if a native Kodi addon,
/// codec or GPU driver crashes the legacy runtime.
class KodiCore {
  static const channel = MethodChannel('addko/kodi_core');
  static bool get supported => Platform.isAndroid;
  static int _sequence = 0;

  static Future<Map<String, String>> profile() async {
    final value = await channel.invokeMapMethod<String, String>('profile');
    if (value == null) throw StateError('Perfil do núcleo indisponível.');
    return value;
  }

  static Future<Map<String, dynamic>> status() async =>
      await channel.invokeMapMethod<String, dynamic>('status') ?? {};

  static Future<void> allowLocalFiles() =>
      channel.invokeMethod<void>('storage');

  /// Compatibility no-op. Kodi now owns a separate Activity instead of taking
  /// the renderer away from Flutter in the same Activity.
  static Future<void> setLegacyGui(bool enabled) =>
      channel.invokeMethod<void>('legacyGui', {'enabled': enabled});

  static Future<void> ensureReady() async {
    final state = await status();
    if (state['bundled'] == true) return;
    throw StateError(
      'O runtime Kodi não está empacotado neste APK. '
      '${state['error'] ?? 'Refaça o build Android.'}',
    );
  }

  /// Direct JSON-RPC is intentionally unavailable from the Flutter process now.
  /// This method is retained for diagnostics/older pages and returns the native
  /// channel error instead of coupling Flutter to the Kodi process again.
  static Future<dynamic> rpc(
    String method, [
    Map<String, dynamic> params = const {},
  ]) async {
    final id = ++_sequence;
    final raw = await channel.invokeMethod<String>('rpc', {
      'request': jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    });
    if (raw == null) throw StateError('Resposta vazia do núcleo.');
    final response = jsonDecode(raw);
    if (response is! Map || response['id'] != id) {
      throw StateError('Resposta inválida do núcleo.');
    }
    if (response.containsKey('error')) {
      throw StateError('$method: ${response['error']}');
    }
    if (!response.containsKey('result')) {
      throw StateError('$method: resultado ausente.');
    }
    return response['result'];
  }

  /// Kept for source compatibility. Discovery/enabling now happens inside the
  /// isolated Kodi Activity after Kodi JSON-RPC itself is ready.
  static Future<void> prepareAddon(String id) async {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id', 'ID vazio');
    await ensureReady();
  }

  /// Opens a classic Kodi addon in a crash-isolated native Kodi Activity.
  static Future<void> openLegacyAddon(String id) async {
    await ensureReady();
    await channel.invokeMethod<void>('openLegacyAddon', {'addonId': id});
  }

  static Future<List<Map<String, dynamic>>> directory(String url) async {
    final result = await rpc('Files.GetDirectory', {
      'directory': url,
      'media': 'files',
      'properties': ['title', 'thumbnail', 'art', 'plot'],
      'sort': {'method': 'none'},
    });
    if (result is! Map || result['files'] is! List) {
      throw StateError('O addon não retornou um diretório válido.');
    }
    return (result['files'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<void> open({String? addonId, bool selfTest = false}) async {
    await ensureReady();
    await channel.invokeMethod<void>('openKodi', {
      if (addonId != null) 'addonId': addonId,
      'selfTest': selfTest,
    });
  }
}
