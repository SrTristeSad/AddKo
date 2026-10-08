import 'dart:io';

import 'package:flutter/services.dart';

class AndroidPythonRuntimeInfo {
  const AndroidPythonRuntimeInfo({
    required this.home,
    required this.abi,
    required this.version,
  });

  final String home;
  final String abi;
  final String version;
}

class AndroidPythonRuntime {
  AndroidPythonRuntime._();

  static const MethodChannel _channel = MethodChannel('addko/python_runtime');
  static Future<AndroidPythonRuntimeInfo>? _prepared;

  static Future<AndroidPythonRuntimeInfo> prepare() {
    if (!Platform.isAndroid) {
      throw UnsupportedError('O runtime Android só pode ser preparado no Android.');
    }
    return _prepared ??= _prepare();
  }

  static Future<AndroidPythonRuntimeInfo> _prepare() async {
    final result = await _channel.invokeMapMethod<String, Object?>('prepare');
    if (result == null) {
      throw StateError('O host Android não retornou dados do runtime Python.');
    }

    final home = result['home']?.toString().trim() ?? '';
    final abi = result['abi']?.toString().trim() ?? '';
    final version = result['version']?.toString().trim() ?? '';
    if (home.isEmpty || abi.isEmpty || version.isEmpty) {
      throw StateError('Resposta inválida ao preparar o CPython embarcado.');
    }

    return AndroidPythonRuntimeInfo(
      home: home,
      abi: abi,
      version: version,
    );
  }
}
