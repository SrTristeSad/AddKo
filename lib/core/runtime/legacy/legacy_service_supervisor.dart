import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../addons/application/addon_install_controller.dart';
import '../../addons/domain/installed_addon.dart';
import 'kodi_json_rpc_compat.dart';
import 'legacy_runtime_collector.dart';
import 'legacy_runtime_request.dart';
import 'process_python_executor.dart';
import 'python_runtime_bundle.dart';

typedef LegacyServiceEventHandler = FutureOr<void> Function(
  String addonId,
  String method,
  Map<String, Object?> params,
);

class LegacyServiceSupervisor extends ChangeNotifier {
  LegacyServiceSupervisor({
    required this.addonInstallController,
    this.eventHandler,
    PythonRuntimeBundle? runtimeBundle,
    PythonExecutableResolver? pythonResolver,
  })  : _runtimeBundle = runtimeBundle ?? PythonRuntimeBundle(),
        _pythonResolver = pythonResolver ?? const PythonExecutableResolver();

  static const KodiJsonRpcCompat _jsonRpc = KodiJsonRpcCompat();

  final AddonInstallController addonInstallController;
  LegacyServiceEventHandler? eventHandler;
  final PythonRuntimeBundle _runtimeBundle;
  final PythonExecutableResolver _pythonResolver;

  final Map<String, _RunningService> _running = {};
  final Map<String, String> _errors = {};
  final Map<String, String> _failedVersions = {};

  bool _started = false;
  bool _disposed = false;
  bool _notifierDisposed = false;
  bool _reconciling = false;
  bool _reconcileAgain = false;

  List<String> get runningAddonIds => List.unmodifiable(_running.keys);
  Map<String, String> get errors => Map.unmodifiable(_errors);
  bool get started => _started;

  Future<void> start() async {
    if (_started || _disposed) {
      return;
    }

    await addonInstallController.initialize();
    if (_disposed) {
      return;
    }

    _started = true;
    addonInstallController.addListener(_handleAddonRegistryChanged);
    await reconcile();
  }

  void _handleAddonRegistryChanged() {
    unawaited(reconcile());
  }

  Future<void> reconcile() async {
    if (!_started || _disposed) {
      return;
    }
    if (_reconciling) {
      _reconcileAgain = true;
      return;
    }

    _reconciling = true;
    try {
      do {
        _reconcileAgain = false;
        final desired = <String, InstalledAddon>{
          for (final addon in addonInstallController.installedAddons)
            if (addon.manifest.isPythonService &&
                addon.manifest.pythonServiceEntrypoint?.trim().isNotEmpty == true)
              addon.manifest.id: addon,
        };

        for (final running in List<_RunningService>.from(_running.values)) {
          final replacement = desired[running.addonId];
          if (replacement == null ||
              replacement.manifest.version != running.version ||
              replacement.installPath != running.installPath) {
            await _stopRunning(running);
          }
        }

        for (final addon in desired.values) {
          if (_running.containsKey(addon.manifest.id)) {
            continue;
          }

          final failedVersion = _failedVersions[addon.manifest.id];
          if (failedVersion == addon.manifest.version) {
            continue;
          }

          await _startService(addon);
        }
      } while (_reconcileAgain && !_disposed);
    } finally {
      _reconciling = false;
    }
  }

  Future<void> retry(String addonId) async {
    _failedVersions.remove(addonId);
    _errors.remove(addonId);
    _notifyListenersSafely();
    await reconcile();
  }

  Future<void> restart(String addonId) async {
    if (_disposed) {
      return;
    }

    _failedVersions.remove(addonId);
    _errors.remove(addonId);
    final running = _running[addonId];
    if (running != null) {
      await _stopRunning(running);
      if (identical(_running[addonId], running)) {
        _running.remove(addonId);
      }
    }
    _notifyListenersSafely();
    await reconcile();
  }

  Future<void> shutdown() async {
    if (_disposed) {
      return;
    }
    _disposed = true;

    if (_started) {
      addonInstallController.removeListener(_handleAddonRegistryChanged);
    }

    final running = List<_RunningService>.from(_running.values);
    await Future.wait(running.map(_stopRunning));
    _running.clear();
    _notifyListenersSafely();
  }

  Future<void> _startService(InstalledAddon addon) async {
    final entrypoint = addon.manifest.pythonServiceEntrypoint?.trim();
    if (entrypoint == null || entrypoint.isEmpty) {
      return;
    }

    final python = await _pythonResolver.resolve();
    if (python == null) {
      _recordFailure(
        addon,
        'Nenhum runtime Python foi encontrado para iniciar o serviço.',
      );
      return;
    }

    Directory? tempDirectory;
    try {
      final runtimeFiles = await _runtimeBundle.materialize();
      final directories = await addonInstallController.directories();
      final supportRoot = p.dirname(directories.addonsRootPath);
      final profilePath = p.join(
        directories.addonDataRootPath,
        addon.manifest.id,
      );
      await Directory(profilePath).create(recursive: true);

      final tempRoot = p.join(Directory.systemTemp.path, 'addko');
      await Directory(tempRoot).create(recursive: true);
      tempDirectory = await Directory(tempRoot).createTemp('service-');
      final contextFile = File(p.join(tempDirectory.path, 'context.json'));
      final entrypointPath = p.normalize(p.join(addon.installPath, entrypoint));

      final context = <String, Object?>{
        'addon_id': addon.manifest.id,
        'addon_path': addon.installPath,
        'entrypoint_path': entrypointPath,
        'plugin_url': 'service://${addon.manifest.id}',
        'handle': 0,
        'query': '',
        'profile_path': profilePath,
        'addons_root': directories.addonsRootPath,
        'addon_data_root': directories.addonDataRootPath,
        'shims_path': runtimeFiles.shimsPath,
        'python_paths': _pythonPathsFor(addon),
        'special_paths': {
          'special://home': supportRoot,
          'special://profile': supportRoot,
          'special://userdata': supportRoot,
          'special://temp': tempRoot,
        },
        'argv': [entrypointPath],
        'runtime_kind': 'service',
      };
      await contextFile.writeAsString(jsonEncode(context), flush: true);

      final process = await Process.start(
        python,
        [runtimeFiles.workerPath, contextFile.path],
        workingDirectory: addon.installPath,
        environment: {
          ...Platform.environment,
          'PYTHONUTF8': '1',
          'PYTHONDONTWRITEBYTECODE': '1',
        },
        runInShell: false,
      );

      final running = _RunningService(
        addonId: addon.manifest.id,
        version: addon.manifest.version,
        installPath: addon.installPath,
        process: process,
        tempDirectory: tempDirectory,
      );
      tempDirectory = null;
      _running[addon.manifest.id] = running;
      _errors.remove(addon.manifest.id);
      _failedVersions.remove(addon.manifest.id);
      _notifyListenersSafely();

      final stdoutDone = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asyncMap((line) => _handleStdoutLine(running, line))
          .drain<void>();
      final stderrDone = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) {
        if (line.trim().isNotEmpty) {
          debugPrint('[AddKo service ${running.addonId}] $line');
        }
      });

      unawaited(_watchService(running, stdoutDone, stderrDone));
    } on Object catch (error) {
      if (tempDirectory != null && await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
      _recordFailure(addon, error.toString());
    }
  }

  Future<void> _handleStdoutLine(
    _RunningService running,
    String line,
  ) async {
    final request = LegacyRuntimeRequest.tryParse(line);
    if (request != null) {
      Object? result = request.defaultValue;
      switch (request.method) {
        case 'xbmc.Monitor.abortRequested':
          result = running.stopRequested;
          break;
        case 'xbmc.Monitor.waitForAbort':
          result = await _waitForAbort(running, request);
          break;
        case 'xbmc.executeJSONRPC':
          result = _jsonRpc.handle(request.params['request']?.toString() ?? '');
          break;
        default:
          break;
      }

      try {
        running.process.stdin.writeln(
          jsonEncode({
            'request_id': request.id,
            'result': result,
          }),
        );
        await running.process.stdin.flush();
      } on Object {
        // The process may have exited while the response was being prepared.
      }
      return;
    }

    if (!line.startsWith(LegacyRuntimeCollector.protocolPrefix)) {
      if (line.trim().isNotEmpty) {
        debugPrint('[AddKo service ${running.addonId}] $line');
      }
      return;
    }

    final payload = line.substring(LegacyRuntimeCollector.protocolPrefix.length);
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) {
        return;
      }
      final event = Map<String, Object?>.from(decoded);
      final method = event['method']?.toString() ?? '';
      final params = event['params'];
      final values = params is Map
          ? Map<String, Object?>.from(params)
          : const <String, Object?>{};

      if (method == 'xbmc.log') {
        final message = values['message']?.toString();
        if (message != null && message.isNotEmpty) {
          debugPrint('[AddKo service ${running.addonId}] $message');
        }
        return;
      }

      if (method == 'invocation.error') {
        final message = values['message']?.toString() ?? 'Falha no serviço.';
        _errors[running.addonId] = message;
        _notifyListenersSafely();
        return;
      }

      final handler = eventHandler;
      if (handler != null) {
        await Future<void>.sync(
          () => handler(running.addonId, method, values),
        );
        return;
      }

      if (method == 'xbmc.executebuiltin') {
        final function = values['function']?.toString() ?? '';
        debugPrint(
          '[AddKo service ${running.addonId}] built-in sem host: $function',
        );
      }
    } on FormatException {
      debugPrint('[AddKo service ${running.addonId}] protocolo inválido: $payload');
    } on Object catch (error, stackTrace) {
      debugPrint(
        '[AddKo service ${running.addonId}] falha ao encaminhar evento: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<bool> _waitForAbort(
    _RunningService running,
    LegacyRuntimeRequest request,
  ) async {
    if (running.stopRequested) {
      return true;
    }

    final rawTimeout = request.params['timeout'];
    final timeout = rawTimeout is num
        ? rawTimeout.toDouble()
        : double.tryParse(rawTimeout?.toString() ?? '') ?? -1;

    if (timeout <= 0) {
      await running.stopSignal.future;
      return true;
    }

    await Future.any<void>([
      Future<void>.delayed(
        Duration(milliseconds: (timeout * 1000).round()),
      ),
      running.stopSignal.future,
    ]);
    return running.stopRequested;
  }

  Future<void> _watchService(
    _RunningService running,
    Future<void> stdoutDone,
    Future<void> stderrDone,
  ) async {
    final exitCode = await running.process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);
    await _cleanupTemp(running);

    if (identical(_running[running.addonId], running)) {
      _running.remove(running.addonId);
    }

    if (!running.stopRequested && !_disposed) {
      _errors[running.addonId] =
          'Serviço encerrou inesperadamente com código $exitCode.';
      _failedVersions[running.addonId] = running.version;
    }
    _notifyListenersSafely();
  }

  Future<void> _stopRunning(_RunningService running) async {
    if (!running.stopRequested) {
      running.stopRequested = true;
      if (!running.stopSignal.isCompleted) {
        running.stopSignal.complete();
      }
    }

    try {
      await running.process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      running.process.kill();
      try {
        await running.process.exitCode.timeout(const Duration(seconds: 1));
      } on TimeoutException {
        running.process.kill(ProcessSignal.sigkill);
      }
    }
  }

  void _recordFailure(InstalledAddon addon, String message) {
    _errors[addon.manifest.id] = message;
    _failedVersions[addon.manifest.id] = addon.manifest.version;
    _notifyListenersSafely();
  }

  void _notifyListenersSafely() {
    if (!_notifierDisposed) {
      notifyListeners();
    }
  }

  Future<void> _cleanupTemp(_RunningService running) async {
    try {
      if (await running.tempDirectory.exists()) {
        await running.tempDirectory.delete(recursive: true);
      }
    } on FileSystemException {
      // Best effort cleanup only.
    }
  }

  List<String> _pythonPathsFor(InstalledAddon addon) {
    final result = <String>[];
    final visited = <String>{};

    void collect(InstalledAddon current) {
      if (!visited.add(current.manifest.id)) {
        return;
      }

      for (final dependency in current.manifest.dependencies) {
        if (dependency.optional ||
            dependency.id.startsWith('xbmc.') ||
            dependency.id.startsWith('kodi.')) {
          continue;
        }
        final installed = addonInstallController.installedById(dependency.id);
        if (installed == null) {
          continue;
        }
        collect(installed);

        var addedLibrary = false;
        for (final extension in installed.manifest.extensions) {
          if (extension.point != 'xbmc.python.module') {
            continue;
          }
          final library = extension.library?.trim();
          if (library != null && library.isNotEmpty) {
            result.add(p.normalize(p.join(installed.installPath, library)));
            addedLibrary = true;
          }
        }
        if (!addedLibrary) {
          result.add(installed.installPath);
        }
      }
    }

    collect(addon);
    return result.toSet().toList(growable: false);
  }

  @override
  void dispose() {
    _notifierDisposed = true;
    unawaited(shutdown());
    super.dispose();
  }
}

class _RunningService {
  _RunningService({
    required this.addonId,
    required this.version,
    required this.installPath,
    required this.process,
    required this.tempDirectory,
  });

  final String addonId;
  final String version;
  final String installPath;
  final Process process;
  final Directory tempDirectory;
  final Completer<void> stopSignal = Completer<void>();

  bool stopRequested = false;
}
