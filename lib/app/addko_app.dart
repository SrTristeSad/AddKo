import 'dart:async';

import 'package:flutter/material.dart';

import '../core/addons/application/addon_install_controller.dart';
import '../core/addons/domain/kodi_version.dart';
import '../core/player/playback_request.dart';
import '../core/repositories/application/repository_registry.dart';
import '../core/repositories/application/repository_store_controller.dart';
import '../core/repositories/domain/repository_catalog.dart';
import '../core/repositories/infrastructure/shared_preferences_repository_storage.dart';
import '../core/runtime/legacy/kodi_builtin_command.dart';
import '../core/runtime/legacy/legacy_plugin_item.dart';
import '../core/runtime/legacy/legacy_service_supervisor.dart';
import '../features/launcher/launcher_page.dart';
import '../features/player/player_page.dart';
import 'addko_theme.dart';

class AddKoApp extends StatefulWidget {
  const AddKoApp({
    this.repositoryRegistry,
    this.repositoryStoreController,
    this.addonInstallController,
    this.legacyServiceSupervisor,
    super.key,
  });

  final RepositoryRegistry? repositoryRegistry;
  final RepositoryStoreController? repositoryStoreController;
  final AddonInstallController? addonInstallController;
  final LegacyServiceSupervisor? legacyServiceSupervisor;

  @override
  State<AddKoApp> createState() => _AddKoAppState();
}

class _AddKoAppState extends State<AddKoApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  late final RepositoryRegistry _repositoryRegistry;
  late final RepositoryStoreController _repositoryStoreController;
  late final AddonInstallController _addonInstallController;
  late final LegacyServiceSupervisor _legacyServiceSupervisor;
  late final bool _ownsRepositoryRegistry;
  late final bool _ownsRepositoryStoreController;
  late final bool _ownsAddonInstallController;
  late final bool _ownsLegacyServiceSupervisor;

  @override
  void initState() {
    super.initState();
    _ownsRepositoryRegistry = widget.repositoryRegistry == null;
    _repositoryRegistry = widget.repositoryRegistry ??
        RepositoryRegistry(
          storage: const SharedPreferencesRepositoryStorage(),
        );

    _ownsRepositoryStoreController = widget.repositoryStoreController == null;
    _repositoryStoreController =
        widget.repositoryStoreController ?? RepositoryStoreController();

    _ownsAddonInstallController = widget.addonInstallController == null;
    _addonInstallController =
        widget.addonInstallController ?? AddonInstallController();

    _ownsLegacyServiceSupervisor = widget.legacyServiceSupervisor == null;
    _legacyServiceSupervisor = widget.legacyServiceSupervisor ??
        LegacyServiceSupervisor(
          addonInstallController: _addonInstallController,
        );
    _legacyServiceSupervisor.eventHandler = _handleLegacyServiceEvent;

    if (_ownsRepositoryRegistry) {
      unawaited(_initializeRepositoryRegistry());
    }
    unawaited(_initializeLegacyRuntime());
  }

  Future<void> _initializeRepositoryRegistry() async {
    try {
      await _repositoryRegistry.initialize();
    } catch (error, stackTrace) {
      debugPrint('Failed to initialize repository registry: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _initializeLegacyRuntime() async {
    try {
      await _addonInstallController.initialize();
      await _legacyServiceSupervisor.start();
    } catch (error, stackTrace) {
      debugPrint('Failed to initialize legacy runtime: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _handleLegacyServiceEvent(
    String addonId,
    String method,
    Map<String, Object?> params,
  ) async {
    switch (method) {
      case 'xbmcgui.Dialog.notification':
        final heading = params['heading']?.toString().trim() ?? '';
        final message = params['message']?.toString().trim() ?? '';
        final duration = _clampNotificationDuration(params['time']);
        _showMessage(
          message.isEmpty
              ? (heading.isEmpty ? addonId : heading)
              : heading.isEmpty
                  ? message
                  : '$heading\n$message',
          duration: duration,
        );
        return;
      case 'xbmc.executebuiltin':
        final raw = params['function']?.toString() ?? '';
        await _handleServiceBuiltin(addonId, KodiBuiltinCommand.parse(raw));
        return;
      case 'xbmc.Player.play':
        _openServicePlayback(params);
        return;
      default:
        debugPrint('AddKo service $addonId event not handled yet: $method');
    }
  }

  Future<void> _handleServiceBuiltin(
    String addonId,
    KodiBuiltinCommand command,
  ) async {
    if (command.isEmpty) {
      return;
    }

    switch (command.normalizedName) {
      case 'notification':
        final heading = command.argument(0)?.trim() ?? addonId;
        final message = command.argument(1)?.trim() ?? '';
        _showMessage(
          message.isEmpty ? heading : '$heading\n$message',
          duration: _clampNotificationDuration(command.argument(2)),
        );
        return;
      case 'updateaddonrepos':
        try {
          await _repositoryRegistry.initialize();
          await _repositoryStoreController.synchronizeAll(
            _repositoryRegistry.sources,
          );
          _showMessage('Repositórios atualizados por $addonId.');
        } on Object catch (error) {
          _showMessage('Falha ao atualizar repositórios: $error');
        }
        return;
      case 'updatelocaladdons':
        try {
          await _addonInstallController.refreshInstalled();
          _showMessage('Addons locais atualizados por $addonId.');
        } on Object catch (error) {
          _showMessage('Falha ao atualizar addons locais: $error');
        }
        return;
      case 'installaddon':
        final targetId = command.argument(0)?.trim();
        if (targetId != null && targetId.isNotEmpty) {
          await _installAddonFromService(addonId, targetId);
        }
        return;
      case 'playmedia':
        final target = command.argument(0)?.trim();
        if (target != null && target.isNotEmpty && !target.startsWith('plugin://')) {
          _openPlayback(
            LegacyPluginItem(
              label: command.argument(1)?.trim() ?? '',
              path: target,
              url: target,
              isFolder: false,
            ),
          );
        } else {
          debugPrint('AddKo service $addonId PlayMedia plugin:// pending: $target');
        }
        return;
      default:
        debugPrint(
          'AddKo service $addonId built-in not handled yet: ${command.raw}',
        );
    }
  }

  Future<void> _installAddonFromService(
    String sourceAddonId,
    String targetAddonId,
  ) async {
    try {
      await _repositoryRegistry.initialize();
      await _addonInstallController.initialize();

      var candidate = _bestAvailableAddon(targetAddonId);
      if (candidate == null) {
        await _repositoryStoreController.synchronizeAll(
          _repositoryRegistry.sources,
        );
        candidate = _bestAvailableAddon(targetAddonId);
      }

      if (candidate == null) {
        _showMessage(
          '$sourceAddonId pediu $targetAddonId, mas ele não foi encontrado nos repositórios ativos.',
        );
        return;
      }

      final plan = await _addonInstallController.install(
        addon: candidate,
        catalogs: _repositoryStoreController.catalogs,
      );
      if (!plan.canInstall) {
        final detail = plan.issues.map((issue) => issue.toString()).join('\n');
        _showMessage(
          detail.isEmpty
              ? 'Não foi possível instalar $targetAddonId.'
              : 'Não foi possível instalar $targetAddonId:\n$detail',
        );
        return;
      }

      _showMessage('${candidate.manifest.name} instalado para $sourceAddonId.');
    } on Object catch (error) {
      _showMessage('Falha ao instalar $targetAddonId: $error');
    }
  }

  RepositoryAddonEntry? _bestAvailableAddon(String addonId) {
    RepositoryAddonEntry? selected;
    for (final catalog in _repositoryStoreController.catalogs) {
      for (final entry in catalog.addons) {
        if (entry.manifest.id != addonId || entry.packageUri == null) {
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

  void _openServicePlayback(Map<String, Object?> params) {
    final path = params['path']?.toString() ?? '';
    if (path.trim().isEmpty) {
      return;
    }

    final rawItem = params['item'];
    if (rawItem is Map) {
      final itemJson = Map<String, Object?>.from(rawItem);
      itemJson.putIfAbsent('path', () => path);
      itemJson.putIfAbsent('url', () => path);
      itemJson.putIfAbsent('is_folder', () => false);
      _openPlayback(LegacyPluginItem.fromJson(itemJson));
      return;
    }

    _openPlayback(
      LegacyPluginItem(
        label: '',
        path: path,
        url: path,
        isFolder: false,
      ),
    );
  }

  void _openPlayback(LegacyPluginItem item) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      debugPrint('AddKo: player requested before navigator became available.');
      return;
    }

    final request = PlaybackRequest.fromLegacyItem(item);
    if (request.uri.trim().isEmpty) {
      return;
    }
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PlayerPage(request: request),
        ),
      ),
    );
  }

  Duration _clampNotificationDuration(Object? rawValue) {
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

  void _showMessage(String message, {Duration? duration}) {
    final messenger = _messengerKey.currentState;
    if (messenger == null) {
      debugPrint('AddKo background message: $message');
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration ?? const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _prepareForExit() async {
    try {
      await _legacyServiceSupervisor.shutdown();
    } catch (error, stackTrace) {
      debugPrint('Failed to stop legacy services: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  void dispose() {
    _legacyServiceSupervisor.eventHandler = null;
    if (_ownsLegacyServiceSupervisor) {
      final supervisor = _legacyServiceSupervisor;
      unawaited(
        supervisor.shutdown().whenComplete(supervisor.dispose),
      );
    }
    if (_ownsAddonInstallController) {
      _addonInstallController.dispose();
    }
    if (_ownsRepositoryStoreController) {
      _repositoryStoreController.dispose();
    }
    if (_ownsRepositoryRegistry) {
      _repositoryRegistry.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      title: 'AddKo',
      debugShowCheckedModeBanner: false,
      theme: buildAddKoTheme(),
      home: LauncherPage(
        repositoryRegistry: _repositoryRegistry,
        repositoryStoreController: _repositoryStoreController,
        addonInstallController: _addonInstallController,
        serviceSupervisor: _legacyServiceSupervisor,
        onExitRequested: _prepareForExit,
      ),
    );
  }
}
