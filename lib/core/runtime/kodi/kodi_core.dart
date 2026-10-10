import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

/// Direct JNI JSON-RPC calls into the core embedded under the AddKo frontend.
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

  static Future<void> setLegacyGui(bool enabled) =>
      channel.invokeMethod<void>('legacyGui', {'enabled': enabled});

  static Future<void> ensureReady() async {
    for (var i = 0; i < 120; i++) {
      final state = await status();
      if (state['ready'] == true) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final state = await status();
    throw StateError(
        'O núcleo não respondeu. ${state['error'] ?? 'Abra Configurações → Núcleo para ver o log.'}');
  }

  static Future<dynamic> rpc(String method,
      [Map<String, dynamic> params = const {}]) async {
    final id = ++_sequence;
    final raw = await channel.invokeMethod<String>('rpc', {
      'request': jsonEncode(
          {'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}),
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

  static Future<void> prepareAddon(String id) async {
    await ensureReady();
    await rpc('Addons.ExecuteAddon', {
      'addonid': 'script.addko.bridge',
      'params': ['refresh', '']
    });
    Object? lastError;
    for (var i = 0; i < 40; i++) {
      try {
        await rpc('Addons.GetAddonDetails', {
          'addonid': id,
          'properties': ['enabled']
        });
        await rpc('Addons.SetAddonEnabled', {'addonid': id, 'enabled': true});
        return;
      } catch (error) {
        lastError = error;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError('O Kodi não conseguiu habilitar $id. $lastError');
  }

  /// Opens a classic Kodi plugin inside Kodi's own GUI.
  ///
  /// Flutter remains the AddKo shell, but while this call activates the plugin
  /// Kodi owns rendering and input. Android restores Flutter automatically when
  /// the Kodi window returns to Home.
  static Future<void> openLegacyAddon(String id) async {
    await prepareAddon(id);
    await setLegacyGui(true);
    try {
      await rpc('GUI.ActivateWindow', {
        'window': 'videos',
        'parameters': ['plugin://$id/', 'return'],
      });
    } catch (_) {
      await setLegacyGui(false);
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> directory(String url) async {
    final result = await rpc('Files.GetDirectory', {
      'directory': url,
      'media': 'files',
      'properties': ['title', 'thumbnail', 'art', 'plot'],
      'sort': {'method': 'none'}
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
    if (selfTest) {
      await rpc('Addons.ExecuteAddon', {
        'addonid': 'script.addko.bridge',
        'params': ['selftest', '']
      });
    } else if (addonId != null) {
      await prepareAddon(addonId);
    }
  }
}
