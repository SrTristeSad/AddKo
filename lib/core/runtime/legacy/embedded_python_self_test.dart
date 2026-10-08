import 'dart:io';

import 'android_python_runtime.dart';
import 'embedded_python_host.dart';

class EmbeddedPythonSelfTestResult {
  const EmbeddedPythonSelfTestResult({
    required this.passed,
    required this.message,
    this.version = '',
    this.abi = '',
  });

  final bool passed;
  final String message;
  final String version;
  final String abi;
}

Future<EmbeddedPythonSelfTestResult> runEmbeddedPythonSelfTest() async {
  if (!Platform.isAndroid) {
    return const EmbeddedPythonSelfTestResult(
      passed: false,
      message: 'O teste do CPython embarcado é destinado ao Android/Android TV.',
    );
  }

  try {
    final runtime = await AndroidPythonRuntime.prepare();
    final host = EmbeddedPythonHost.tryOpen();
    if (host == null) {
      return EmbeddedPythonSelfTestResult(
        passed: false,
        message: 'libaddko_python_host não pôde ser carregada.',
        version: runtime.version,
        abi: runtime.abi,
      );
    }
    if (!host.hasBundledPython) {
      return EmbeddedPythonSelfTestResult(
        passed: false,
        message: host.lastError.isEmpty
            ? 'libpython não foi encontrada para ${runtime.abi}.'
            : host.lastError,
        version: runtime.version,
        abi: runtime.abi,
      );
    }

    final configureStatus = host.configure(runtime.home);
    if (configureStatus != 0) {
      return EmbeddedPythonSelfTestResult(
        passed: false,
        message: 'Falha ao configurar PYTHONHOME: ${host.lastError}',
        version: runtime.version,
        abi: runtime.abi,
      );
    }

    final initializeStatus = host.initialize();
    if (initializeStatus != 0) {
      return EmbeddedPythonSelfTestResult(
        passed: false,
        message: 'Falha ao inicializar CPython: ${host.lastError}',
        version: runtime.version,
        abi: runtime.abi,
      );
    }

    final status = host.executeIsolated(r'''
import hashlib
import json
import socket
import sqlite3
import ssl
import urllib.parse
import zlib

assert json.loads('{"ok": true}')['ok'] is True
connection = sqlite3.connect(':memory:')
connection.execute('create table addko(value text)')
connection.execute('insert into addko values (?)', ('ok',))
assert connection.execute('select value from addko').fetchone()[0] == 'ok'
connection.close()
assert zlib.decompress(zlib.compress(b'addko')) == b'addko'
assert len(hashlib.sha256(b'addko').hexdigest()) == 64
assert ssl.OPENSSL_VERSION
assert socket.AF_INET
assert urllib.parse.urlparse('https://example.com/addko').scheme == 'https'
''');

    if (status != 0) {
      return EmbeddedPythonSelfTestResult(
        passed: false,
        message: host.lastError.isEmpty
            ? 'O CPython retornou status $status durante o teste.'
            : host.lastError,
        version: host.version,
        abi: runtime.abi,
      );
    }

    return EmbeddedPythonSelfTestResult(
      passed: true,
      message: 'json, sqlite3, ssl, socket, zlib, hashlib e urllib carregaram corretamente.',
      version: host.version,
      abi: runtime.abi,
    );
  } on Object catch (error) {
    return EmbeddedPythonSelfTestResult(
      passed: false,
      message: 'Falha no teste do runtime: $error',
    );
  }
}
