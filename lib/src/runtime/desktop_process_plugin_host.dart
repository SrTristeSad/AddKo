import 'dart:async';
import 'dart:io';

import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:addko/src/runtime/plugin_host.dart';
import 'package:path/path.dart' as p;

/// Adds generic native-process support on desktop hosts.
///
/// This is intentionally plugin-agnostic. It does not know about Elementum or
/// torrents. Executables must live inside the installed plugin directory or
/// the plugin's private data directory, and the plugin must already declare
/// `background` + `storage`.
class DesktopProcessPluginHost extends PluginHost {
  DesktopProcessPluginHost({
    required this.inner,
    required this.manifest,
    required this.pluginDirectory,
    required this.dataDirectory,
  });

  final PluginHost inner;
  final PluginManifest manifest;
  final Directory pluginDirectory;
  final Directory dataDirectory;

  final Map<int, Process> _processes = <int, Process>{};
  int _nextProcessId = 0;
  bool _closed = false;

  bool get _enabled =>
      !Platform.isAndroid &&
      !Platform.isIOS &&
      manifest.permissions.contains(PluginPermission.background) &&
      manifest.permissions.contains(PluginPermission.storage);

  @override
  Map<String, bool> get capabilities => <String, bool>{
        ...inner.capabilities,
        'process': _enabled,
      };

  @override
  Future<Object?> invoke(String operation, Object? arguments) async {
    if (operation != 'process.spawn' &&
        operation != 'process.stop' &&
        operation != 'fs.set_executable' &&
        operation != 'fs.chmod') {
      return inner.invoke(operation, arguments);
    }

    if (!_enabled) {
      throw const DesktopProcessHostException(
        'Processos nativos não estão disponíveis neste host.',
      );
    }

    final args = _map(arguments);
    switch (operation) {
      case 'process.spawn':
        return _spawn(args);
      case 'process.stop':
        return _stop(_int(args['handle'], min: 1));
      case 'fs.set_executable':
        return _setExecutable(
          args['path'],
          executable: args['executable'] != false,
        );
      case 'fs.chmod':
        return _chmod(args['path'], args['mode']?.toString() ?? '755');
    }
    throw DesktopProcessHostException('Operação desconhecida: $operation');
  }

  Future<int> _spawn(Map<String, Object?> args) async {
    _ensureOpen();

    final executable = _allowedPath(args['path']);
    if (!await File(executable).exists()) {
      throw DesktopProcessHostException(
        'Executável não encontrado: $executable',
      );
    }

    final rawArgs = args['args'];
    final processArgs = rawArgs is List
        ? rawArgs.map((value) => value.toString()).toList(growable: false)
        : const <String>[];

    String? workingDirectory;
    final rawCwd = args['cwd']?.toString();
    if (rawCwd != null && rawCwd.trim().isNotEmpty) {
      workingDirectory = _allowedPath(rawCwd);
    }

    final environment = <String, String>{};
    final rawEnv = args['env'];
    if (rawEnv is Map) {
      for (final entry in rawEnv.entries) {
        final key = entry.key.toString();
        if (key.isEmpty || key.contains('=')) {
          throw const DesktopProcessHostException(
            'Nome de variável de ambiente inválido.',
          );
        }
        environment[key] = entry.value.toString();
      }
    }

    final process = await Process.start(
      executable,
      processArgs,
      workingDirectory: workingDirectory,
      environment: environment.isEmpty ? null : environment,
      includeParentEnvironment: true,
      runInShell: false,
      mode: ProcessStartMode.normal,
    );

    // Avoid blocking a child process whose stdout/stderr buffers fill up.
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());

    final id = ++_nextProcessId;
    _processes[id] = process;
    unawaited(
      process.exitCode.then((_) {
        _processes.remove(id);
      }),
    );
    return id;
  }

  Future<bool> _stop(int handle) async {
    final process = _processes.remove(handle);
    if (process == null) return false;

    if (process.kill(ProcessSignal.sigterm)) {
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
        return true;
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        return true;
      }
    }
    return false;
  }

  Future<bool> _setExecutable(Object? raw, {required bool executable}) async {
    if (Platform.isWindows) return true;
    return _chmod(raw, executable ? '755' : '644');
  }

  Future<bool> _chmod(Object? raw, String mode) async {
    if (Platform.isWindows) return true;
    if (!RegExp(r'^[0-7]{3,4}$').hasMatch(mode)) {
      throw const DesktopProcessHostException('Modo chmod inválido.');
    }

    final path = _allowedPath(raw);
    final result = await Process.run(
      '/bin/chmod',
      <String>[mode, path],
      runInShell: false,
    );
    if (result.exitCode != 0) {
      throw DesktopProcessHostException(
        'chmod falhou (${result.exitCode}): ${result.stderr}',
      );
    }
    return true;
  }

  String _allowedPath(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) {
      throw const DesktopProcessHostException('Caminho vazio.');
    }

    final candidate = p.normalize(p.absolute(value));
    final pluginRoot = p.normalize(p.absolute(pluginDirectory.path));
    final dataRoot = p.normalize(p.absolute(dataDirectory.path));

    if (candidate == pluginRoot ||
        candidate == dataRoot ||
        p.isWithin(pluginRoot, candidate) ||
        p.isWithin(dataRoot, candidate)) {
      return candidate;
    }

    throw const DesktopProcessHostException(
      'Processo só pode usar arquivos dentro do plugin ou dos próprios dados.',
    );
  }

  @override
  void bindEventDispatcher(PluginEventDispatcher dispatcher) {
    inner.bindEventDispatcher(dispatcher);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    final processes = _processes.values.toList(growable: false);
    _processes.clear();
    for (final process in processes) {
      process.kill(ProcessSignal.sigterm);
    }
    await inner.close();
  }

  void _ensureOpen() {
    if (_closed) {
      throw const DesktopProcessHostException('Host de processos já encerrado.');
    }
  }
}

Map<String, Object?> _map(Object? value) {
  if (value == null) return <String, Object?>{};
  if (value is! Map) {
    throw const DesktopProcessHostException(
      'Argumentos da operação devem ser objeto.',
    );
  }
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

int _int(Object? value, {required int min}) {
  final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
  if (parsed == null || parsed < min) {
    throw DesktopProcessHostException('Inteiro inválido: $value');
  }
  return parsed;
}

class DesktopProcessHostException implements Exception {
  const DesktopProcessHostException(this.message);

  final String message;

  @override
  String toString() => 'DesktopProcessHostException: $message';
}
