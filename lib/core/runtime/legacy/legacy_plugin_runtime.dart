import 'dart:io';

import 'package:path/path.dart' as p;

import '../../addons/application/addon_install_controller.dart';
import '../../addons/domain/installed_addon.dart';
import '../plugin_uri.dart';
import 'addon_path_guard.dart';
import 'embedded_python_executor.dart';
import 'legacy_plugin_invocation.dart';
import 'legacy_plugin_result.dart';
import 'legacy_runtime_request.dart';
import 'process_python_executor.dart';
import 'python_runtime_bundle.dart';

class LegacyPluginRuntime {
  LegacyPluginRuntime({
    required this.addonInstallController,
    this.requestHandler,
    PythonRuntimeBundle? runtimeBundle,
    PythonExecutableResolver? pythonResolver,
  })  : _runtimeBundle = runtimeBundle ?? PythonRuntimeBundle(),
        _pythonResolver = pythonResolver ?? const PythonExecutableResolver();

  final AddonInstallController addonInstallController;
  final LegacyRuntimeRequestHandler? requestHandler;
  final PythonRuntimeBundle _runtimeBundle;
  final PythonExecutableResolver _pythonResolver;

  int _nextHandle = 1;

  Future<LegacyPluginResult> invokeRoot(String addonId) {
    return invokeUrl('plugin://$addonId/');
  }

  Future<LegacyPluginResult> invokeUrl(String rawPluginUrl) async {
    await addonInstallController.initialize();

    final PluginUri pluginUri;
    try {
      pluginUri = PluginUri.parse(rawPluginUrl);
    } on FormatException catch (error) {
      return _failure(error.message.toString());
    }

    var addon = addonInstallController.installedById(pluginUri.addonId);
    if (addon == null) {
      // Kodi add-ons are allowed to unpack/install another add-on directly into
      // special://home/addons and then invoke it immediately. Refresh the disk
      // registry once before declaring the target missing.
      await addonInstallController.refreshInstalled();
      addon = addonInstallController.installedById(pluginUri.addonId);
    }
    if (addon == null) {
      return _failure('Addon ${pluginUri.addonId} não está instalado.');
    }
    if (!addonInstallController.hasRequiredDependencies(addon)) {
      return _failure(
        '${addon.manifest.name} está instalado, mas possui dependências obrigatórias incompletas. Abra a Loja e use Corrigir.',
      );
    }

    final entrypoint = addon.manifest.pythonEntrypoint;
    if (entrypoint == null || entrypoint.trim().isEmpty) {
      return _failure(
        '${addon.manifest.name} não declara xbmc.python.pluginsource.',
      );
    }

    return _invokeAddon(
      addon: addon,
      entrypoint: entrypoint,
      invocationUrl: rawPluginUrl,
      query: _queryFor(rawPluginUrl),
    );
  }

  Future<LegacyPluginResult> invokeScriptAddon(
    String addonId, {
    List<String> arguments = const [],
  }) async {
    await addonInstallController.initialize();
    var addon = addonInstallController.installedById(addonId);
    if (addon == null) {
      await addonInstallController.refreshInstalled();
      addon = addonInstallController.installedById(addonId);
    }
    if (addon == null) {
      return _failure('Addon $addonId não está instalado.');
    }
    if (!addonInstallController.hasRequiredDependencies(addon)) {
      return _failure(
        '${addon.manifest.name} possui dependências obrigatórias incompletas.',
      );
    }

    final entrypoint = addon.manifest.pythonScriptEntrypoint;
    if (entrypoint == null || entrypoint.trim().isEmpty) {
      return _failure(
        '${addon.manifest.name} não declara xbmc.python.script.',
      );
    }

    final entrypointPath = AddonPathGuard.resolveInside(
      addon.installPath,
      entrypoint,
    );
    if (entrypointPath == null) {
      return _failure(
        '${addon.manifest.name} declara um caminho Python inseguro: "$entrypoint".',
      );
    }

    return _invokeAddon(
      addon: addon,
      entrypoint: entrypoint,
      invocationUrl: 'script://$addonId',
      query: '',
      argv: [entrypointPath, ...arguments],
    );
  }

  Future<LegacyPluginResult> _invokeAddon({
    required InstalledAddon addon,
    required String entrypoint,
    required String invocationUrl,
    required String query,
    List<String>? argv,
  }) async {
    final entrypointPath = AddonPathGuard.resolveInside(
      addon.installPath,
      entrypoint,
    );
    if (entrypointPath == null) {
      return _failure(
        '${addon.manifest.name} declara um caminho Python inseguro: "$entrypoint".',
      );
    }
    if (!await File(entrypointPath).exists()) {
      return _failure(
        '${addon.manifest.name} declara o arquivo Python "$entrypoint", mas ele não existe no pacote instalado.',
      );
    }

    final runtimeFiles = await _runtimeBundle.materialize();
    final directories = await addonInstallController.directories();
    final supportRoot = p.dirname(directories.addonsRootPath);
    final profilePath = p.join(directories.addonDataRootPath, addon.manifest.id);
    await Directory(profilePath).create(recursive: true);
    // Legacy Kodi addons frequently access special://profile/Database directly
    // instead of using JSON-RPC. Kodi always exposes this directory.
    await Directory(p.join(supportRoot, 'Database')).create(recursive: true);

    final tempPath = p.join(Directory.systemTemp.path, 'addko');
    await Directory(tempPath).create(recursive: true);

    final invocation = LegacyPluginInvocation(
      addonId: addon.manifest.id,
      addonPath: addon.installPath,
      entrypointPath: entrypointPath,
      pluginUrl: invocationUrl,
      handle: _nextHandle++,
      query: query,
      profilePath: profilePath,
      addonsRoot: directories.addonsRootPath,
      addonDataRoot: directories.addonDataRootPath,
      shimsPath: runtimeFiles.shimsPath,
      pythonPaths: _pythonPathsFor(addon),
      specialPaths: {
        'special://home': supportRoot,
        'special://profile': supportRoot,
        'special://userdata': supportRoot,
        'special://temp': tempPath,
      },
      installedAddons: {
        for (final installed in addonInstallController.installedAddons)
          installed.manifest.id: installed.manifest.version,
      },
      argv: argv,
    );

    if (Platform.isAndroid) {
      final executor = EmbeddedPythonExecutor(
        workerScriptPath: runtimeFiles.workerPath,
        requestHandler: requestHandler,
      );
      return executor.invoke(invocation);
    }

    final python = await _pythonResolver.resolve();
    if (python == null) {
      return _failure(
        'Nenhum runtime Python foi encontrado. No desktop, configure Python 3 '
        'ou ADDKO_PYTHON; no Android o AddKo usa o runtime CPython embarcado.',
      );
    }

    final executor = ProcessPythonExecutor(
      pythonExecutable: python,
      workerScriptPath: runtimeFiles.workerPath,
      requestHandler: requestHandler,
    );
    return executor.invoke(invocation);
  }

  List<String> _pythonPathsFor(InstalledAddon addon) {
    final result = <String>[];
    final visited = <String>{};

    void collect(InstalledAddon current) {
      if (!visited.add(current.manifest.id.toLowerCase())) {
        return;
      }

      for (final dependency in current.manifest.dependencies) {
        if (dependency.optional ||
            dependency.id.toLowerCase().startsWith('xbmc.') ||
            dependency.id.toLowerCase().startsWith('kodi.')) {
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
            final libraryPath = AddonPathGuard.resolveInside(
              installed.installPath,
              library,
            );
            if (libraryPath != null &&
                FileSystemEntity.typeSync(libraryPath) !=
                    FileSystemEntityType.notFound) {
              result.add(libraryPath);
              addedLibrary = true;
            }
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

  String _queryFor(String rawPluginUrl) {
    final queryIndex = rawPluginUrl.indexOf('?');
    return queryIndex == -1 ? '' : rawPluginUrl.substring(queryIndex);
  }

  LegacyPluginResult _failure(String message) {
    return LegacyPluginResult(
      items: const [],
      logs: const [],
      succeeded: false,
      errorMessage: message,
    );
  }
}
