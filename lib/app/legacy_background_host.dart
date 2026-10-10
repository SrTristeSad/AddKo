import 'dart:async';

import '../core/addons/application/addon_install_controller.dart';
import '../core/addons/domain/kodi_version.dart';
import '../core/player/playback_host_controller.dart';
import '../core/repositories/application/repository_registry.dart';
import '../core/repositories/application/repository_store_controller.dart';
import '../core/repositories/domain/repository_catalog.dart';
import '../core/runtime/legacy/kodi_builtin_command.dart';
import '../core/runtime/legacy/legacy_plugin_item.dart';
import '../core/runtime/legacy/legacy_plugin_result.dart';
import '../core/runtime/legacy/legacy_plugin_runtime.dart';
import '../core/runtime/legacy/legacy_runtime_request.dart';

typedef BackgroundMessageHandler = void Function(
  String message, {
  Duration? duration,
});
typedef BackgroundPlaybackHandler = FutureOr<void> Function(
  LegacyPluginItem item,
);
typedef BackgroundRuntimeRequestHandler = Future<Object?> Function(
  LegacyRuntimeRequest request,
);

class LegacyBackgroundHost {
  LegacyBackgroundHost({
    required this.repositoryRegistry,
    required this.repositoryStoreController,
    required this.addonInstallController,
    required this.requestHandler,
    required this.onMessage,
    required this.onPlayback,
    PlaybackHostController? playbackHost,
  }) : playbackHost = playbackHost ?? PlaybackHostController.shared {
    _runtime = LegacyPluginRuntime(
      addonInstallController: addonInstallController,
      requestHandler: requestHandler,
    );
  }

  final RepositoryRegistry repositoryRegistry;
  final RepositoryStoreController repositoryStoreController;
  final AddonInstallController addonInstallController;
  final BackgroundRuntimeRequestHandler requestHandler;
  final BackgroundMessageHandler onMessage;
  final BackgroundPlaybackHandler onPlayback;
  final PlaybackHostController playbackHost;
  late final LegacyPluginRuntime _runtime;

  Future<void> handleServiceEvent(
    String addonId,
    String method,
    Map<String, Object?> params,
  ) async {
    switch (method) {
      case 'xbmcgui.Dialog.notification':
        final heading = params['heading']?.toString().trim() ?? '';
        final message = params['message']?.toString().trim() ?? '';
        onMessage(
          message.isEmpty
              ? (heading.isEmpty ? addonId : heading)
              : heading.isEmpty
                  ? message
                  : '$heading\n$message',
          duration: _notificationDuration(params['time']),
        );
        return;
      case 'xbmc.executebuiltin':
        await _handleBuiltin(
          addonId,
          KodiBuiltinCommand.parse(params['function']?.toString() ?? ''),
        );
        return;
      case 'xbmc.Player.play':
        await _handlePlayerPlay(params);
        return;
      case 'xbmc.Player.pause':
        await playbackHost.pause();
        return;
      case 'xbmc.Player.stop':
        await playbackHost.stop();
        return;
      case 'xbmc.Player.seekTime':
        final raw = params['time'];
        final seconds = raw is num
            ? raw.toDouble()
            : double.tryParse(raw?.toString() ?? '');
        if (seconds != null && seconds >= 0) {
          await playbackHost.seek(
            Duration(milliseconds: (seconds * 1000).round()),
          );
        }
        return;
      default:
        return;
    }
  }

  Future<void> _handlePlayerPlay(Map<String, Object?> params) async {
    final path = params['path']?.toString() ?? '';
    if (path.trim().isEmpty) return;

    final rawItem = params['item'];
    if (rawItem is Map) {
      final itemJson = Map<String, Object?>.from(rawItem);
      itemJson.putIfAbsent('path', () => path);
      itemJson.putIfAbsent('url', () => path);
      itemJson.putIfAbsent('is_folder', () => false);
      await Future<void>.sync(
        () => onPlayback(LegacyPluginItem.fromJson(itemJson)),
      );
      return;
    }

    await Future<void>.sync(
      () => onPlayback(
        LegacyPluginItem(
          label: '',
          path: path,
          url: path,
          isFolder: false,
        ),
      ),
    );
  }

  Future<void> _handleBuiltin(
    String sourceAddonId,
    KodiBuiltinCommand command, {
    int depth = 0,
  }) async {
    if (command.isEmpty || depth > 16) return;

    switch (command.normalizedName) {
      case 'notification':
        final heading = command.argument(0)?.trim() ?? sourceAddonId;
        final message = command.argument(1)?.trim() ?? '';
        onMessage(
          message.isEmpty ? heading : '$heading\n$message',
          duration: _notificationDuration(command.argument(2)),
        );
        return;
      case 'updateaddonrepos':
        try {
          await repositoryRegistry.initialize();
          await Future.wait([
            repositoryStoreController.ensureKodiSystemCatalog(),
            repositoryStoreController.synchronizeAll(
              repositoryRegistry.sources,
            ),
          ]);
          onMessage('Repositórios atualizados por $sourceAddonId.');
        } on Object catch (error) {
          onMessage('Falha ao atualizar repositórios: $error');
        }
        return;
      case 'updatelocaladdons':
        try {
          await addonInstallController.refreshInstalled();
          onMessage('Addons locais atualizados por $sourceAddonId.');
        } on Object catch (error) {
          onMessage('Falha ao atualizar addons locais: $error');
        }
        return;
      case 'installaddon':
        final target = command.argument(0)?.trim();
        if (target != null && target.isNotEmpty) {
          await _installAddon(sourceAddonId, target);
        }
        return;
      case 'runplugin':
        final target = command.argument(0)?.trim();
        if (target != null && target.startsWith('plugin://')) {
          await _runPlugin(sourceAddonId, target, depth: depth + 1);
        }
        return;
      case 'runaddon':
        final targetId = command.argument(0)?.trim();
        if (targetId == null || targetId.isEmpty) return;
        final addon = addonInstallController.installedById(targetId);
        if (addon?.manifest.isPythonPlugin == true) {
          await _runPlugin(
            sourceAddonId,
            'plugin://$targetId/',
            depth: depth + 1,
          );
        } else if (addon?.manifest.isPythonScript == true) {
          await _runScript(
            sourceAddonId,
            targetId,
            const [],
            depth: depth + 1,
          );
        }
        return;
      case 'runscript':
        final target = command.argument(0)?.trim();
        if (target == null || target.isEmpty) return;
        if (target.startsWith('plugin://')) {
          await _runPlugin(sourceAddonId, target, depth: depth + 1);
        } else {
          await _runScript(
            sourceAddonId,
            target,
            command.arguments.skip(1).toList(growable: false),
            depth: depth + 1,
          );
        }
        return;
      case 'playmedia':
        final target = command.argument(0)?.trim();
        if (target == null || target.isEmpty) return;
        if (target.startsWith('plugin://')) {
          await _runPlugin(sourceAddonId, target, depth: depth + 1);
        } else {
          await Future<void>.sync(
            () => onPlayback(
              LegacyPluginItem(
                label: command.argument(1)?.trim() ?? '',
                path: target,
                url: target,
                isFolder: false,
              ),
            ),
          );
        }
        return;
      case 'container.update':
        final target = command.argument(0)?.trim();
        if (target != null && target.startsWith('plugin://')) {
          await _runPlugin(sourceAddonId, target, depth: depth + 1);
        }
        return;
      case 'container.refresh':
        return;
      default:
        return;
    }
  }

  Future<void> _runPlugin(
    String sourceAddonId,
    String target, {
    required int depth,
  }) async {
    final result = await _runtime.invokeUrl(target);
    await _processRuntimeResult(sourceAddonId, result, depth: depth);
  }

  Future<void> _runScript(
    String sourceAddonId,
    String addonId,
    List<String> arguments, {
    required int depth,
  }) async {
    final result = await _runtime.invokeScriptAddon(
      addonId,
      arguments: arguments,
    );
    await _processRuntimeResult(sourceAddonId, result, depth: depth);
  }

  Future<void> _processRuntimeResult(
    String sourceAddonId,
    LegacyPluginResult result, {
    required int depth,
  }) async {
    if (!result.succeeded) {
      onMessage(
        '$sourceAddonId: ${result.errorMessage ?? 'falha ao executar addon em segundo plano.'}',
      );
      return;
    }

    final resolved = result.resolvedItem;
    if (resolved != null) {
      await Future<void>.sync(() => onPlayback(resolved));
    }

    for (final raw in result.builtins) {
      await _handleBuiltin(
        sourceAddonId,
        KodiBuiltinCommand.parse(raw),
        depth: depth + 1,
      );
    }
  }

  Future<void> _installAddon(
    String sourceAddonId,
    String rawTargetAddonId,
  ) async {
    final targetAddonId = _normalizeAddonId(rawTargetAddonId);
    if (targetAddonId.isEmpty) {
      onMessage('$sourceAddonId pediu um addon sem identificador válido.');
      return;
    }

    try {
      await repositoryRegistry.initialize();
      await addonInstallController.initialize();

      if (addonInstallController.installedById(targetAddonId) != null) {
        return;
      }

      var candidate = _bestAvailableAddon(targetAddonId);
      if (candidate == null) {
        // Kodi components such as inputstream.adaptive and
        // inputstream.ffmpegdirect live in the official Omega repository, not
        // necessarily in the third-party repository that requested them.
        await repositoryStoreController.ensureKodiSystemCatalog();
        candidate = _bestAvailableAddon(targetAddonId);
      }

      if (candidate == null) {
        await repositoryStoreController.synchronizeAll(
          repositoryRegistry.sources,
        );
        candidate = _bestAvailableAddon(targetAddonId);
      }

      if (candidate == null) {
        onMessage(
          'Addon não encontrado nos repositórios disponíveis: $targetAddonId',
        );
        return;
      }

      final plan = await addonInstallController.install(
        addon: candidate,
        catalogs: repositoryStoreController.catalogs,
      );
      if (!plan.canInstall) {
        final detail = plan.issues.map((issue) => issue.toString()).join('\n');
        onMessage(
          detail.isEmpty
              ? 'Não foi possível instalar $targetAddonId.'
              : 'Não foi possível instalar $targetAddonId:\n$detail',
        );
        return;
      }

      onMessage('${candidate.manifest.name} instalado para $sourceAddonId.');
    } on Object catch (error) {
      onMessage('Falha ao instalar $targetAddonId: $error');
    }
  }

  String _normalizeAddonId(String rawValue) {
    var value = rawValue.trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1).trim();
    }
    value = value.replaceAll('\\', '/');
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    final slash = value.lastIndexOf('/');
    if (slash >= 0) {
      value = value.substring(slash + 1);
    }
    return value.trim();
  }

  RepositoryAddonEntry? _bestAvailableAddon(String addonId) {
    final normalizedId = addonId.toLowerCase();
    RepositoryAddonEntry? selected;
    for (final catalog in repositoryStoreController.catalogs) {
      for (final entry in catalog.addons) {
        if (entry.manifest.id.toLowerCase() != normalizedId ||
            entry.packageUri == null) {
          continue;
        }
        if (selected == null ||
            KodiVersion(entry.manifest.version)
                    .compareTo(KodiVersion(selected.manifest.version)) >
                0) {
          selected = entry;
        }
      }
    }
    return selected;
  }

  Duration _notificationDuration(Object? rawValue) {
    final raw = rawValue is num
        ? rawValue.toInt()
        : int.tryParse(rawValue?.toString() ?? '') ?? 3000;
    final milliseconds = raw < 800
        ? 800
        : raw > 30000
            ? 30000
            : raw;
    return Duration(milliseconds: milliseconds);
  }
}
