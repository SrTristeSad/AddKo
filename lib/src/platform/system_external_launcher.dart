import 'dart:io';

import 'package:flutter/services.dart';

class SystemExternalLauncher {
  const SystemExternalLauncher._();

  static const MethodChannel _channel = MethodChannel('addko/system');

  static bool get isSupported => Platform.isAndroid;

  static Future<bool> open(Uri uri) async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>(
          'openUri',
          <String, Object?>{'uri': uri.toString()},
        ) ??
        false;
  }
}
