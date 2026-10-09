import 'dart:convert';
import 'dart:io';

import 'legacy_plugin_invocation.dart';
import 'legacy_plugin_result.dart';
import 'legacy_runtime_collector.dart';
import 'legacy_runtime_request.dart';
import 'python_executor.dart';

class ProcessPythonExecutor implements PythonExecutor {
  const ProcessPythonExecutor({
    required this.pythonExecutable,
    required this.workerScriptPath,
    this.requestHandler,
  });

  final String pythonExecutable;
  final String workerScriptPath;
  final LegacyRuntimeRequestHandler? requestHandler;

  @override
  Future<LegacyPluginResult> invoke(LegacyPluginInvocation invocation) async {
    final collector = LegacyRuntimeCollector();
    final tempDirectory = await Directory.systemTemp.createTemp('addko-python-');
    final contextFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}context.json',
    );

    try {
      await contextFile.writeAsString(
        jsonEncode(invocation.toJson()),
        flush: true,
      );

      final process = await Process.start(
        pythonExecutable,
        [workerScriptPath, contextFile.path],
        workingDirectory: invocation.addonPath,
        environment: {
          ...Platform.environment,
          'PYTHONUTF8': '1',
          'PYTHONDONTWRITEBYTECODE': '1',
        },
        runInShell: false,
      );

      final stdoutDone = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asyncMap((line) async {
        final request = LegacyRuntimeRequest.tryParse(line);
        if (request == null) {
          collector.consumeStdoutLine(line);
          return;
        }

        Object? result = request.defaultValue;
        final handler = requestHandler;
        if (handler != null) {
          try {
            result = await handler(request);
          } on Object catch (error) {
            collector.consumeStderrLine(
              'GUI request ${request.method} failed: $error',
            );
          }
        }

        process.stdin.writeln(
          jsonEncode({
            'request_id': request.id,
            'result': result,
          }),
        );
        await process.stdin.flush();
      }).drain<void>();

      final stderrDone = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach(collector.consumeStderrLine);

      final exitCode = await process.exitCode;
      await Future.wait([stdoutDone, stderrDone]);
      await process.stdin.close();
      return collector.build(exitCode: exitCode);
    } on ProcessException catch (error) {
      collector.consumeStderrLine(error.toString());
      return collector.build(exitCode: -1);
    } finally {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    }
  }
}

class PythonExecutableResolver {
  const PythonExecutableResolver();

  Future<String?> resolve() async {
    final configured = Platform.environment['ADDKO_PYTHON']?.trim();
    final candidates = <String>[
      if (configured != null && configured.isNotEmpty) configured,
      if (Platform.isWindows) 'python.exe' else 'python3',
      if (Platform.isWindows) 'py.exe' else 'python',
    ];

    for (final candidate in candidates) {
      try {
        final result = await Process.run(
          candidate,
          const ['--version'],
          runInShell: false,
        );
        if (result.exitCode == 0) {
          return candidate;
        }
      } on ProcessException {
        // Try the next executable name.
      }
    }

    return null;
  }
}
