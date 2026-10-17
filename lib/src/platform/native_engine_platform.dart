import 'dart:io';

import 'package:flutter/services.dart';

/// Typed gateway to explicitly approved Android-native engines in the
/// signed AddKo APK. No arbitrary paths, URLs, or executable bytes accepted.
class NativeEnginePlatform {
  const NativeEnginePlatform();

  static const MethodChannel _channel = MethodChannel('addko/native_engines');

  bool get supported => Platform.isAndroid;

  Future<Object?> invoke(String action, String engine) async {
    if (!supported) {
      throw UnsupportedError('Motores nativos só disponíveis no Android.');
    }
    if (!RegExp(r'^[a-z][a-z0-9_-]{0,63}$').hasMatch(engine)) {
      throw ArgumentError.value(engine, 'engine', 'ID inválido.');
    }
    return _channel.invokeMethod<Object?>(action, <String, Object?>{
      'engine': engine,
    });
  }
}
