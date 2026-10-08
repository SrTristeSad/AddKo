import 'dart:async';

import 'package:flutter/material.dart';

import '../core/addons/application/addon_install_controller.dart';
import '../core/player/playback_host_controller.dart';
import '../core/player/playback_request.dart';
import '../core/repositories/application/repository_registry.dart';
import '../core/repositories/application/repository_store_controller.dart';
import '../core/repositories/infrastructure/shared_preferences_repository_storage.dart';
import '../core/runtime/legacy/legacy_plugin_item.dart';
import '../core/runtime/legacy/legacy_runtime_request.dart';
import '../core/runtime/legacy/legacy_service_supervisor.dart';
import '../features/launcher/launcher_page.dart';
import '../features/legacy/legacy_flutter_ui_bridge.dart';
import '../features/player/player_page.dart';
import 'addko_theme.dart';
import 'legacy_background_host.dart';

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
  late final LegacyBackgroundHost _backgroundHost;
  late final bool _ownsRepositoryRegistry;
  late final bool _ownsRepositoryStoreController;
  late final bool _ownsAddonInstallController;
  late final bool _ownsLegacyServiceSupervisor;

  bool _playerRoutePending = false;

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

    _backgroundHost = LegacyBackgroundHost(
      repositoryRegistry: _repositoryRegistry,
      repositoryStoreController: _repositoryStoreController,
      addonInstallController: _addonInstallController,
      requestHandler: _handleBackgroundRuntimeRequest,
      onMessage: _showMessage,
      onPlayback: _openPlayback,
    );
    _legacyServiceSupervisor.eventHandler = _backgroundHost.handleServiceEvent;

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

  Future<Object?> _handleBackgroundRuntimeRequest(
    LegacyRuntimeRequest request,
  ) async {
    final context = _navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      return request.defaultValue;
    }
    return LegacyFlutterUiBridge.handle(context, request);
  }

  Future<void> _openPlayback(LegacyPluginItem item) async {
    final request = PlaybackRequest.fromLegacyItem(item);
    if (request.uri.trim().isEmpty) {
      return;
    }

    final playbackHost = PlaybackHostController.shared;
    if (playbackHost.isAttached && await playbackHost.open(request)) {
      return;
    }

    if (_playerRoutePending) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      if (playbackHost.isAttached) {
        await playbackHost.open(request);
      }
      return;
    }

    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      debugPrint('AddKo: player requested before navigator became available.');
      return;
    }

    _playerRoutePending = true;
    try {
      await navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PlayerPage(
            request: request,
            playbackHost: playbackHost,
          ),
        ),
      );
    } finally {
      _playerRoutePending = false;
    }
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
      await PlaybackHostController.shared.stop();
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
