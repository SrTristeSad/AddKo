import 'dart:convert';
import 'dart:io';

import 'embedded_python_host.dart';
import 'legacy_plugin_invocation.dart';
import 'legacy_plugin_result.dart';
import 'legacy_runtime_collector.dart';
import 'python_executor.dart';

class EmbeddedPythonExecutor implements PythonExecutor {
  EmbeddedPythonExecutor({
    required this.workerScriptPath,
    EmbeddedPythonHost? host,
  }) : _host = host ?? EmbeddedPythonHost.tryOpen();

  final String workerScriptPath;
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
    if (!host.hasBundledPython) {
      collector.consumeStderrLine(
        host.lastError.isEmpty
            ? 'Biblioteca CPython embarcada não encontrada para esta ABI.'
            : host.lastError,
      );
      return collector.build(exitCode: -2);
    }

    final initializeResult = host.initialize();
    if (initializeResult != 0) {
      collector.consumeStderrLine(
        host.lastError.isEmpty
            ? 'Falha ao inicializar CPython ($initializeResult).'
            : host.lastError,
      );
      return collector.build(exitCode: initializeResult);
    }

    final tempDirectory = await Directory.systemTemp.createTemp(
      'addko-embedded-python-',
    );
    final contextFile = File('${tempDirectory.path}/context.json');
    final stdoutFile = File('${tempDirectory.path}/stdout.log');
    final stderrFile = File('${tempDirectory.path}/stderr.log');
    final exitFile = File('${tempDirectory.path}/exit-code.txt');

    try {
      await contextFile.writeAsString(
        jsonEncode(invocation.toJson()),
        flush: true,
      );

      final source = _bootstrapSource(
        workerPath: workerScriptPath,
        contextPath: contextFile.path,
        stdoutPath: stdoutFile.path,
        stderrPath: stderrFile.path,
        exitPath: exitFile.path,
      );
      final nativeStatus = host.execute(source);

      if (await stdoutFile.exists()) {
        final lines = await stdoutFile.readAsLines();
        for (final line in lines) {
          collector.consumeStdoutLine(line);
        }
      }
      if (await stderrFile.exists()) {
        final lines = await stderrFile.readAsLines();
        for (final line in lines) {
          collector.consumeStderrLine(line);
        }
      }

      if (nativeStatus != 0) {
        collector.consumeStderrLine(
          host.lastError.isEmpty
              ? 'Falha no host CPython ($nativeStatus).'
              : host.lastError,
        );
        return collector.build(exitCode: nativeStatus);
      }

      var exitCode = 0;
      if (await exitFile.exists()) {
        exitCode = int.tryParse((await exitFile.readAsString()).trim()) ?? 0;
      }
      return collector.build(exitCode: exitCode);
    } finally {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    }
  }

  String _bootstrapSource({
    required String workerPath,
    required String contextPath,
    required String stdoutPath,
    required String stderrPath,
    required String exitPath,
  }) {
    String literal(String value) => jsonEncode(value);

    return '''
import io
import os
import runpy
import sys
import traceback

_worker = ${literal(workerPath)}
_context = ${literal(contextPath)}
_stdout_path = ${literal(stdoutPath)}
_stderr_path = ${literal(stderrPath)}
_exit_path = ${literal(exitPath)}

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

with open(_stdout_path, 'w', encoding='utf-8') as _stdout, open(
    _stderr_path, 'w', encoding='utf-8'
) as _stderr:
    sys.stdout = _stdout
    sys.stderr = _stderr
    # Until the native request bridge is connected, synchronous Kodi UI
    # requests receive their shim default instead of blocking the interpreter.
    sys.stdin = io.StringIO('')
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

with open(_exit_path, 'w', encoding='utf-8') as _handle:
    _handle.write(str(_exit_code))
''';
  }
}
