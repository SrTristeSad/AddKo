import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'android_python_runtime.dart';
import 'embedded_python_host.dart';
import 'legacy_plugin_invocation.dart';
import 'legacy_plugin_result.dart';
import 'legacy_runtime_collector.dart';
import 'legacy_runtime_request.dart';
import 'python_executor.dart';

class EmbeddedPythonExecutor implements PythonExecutor {
  EmbeddedPythonExecutor({
    required this.workerScriptPath,
    this.requestHandler,
    EmbeddedPythonHost? host,
  }) : _host = host ?? EmbeddedPythonHost.tryOpen();

  final String workerScriptPath;
  final LegacyRuntimeRequestHandler? requestHandler;
  final EmbeddedPythonHost? _host;

  @override
  Future<LegacyPluginResult> invoke(LegacyPluginInvocation invocation) async {
    final collector = LegacyRuntimeCollector();
    final host = _host;
    if (host == null) {
      collector.consumeStderrLine(
        'Host nativo do CPython não foi encontrado no pacote Android.',
      );
      return collector.build(exitCode: -1);
    }

    AndroidPythonRuntimeInfo runtimeInfo;
    try {
      runtimeInfo = await AndroidPythonRuntime.prepare();
    } on Object catch (error) {
      collector.consumeStderrLine('Falha ao preparar CPython Android: $error');
      return collector.build(exitCode: -2);
    }

    if (!host.hasBundledPython) {
      collector.consumeStderrLine(
        host.lastError.isEmpty
            ? 'Biblioteca CPython embarcada não encontrada para ${runtimeInfo.abi}.'
            : host.lastError,
      );
      return collector.build(exitCode: -3);
    }

    final tempDirectory = await Directory.systemTemp.createTemp(
      'addko-embedded-python-',
    );
    final contextFile = File('${tempDirectory.path}/context.json');
    final stderrFile = File('${tempDirectory.path}/stderr.log');
    final exitFile = File('${tempDirectory.path}/exit-code.txt');
    final server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    final token = _bridgeToken();

    try {
      await contextFile.writeAsString(
        jsonEncode(invocation.toJson()),
        flush: true,
      );

      final workerPath = workerScriptPath;
      final contextPath = contextFile.path;
      final stderrPath = stderrFile.path;
      final exitPath = exitFile.path;
      final pythonHome = runtimeInfo.home;
      final port = server.port;

      final execution = Isolate.run<Map<String, Object?>>(
        () => _runEmbedded(
          workerPath: workerPath,
          contextPath: contextPath,
          stderrPath: stderrPath,
          exitPath: exitPath,
          pythonHome: pythonHome,
          port: port,
          token: token,
        ),
      );

      Socket? socket;
      try {
        socket = await server.first.timeout(const Duration(seconds: 8));
      } on TimeoutException {
        final nativeResult = await execution;
        collector.consumeStderrLine(
          nativeResult['error']?.toString().isNotEmpty == true
              ? nativeResult['error']!.toString()
              : 'CPython não abriu o bridge local do AddKo.',
        );
        return collector.build(
          exitCode: (nativeResult['status'] as num?)?.toInt() ?? -4,
        );
      }

      await _consumeBridge(socket, collector, token);
      final nativeResult = await execution;

      if (await stderrFile.exists()) {
        final lines = await stderrFile.readAsLines();
        for (final line in lines) {
          collector.consumeStderrLine(line);
        }
      }

      final nativeStatus = (nativeResult['status'] as num?)?.toInt() ?? 0;
      if (nativeStatus != 0) {
        final error = nativeResult['error']?.toString() ?? '';
        collector.consumeStderrLine(
          error.isEmpty ? 'Falha no host CPython ($nativeStatus).' : error,
        );
        return collector.build(exitCode: nativeStatus);
      }

      var exitCode = 0;
      if (await exitFile.exists()) {
        exitCode = int.tryParse((await exitFile.readAsString()).trim()) ?? 0;
      }
      return collector.build(exitCode: exitCode);
    } finally {
      await server.close();
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    }
  }

  Future<void> _consumeBridge(
    Socket socket,
    LegacyRuntimeCollector collector,
    String token,
  ) async {
    var authenticated = false;
    try {
      await for (final line in socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (!authenticated) {
          if (line != 'ADDKO_EMBEDDED $token') {
            collector.consumeStderrLine(
              'Bridge CPython rejeitado: handshake inválido.',
            );
            socket.destroy();
            return;
          }
          authenticated = true;
          continue;
        }

        final request = LegacyRuntimeRequest.tryParse(line);
        if (request == null) {
          collector.consumeStdoutLine(line);
          continue;
        }

        Object? result = request.defaultValue;
        final handler = requestHandler;
        if (handler != null) {
          try {
            result = await handler(request);
          } on Object catch (error) {
            collector.consumeStderrLine(
              'Embedded request ${request.method} failed: $error',
            );
          }
        }

        socket.writeln(
          jsonEncode({
            'request_id': request.id,
            'result': result,
          }),
        );
        await socket.flush();
      }
    } finally {
      await socket.close();
    }
  }

  static Map<String, Object?> _runEmbedded({
    required String workerPath,
    required String contextPath,
    required String stderrPath,
    required String exitPath,
    required String pythonHome,
    required int port,
    required String token,
  }) {
    final host = EmbeddedPythonHost.tryOpen();
    if (host == null) {
      return const {
        'status': -1,
        'error': 'Host nativo do CPython não pôde ser carregado no isolate.',
      };
    }
    if (!host.hasBundledPython) {
      return {
        'status': -2,
        'error': host.lastError,
      };
    }

    final configureResult = host.configure(pythonHome);
    if (configureResult != 0) {
      return {
        'status': configureResult,
        'error': host.lastError,
      };
    }

    final initializeResult = host.initialize();
    if (initializeResult != 0) {
      return {
        'status': initializeResult,
        'error': host.lastError,
      };
    }

    final source = _bootstrapSource(
      workerPath: workerPath,
      contextPath: contextPath,
      stderrPath: stderrPath,
      exitPath: exitPath,
      port: port,
      token: token,
    );
    final status = host.execute(source);
    return {
      'status': status,
      'error': status == 0 ? '' : host.lastError,
    };
  }

  static String _bootstrapSource({
    required String workerPath,
    required String contextPath,
    required String stderrPath,
    required String exitPath,
    required int port,
    required String token,
  }) {
    String literal(String value) => jsonEncode(value);

    return '''
import runpy
import socket
import sys
import traceback

_worker = ${literal(workerPath)}
_context = ${literal(contextPath)}
_stderr_path = ${literal(stderrPath)}
_exit_path = ${literal(exitPath)}
_bridge_port = $port
_bridge_token = ${literal(token)}

_old_stdout = sys.stdout
_old_stderr = sys.stderr
_old_stdin = sys.stdin
_old_argv = list(sys.argv)
_old_path = list(sys.path)
_exit_code = 0

for _name in (
    'addko_bridge',
    'addko_window',
    'xbmc',
    'xbmcaddon',
    'xbmcdrm',
    'xbmcgui',
    'xbmcplugin',
    'xbmcvfs',
):
    sys.modules.pop(_name, None)

_socket = socket.create_connection(('127.0.0.1', _bridge_port), timeout=8.0)
_stdin = _socket.makefile('r', encoding='utf-8', newline='\\n')
_stdout = _socket.makefile('w', encoding='utf-8', newline='\\n', buffering=1)
_stdout.write('ADDKO_EMBEDDED ' + _bridge_token + '\\n')
_stdout.flush()

with open(_stderr_path, 'w', encoding='utf-8') as _stderr:
    sys.stdout = _stdout
    sys.stderr = _stderr
    sys.stdin = _stdin
    sys.argv = [_worker, _context]
    try:
        runpy.run_path(_worker, run_name='__main__')
    except SystemExit as _error:
        _exit_code = _error.code if isinstance(_error.code, int) else 0
    except BaseException:
        traceback.print_exc(file=_stderr)
        _exit_code = 1
    finally:
        sys.stdout = _old_stdout
        sys.stderr = _old_stderr
        sys.stdin = _old_stdin
        sys.argv = _old_argv
        sys.path[:] = _old_path

try:
    _stdout.close()
    _stdin.close()
finally:
    _socket.close()

with open(_exit_path, 'w', encoding='utf-8') as _handle:
    _handle.write(str(_exit_code))
''';
  }

  String _bridgeToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
