import 'package:flutter/services.dart';

class SystemFilePicker {
  const SystemFilePicker._();

  static const MethodChannel _channel = MethodChannel('addko/system');

  static Future<String?> pickAddko() {
    return _channel.invokeMethod<String>('pickAddko');
  }
}
