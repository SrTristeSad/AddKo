import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../addons/application/addon_install_controller.dart';
import '../../addons/domain/installed_addon.dart';
import 'embedded_python_executor.dart';
import 'kodi_json_rpc_compat.dart';
import 'legacy_plugin_invocation.dart';
import 'legacy_plugin_result.dart';
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

  final Map<String, _RunningProcessService> _running = {};
  final Map<String, _RunningEmbeddedService> _embeddedRunning = {};
  final Map<String, String> _errors = {};
  final Map<String, String> _failedVersions = {};

  bool _started = false;
  bool _disposed = false;
  bool _notifierDisposed = false;
  bool _reconciling = false;
  bool _reconcileAgain = false;

  List<String> get runningAddonIds => List.unmodifiable({
        ..._running.keys,
        ..._embeddedRunning.keys,
      });
  Map<String, String> get errors => Map.unmodifiable(_errors);
  bool get started => _started;

  Future<void> start() async {
    if (_started || _disposed) return;

    await addonInstallController.initialize();
    if (_disposed) return;

    _started = true;
    addonInstallController.addListener(_handleAddonRegistryChanged);
    await reconcile();
  }

  void _handleAddonRegistryChanged() {
    unawaited(reconcile());
  }

  Future<void> reconcile() async {
    if (!_started || _disposed) return;
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

        for (final running in List<_RunningProcessService>.from(_running.values)) {
          final replacement = desired[running.addonId];
          if (_needsReplacement(
            running.version,
            running.installPath,
            replacement,
          )) {
            await _stopProcessService(running);
          }
        }

        for (final running
            in List<_RunningEmbeddedService>.from(_embeddedRunning.values)) {
          final replacement = desired[running.addonId];
          if (_needsReplacement(
            running.version,
            running.installPath,
            replacement,
          )) {
            await _stopEmbeddedService(running);
          }
        }

        for (final addon in desired.values) {
          if (_running.containsKey(addon.manifest.id) ||
              _embeddedRunning.containsKey(addon.manifest.id)) {
            continue;
          }

          final failedVersion = _failedVersions[addon.manifest.id];
          if (failedVersion == addon.manifest.version) continue;
          await _startService(addon);
        }
      } while (_reconcileAgain && !_disposed);
    } finally {
      _reconciling = false;
    }
  }

  bool _needsReplacement(
    String version,
    String installPath,
    InstalledAddon? replacement,
  ) {
    return replacement == null ||
        replacement.manifest.version != version ||
        replacement.installPath != installPath;
  }

  Future<void> retry(String addonId) async {
    _failedVersions.remove(addonId);
    _errors.remove(addonId);
    _notifyListenersSafely();
    await reconcile();
  }

  Future<void> restart(String addonId) async {
    if (_disposed) return;

    _failedVersions.remove(addonId);
    _errors.remove(addonId);

    final process = _running[addonId];
    if (process != null) {
      await _stopProcessService(process);
    }

    final embedded = _embeddedRunning[addonId];
    if (embedded != null) {
      await _stopEmbeddedService(embedded);
    }

    _notifyListenersSafely();
    await reconcile();
  }

  Future<void> shutdown() async {
    if (_disposed) return;
    _disposed = true;

    if (_started) {
      addonInstallController.removeListener(_handleAddonRegistryChanged);
    }

    final processes = List<_RunningProcessService>.from(_running.values);
    final embedded = List<_RunningEmbeddedService>.from(_embeddedRunning.values);
    await Future.wait([
      ...processes.map(_stopProcessService),
      ...embedded.map(_stopEmbeddedService),
    ]);
    _running.clear();
    _embeddedRunning.clear();
    _notifyListenersSafely();
  }

  Future<void> _startService(InstalledAddon addon) async {
    if (Platform.isAndroid) {
      await _startEmbeddedService(addon);
      return;
    }
    await _startProcessService(addon);
  }

  Future<void> _startProcessService(InstalledAddon addon) async {
    final entrypoint = addon.manifest.pythonServiceEntrypoint?.trim();
    if (entrypoint == null || entrypoint.isEmpty) return;

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

      final running = _RunningProcessService(
        addonId: addon.manifest.id,
        version: addon.manifest.version,
        installPath: addon.installPath,
        process: process,
        tempDirectory: tempDirectory,
      );
      tempDirectory = null;
      _running[addon.manifest.id] = running;
      _markStarted(addon.manifest.id);

      final stdoutDone = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asyncMap((line) => _handleProcessStdoutLine(running, line))
          .drain<void>();
      final stderrDone = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) {
        if (line.trim().isNotEmpty) {
          debugPrint('[AddKo service ${running.addonId}] $line');
        }
      });

      unawaited(_watchProcessService(running, stdoutDone, stderrDone));
    } on Object catch (error) {
      if (tempDirectory != null && await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
      _recordFailure(addon, error.toString());
    }
  }

  Future<void> _startEmbeddedService(InstalledAddon addon) async {
    final entrypoint = addon.manifest.pythonServiceEntrypoint?.trim();
    if (entrypoint == null || entrypoint.isEmpty) return;

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
      final entrypointPath = p.normalize(p.join(addon.installPath, entrypoint));

      final running = _RunningEmbeddedService(
        addonId: addon.manifest.id,
        version: addon.manifest.version,
        installPath: addon.installPath,
      );
      _embeddedRunning[addon.manifest.id] = running;
      _markStarted(addon.manifest.id);

      final invocation = LegacyPluginInvocation(
        addonId: addon.manifest.id,
        addonPath: addon.installPath,
        entrypointPath: entrypointPath,
        pluginUrl: 'service://${addon.manifest.id}',
        handle: 0,
        query: '',
        profilePath: profilePath,
        addonsRoot: directories.addonsRootPath,
        addonDataRoot: directories.addonDataRootPath,
        shimsPath: runtimeFiles.shimsPath,
        pythonPaths: _pythonPathsFor(addon),
        specialPaths: {
          'special://home': supportRoot,
          'special://profile': supportRoot,
          'special://userdata': supportRoot,
          'special://temp': tempRoot,
        },
        argv: [entrypointPath],
      );

      final executor = EmbeddedPythonExecutor(
        workerScriptPath: runtimeFiles.workerPath,
        requestHandler: (request) => _handleEmbeddedRequest(running, request),
        eventHandler: (method, params) =>
            _handleEmbeddedEvent(running, method, params),
      );
      running.execution = executor.invoke(invocation);
      unawaited(_watchEmbeddedService(running));
    } on Object catch (error) {
      _embeddedRunning.remove(addon.manifest.id);
      _recordFailure(addon, error.toString());
    }
  }

  void _markStarted(String addonId) {
    _errors.remove(addonId);
    _failedVersions.remove(addonId);
    _notifyListenersSafely();
  }

  Future<void> _handleProcessStdoutLine(
    _RunningProcessService running,
    String line,
  ) async {
    final request = LegacyRuntimeRequest.tryParse(line);
    if (request != null) {
      final result = await _handleServiceRequest(running, request);
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
      if (decoded is! Map) return;
      final event = Map<String, Object?>.from(decoded);
      final method = event['method']?.toString() ?? '';
      final rawParams = event['params'];
      final params = rawParams is Map
          ? Map<String, Object?>.from(rawParams)
          : const <String, Object?>{};
      await _dispatchEvent(running.addonId, method, params);
    } on FormatException {
      debugPrint('[AddKo service ${running.addonId}] protocolo inválido: $payload');
    } on Object catch (error, stackTrace) {
      debugPrint(
        '[AddKo service ${running.addonId}] falha ao encaminhar evento: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<Object?> _handleEmbeddedRequest(
    _RunningEmbeddedService running,
    LegacyRuntimeRequest request,
  ) {
    return _handleServiceRequest(running, request);
  }

  Future<Object?> _handleServiceRequest(
    _ServiceStopState running,
    LegacyRuntimeRequest request,
  ) async {
    switch (request.method) {
      case 'xbmc.Monitor.abortRequested':
        return running.stopRequested;
      case 'xbmc.Monitor.waitForAbort':
        return _waitForStop(running, request);
      case 'xbmc.executeJSONRPC':
        return _jsonRpc.handle(request.params['request']?.toString() ?? '');
      default:
        return request.defaultValue;
    }
  }

  Future<bool> _waitForStop(
    _ServiceStopState running,
    LegacyRuntimeRequest request,
  ) async {
    if (running.stopRequested) return true;

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

  Future<void> _handleEmbeddedEvent(
    _RunningEmbeddedService running,
    String method,
    Map<String, Object?> params,
  ) {
    return _dispatchEvent(running.addonId, method, params);
  }

  Future<void> _dispatchEvent(
    String addonId,
    String method,
    Map<String, Object?> params,
  ) async {
    if (method == 'xbmc.log') {
      final message = params['message']?.toString();
      if (message != null && message.isNotEmpty) {
        debugPrint('[AddKo service $addonId] $message');
      }
      return;
    }

    if (method == 'invocation.error') {
      final message = params['message']?.toString() ?? 'Falha no serviço.';
      _errors[addonId] = message;
      _notifyListenersSafely();
      return;
    }

    final handler = eventHandler;
    if (handler != null) {
      await Future<void>.sync(() => handler(addonId, method, params));
      return;
    }

    if (method == 'xbmc.executebuiltin') {
      final function = params['function']?.toString() ?? '';
      debugPrint('[AddKo service $addonId] built-in sem host: $function');
    }
  }

  Future<void> _watchProcessService(
    _RunningProcessService running,
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
      _recordUnexpectedExit(running.addonId, running.version, exitCode);
    }
    _notifyListenersSafely();
  }

  Future<void> _watchEmbeddedService(_RunningEmbeddedService running) async {
    LegacyPluginResult result;
    try {
      result = await running.execution;
    } on Object catch (error) {
      if (identical(_embeddedRunning[running.addonId], running)) {
        _embeddedRunning.remove(running.addonId);
      }
      if (!running.stopRequested && !_disposed) {
        _errors[running.addonId] = 'Serviço embarcado falhou: $error';
        _failedVersions[running.addonId] = running.version;
      }
      _notifyListenersSafely();
      return;
    }

    if (identical(_embeddedRunning[running.addonId], running)) {
      _embeddedRunning.remove(running.addonId);
    }

    if (!running.stopRequested && !_disposed) {
      final message = result.errorMessage?.trim();
      _errors[running.addonId] = message?.isNotEmpty == true
          ? message!
          : 'Serviço encerrou inesperadamente no CPython embarcado.';
      _failedVersions[running.addonId] = running.version;
    }
    _notifyListenersSafely();
  }

  void _recordUnexpectedExit(String addonId, String version, int exitCode) {
    _errors[addonId] =
        'Serviço encerrou inesperadamente com código $exitCode.';
    _failedVersions[addonId] = version;
  }

  Future<void> _stopProcessService(_RunningProcessService running) async {
    _requestStop(running);

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

  Future<void> _stopEmbeddedService(_RunningEmbeddedService running) async {
    _requestStop(running);
    try {
      await running.execution.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      _errors[running.addonId] =
          'O serviço não respondeu ao pedido de encerramento do Monitor.';
      _notifyListenersSafely();
      // Keep the service registered: starting another copy would be less safe
      // than leaving the unresponsive subinterpreter visible to the user.
      return;
    }

    if (identical(_embeddedRunning[running.addonId], running)) {
      _embeddedRunning.remove(running.addonId);
    }
  }

  void _requestStop(_ServiceStopState running) {
    if (!running.stopRequested) {
      running.stopRequested = true;
      if (!running.stopSignal.isCompleted) {
        running.stopSignal.complete();
      }
    }
  }

  void _recordFailure(InstalledAddon addon, String message) {
    _errors[addon.manifest.id] = message;
    _failedVersions[addon.manifest.id] = addon.manifest.version;
    _notifyListenersSafely();
  }

  void _notifyListenersSafely() {
    if (!_notifierDisposed) notifyListeners();
  }

  Future<void> _cleanupTemp(_RunningProcessService running) async {
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
      if (!visited.add(current.manifest.id)) return;

      for (final dependency in current.manifest.dependencies) {
        if (dependency.optional ||
            dependency.id.startsWith('xbmc.') ||
            dependency.id.startsWith('kodi.')) {
          continue;
        }
        final installed = addonInstallController.installedById(dependency.id);
        if (installed == null) continue;
        collect(installed);

        var addedLibrary = false;
        for (final extension in installed.manifest.extensions) {
          if (extension.point != 'xbmc.python.module') continue;
          final library = extension.library?.trim();
          if (library != null && library.isNotEmpty) {
            result.add(p.normalize(p.join(installed.installPath, library)));
            addedLibrary = true;
          }
        }
        if (!addedLibrary) result.add(installed.installPath);
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

abstract class _ServiceStopState {
  String get addonId;
  String get version;
  String get installPath;
  Completer<void> get stopSignal;
  bool get stopRequested;
  set stopRequested(bool value);
}

class _RunningProcessService implements _ServiceStopState {
  _RunningProcessService({
    required this.addonId,
    required this.version,
    required this.installPath,
    required this.process,
    required this.tempDirectory,
  });

  @override
  final String addonId;
  @override
  final String version;
  @override
  final String installPath;
  final Process process;
  final Directory tempDirectory;
  @override
  final Completer<void> stopSignal = Completer<void>();

  @override
  bool stopRequested = false;
}

class _RunningEmbeddedService implements _ServiceStopState {
  _RunningEmbeddedService({
    required this.addonId,
    required this.version,
    required this.installPath,
  });

  @override
  final String addonId;
  @override
  final String version;
  @override
  final String installPath;
  @override
  final Completer<void> stopSignal = Completer<void>();

  late Future<LegacyPluginResult> execution;

  @override
  bool stopRequested = false;
}
