import 'dart:async';
import 'dart:io';

import 'package:addko/src/platform/system_file_picker.dart';
import 'package:addko/src/player/addko_video_player.dart';
import 'package:addko/src/plugins/plugin_inspection.dart';
import 'package:addko/src/repositories/addko_repositories.dart';
import 'package:addko/src/plugins/plugin_manager.dart';
import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:addko/src/plugins/plugin_package.dart';
import 'package:addko/src/runtime/lua_plugin_session.dart';
import 'package:addko/src/runtime/lua_runtime.dart';
import 'package:addko/src/runtime/plugin_dependency_host.dart';
import 'package:addko/src/ui/addko_launcher.dart';
import 'package:addko/src/ui/addko_installed_manager.dart';
import 'package:addko/src/ui/addko_repository_store.dart';
import 'package:addko/src/ui/plugin_game_surface.dart';
import 'package:addko/src/ui/plugin_host_dialogs.dart';
import 'package:addko/src/ui/plugin_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final Object _dependencyStackZoneKey = Object();

class AddKoApp extends StatelessWidget {
  const AddKoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AddKo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const _HomePage(),
    );
  }
}

class _HomePage extends StatefulWidget {
  const _HomePage();

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  PluginManager? _manager;
  AddKoRepositoryManager? _repositories;
  List<InstalledPlugin> _plugins = const <InstalledPlugin>[];
  final Map<String, LuaPluginSession> _sessions = <String, LuaPluginSession>{};
  final Map<String, Future<LuaPluginSession>> _openingSessions =
      <String, Future<LuaPluginSession>>{};
  final AddKoVideoPlayer _player = AddKoVideoPlayer();
  String _runtimeStatus = 'Verificando runtime Lua...';
  String? _message;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final runtime = LuaRuntime.open();
      final version = runtime.version;
      final answer = runtime.evaluate('return 6 * 7');
      runtime.dispose();

      final manager = await PluginManager.openDefault();
      final repositories = await AddKoRepositoryManager.openDefault();
      final plugins = await manager.listInstalled();

      if (!mounted) return;
      setState(() {
        _manager = manager;
        _repositories = repositories;
        _plugins = plugins;
        _runtimeStatus = '$version ativo • teste Lua: $answer';
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _runtimeStatus = 'Runtime indisponível: $error';
        _busy = false;
      });
    }
  }

  Future<void> _reloadPlugins() async {
    final manager = _manager;
    if (manager == null) return;
    final plugins = await manager.listInstalled();
    if (!mounted) return;
    setState(() => _plugins = plugins);
  }

  Future<void> _installPackage() async {
    final manager = _manager;
    if (manager == null || _busy) return;

    String? selectedPath;
    try {
      selectedPath = await SystemFilePicker.pickAddko();
      if (selectedPath == null || selectedPath.isEmpty) return;

      setState(() {
        _busy = true;
        _message = 'Inspecionando pacote .addko...';
      });

      final selectedFile = File(selectedPath);
      final preview = await inspectAddkoFile(selectedFile);
      if (!mounted) return;

      final approved = await _confirmInstall(preview);
      if (!approved) {
        if (mounted) {
          setState(() => _message = 'Instalação cancelada.');
        }
        return;
      }

      if (mounted) {
        setState(() => _message = 'Validando e instalando pacote .addko...');
      }

      await _closePluginSession(preview.manifest.id);
      final installed = await manager.installFile(selectedFile);
      await _reloadPlugins();

      if (!mounted) return;
      setState(() {
        _message =
            '${installed.manifest.name} ${installed.manifest.version} instalado.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Falha na instalação: $error');
    } finally {
      if (selectedPath != null) {
        try {
          final selectedFile = File(selectedPath);
          if (await selectedFile.exists()) {
            await selectedFile.delete();
          }
        } on Object {
          // Arquivos de importação ficam no cache; falha na limpeza não bloqueia o app.
        }
      }
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<bool> _confirmInstall(PluginPackagePreview preview) async {
    InstalledPlugin? current;
    for (final plugin in _plugins) {
      if (plugin.manifest.id == preview.manifest.id) {
        current = plugin;
        break;
      }
    }

    final permissions = preview.manifest.permissions.toList()
      ..sort((a, b) => a.wireName.compareTo(b.wireName));
    final dependencies = preview.manifest.dependencies.toList()..sort();
    final installedIds = _plugins.map((plugin) => plugin.manifest.id).toSet();
    final action = current == null ? 'Instalar' : 'Atualizar';

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text('$action ${preview.manifest.name}?'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(preview.manifest.id),
                    const SizedBox(height: 4),
                    Text(preview.manifest.kind == PluginKind.service
                        ? 'Tipo: plugin de serviço (não aparece na tela inicial)'
                        : 'Tipo: aplicativo'),
                    const SizedBox(height: 4),
                    Text(
                      current == null
                          ? 'Versão ${preview.manifest.version}'
                          : 'Versão ${current.manifest.version} → ${preview.manifest.version}',
                    ),
                    const SizedBox(height: 20),
                    Text(
                      permissions.isEmpty
                          ? 'Este mini-app não solicita permissões especiais.'
                          : 'Permissões solicitadas:',
                      style: Theme.of(dialogContext).textTheme.titleSmall,
                    ),
                    if (permissions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      for (final permission in permissions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(Icons.security_rounded, size: 18),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_permissionTitle(permission)),
                                    const SizedBox(height: 2),
                                    Text(
                                      _permissionDescription(permission),
                                      style: Theme.of(dialogContext)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    if (dependencies.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Dependências de mini-app:',
                        style: Theme.of(dialogContext).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      for (final dependency in dependencies)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Icon(
                                installedIds.contains(dependency)
                                    ? Icons.check_circle_outline_rounded
                                    : Icons.error_outline_rounded,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(dependency)),
                              Text(
                                installedIds.contains(dependency)
                                    ? 'instalado'
                                    : 'ausente',
                                style: Theme.of(dialogContext).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'O AddKo só libera essas capacidades dentro do sandbox do mini-app.',
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(action),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<void> _runPlugin(InstalledPlugin plugin) async {
    if (_busy) return;
    if (plugin.manifest.kind == PluginKind.service) {
      setState(() => _message =
          '${plugin.manifest.name} é um serviço usado por outros addons.');
      return;
    }

    final missing = _missingDependencies(plugin);
    if (missing.isNotEmpty) {
      final warning =
          'Não é possível abrir ${plugin.manifest.name}: dependências ausentes: '
          '${missing.join(', ')}.';
      setState(() => _message = warning);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(warning)));
      return;
    }

    setState(() {
      _busy = true;
      _message = 'Iniciando ${plugin.manifest.name}...';
    });

    LuaPluginSession? pendingSession;
    try {
      await _closePluginSession(plugin.manifest.id);
      pendingSession = await _createPluginSession(plugin);
      final result = await pendingSession.start();
      final document = PluginUiDocument.tryParse(result);
      final game = document == null ? PluginGameConfig.tryParse(result) : null;

      _sessions[plugin.manifest.id] = pendingSession;
      final session = pendingSession;
      pendingSession = null;

      if (!mounted) return;
      setState(() {
        _message = document != null || game != null
            ? '${plugin.manifest.name} aberto.'
            : '${plugin.manifest.name}: $result';
        _busy = false;
      });

      var openedExperience = false;
      if (document != null) {
        openedExperience = true;
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (context) => PluginUiPage(
              initialDocument: document,
              allowNetworkImages: plugin.manifest.permissions
                  .contains(PluginPermission.network),
              pluginRoot: plugin.directory.path,
              onAction: session.call,
            ),
          ),
        );
      } else if (game != null) {
        openedExperience = true;
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (context) => PluginGamePage(
              config: game,
              pluginRoot: plugin.directory.path,
              onAction: session.call,
            ),
          ),
        );
      }

      if (openedExperience &&
          !plugin.manifest.permissions.contains(PluginPermission.background)) {
        await _closePluginSession(plugin.manifest.id);
        if (mounted) setState(() {});
      }
    } on Object catch (error) {
      if (pendingSession != null) {
        await pendingSession.close();
      }
      if (!mounted) return;
      setState(() => _message = 'Erro ao iniciar plugin: $error');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Não foi possível abrir o addon: $error'),
        ));
    } finally {
      if (mounted && _busy) {
        setState(() => _busy = false);
      }
    }
  }

  Future<LuaPluginSession> _createPluginSession(InstalledPlugin plugin) {
    return plugin.openSession(
      player: _player,
      uiHandler: (operation, arguments) => handlePluginHostUi(
        context,
        operation,
        arguments,
        player: _player,
      ),
      dependencyCaller: _dependencyCallerFor(plugin),
    );
  }

  PluginDependencyCaller _dependencyCallerFor(InstalledPlugin caller) {
    return (targetPluginId, method, arguments) {
      return _callPluginDependency(
        caller,
        targetPluginId,
        method,
        arguments,
      );
    };
  }

  Future<Object?> _callPluginDependency(
    InstalledPlugin caller,
    String targetPluginId,
    String method,
    Object? arguments,
  ) {
    final inherited =
        Zone.current[_dependencyStackZoneKey] as List<String>? ??
            <String>[caller.manifest.id];
    if (inherited.contains(targetPluginId)) {
      final cycle = <String>[...inherited, targetPluginId].join(' → ');
      throw StateError('Dependência cíclica entre mini-apps: $cycle');
    }

    final stack = List<String>.unmodifiable(<String>[
      ...inherited,
      targetPluginId,
    ]);

    return runZoned<Future<Object?>>(
      () async {
        final target = _findPlugin(targetPluginId);
        if (target == null) {
          throw StateError(
            'Dependência ${caller.manifest.id} → $targetPluginId não está instalada.',
          );
        }

        final missing = _missingDependencies(target);
        if (missing.isNotEmpty) {
          throw StateError(
            'Dependência $targetPluginId também depende de: ${missing.join(', ')}.',
          );
        }

        final session = await _ensureServiceSession(target);
        return session.call('service', <Object?>[method, arguments]);
      },
      zoneValues: <Object, Object?>{
        _dependencyStackZoneKey: stack,
      },
    );
  }

  Future<LuaPluginSession> _ensureServiceSession(InstalledPlugin plugin) async {
    final existing = _sessions[plugin.manifest.id];
    if (existing != null) return existing;

    final opening = _openingSessions[plugin.manifest.id];
    if (opening != null) return opening;

    final future = () async {
      LuaPluginSession? session;
      try {
        session = await _createPluginSession(plugin);
        await session.start();
        _sessions[plugin.manifest.id] = session;
        return session;
      } on Object {
        if (session != null) {
          await session.close();
        }
        rethrow;
      }
    }();

    _openingSessions[plugin.manifest.id] = future;
    try {
      return await future;
    } finally {
      _openingSessions.remove(plugin.manifest.id);
    }
  }

  InstalledPlugin? _findPlugin(String id) {
    for (final plugin in _plugins) {
      if (plugin.manifest.id == id) return plugin;
    }
    return null;
  }

  List<String> _missingDependencies(InstalledPlugin plugin) {
    final installed = _plugins.map((item) => item.manifest.id).toSet();
    final missing = plugin.manifest.dependencies
        .where((dependency) => !installed.contains(dependency))
        .toList()
      ..sort();
    return missing;
  }

  Future<void> _closePluginSession(String pluginId) async {
    final session = _sessions.remove(pluginId);
    if (session == null) return;
    try {
      await session.stop();
    } on Object {
      // Fecha o estado Lua mesmo quando o hook stop do plugin falha.
    }
    await session.close();
  }

  Future<bool> _installRepositoryAddon(RepositoryAddon addon) async {
    final manager = _manager;
    final repositories = _repositories;
    if (manager == null || repositories == null || _busy) {
      throw StateError('Instalador ainda não está disponível.');
    }
    setState(() {
      _busy = true;
      _message = 'Baixando pacote do repositório...';
    });
    try {
      final bytes = await repositories.download(addon);
      // The checksum is validated before any ZIP parsing or permission prompt.
      final preview = inspectAddkoBytes(bytes);
      if (preview.manifest.id != addon.id ||
          preview.manifest.name != addon.name ||
          preview.manifest.version != addon.version) {
        throw const RepositoryException(
          'O manifesto do pacote não corresponde ao catálogo. Instalação bloqueada.',
        );
      }
      if (!mounted) return false;
      final approved = await _confirmInstall(preview);
      if (!approved) return false;
      await _closePluginSession(addon.id);
      final installed = await manager.installBytes(bytes);
      await _reloadPlugins();
      if (mounted) {
        setState(() {
          _message = '${installed.manifest.name} instalado pelo repositório.';
        });
      }
      return true;
    } on Object catch (error) {
      if (mounted) {
        setState(() => _message = 'Falha na instalação: $error');
      }
      rethrow;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openStore() async {
    final repositories = _repositories;
    if (repositories == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AddKoRepositoryStore(
          repositories: repositories,
          installedVersions: <String, String>{
            for (final plugin in _plugins)
              plugin.manifest.id: plugin.manifest.version,
          },
          busy: _busy,
          onInstallPackage: () => unawaited(_installPackage()),
          onInstallAddon: _installRepositoryAddon,
        ),
      ),
    );
    await _reloadPlugins();
  }


  Future<List<InstalledPlugin>> _reloadManagedPlugins() async {
    await _reloadPlugins();
    return _plugins;
  }

  Future<void> _uninstallManagedPlugin(
    InstalledPlugin plugin,
    bool eraseData,
  ) async {
    final manager = _manager;
    if (manager == null || _busy) {
      throw StateError('Gerenciador de addons indisponível.');
    }
    final dependents = await manager.dependentsOf(plugin.manifest.id);
    if (dependents.isNotEmpty) {
      throw StateError(
        'Addon necessário para: '
        '${dependents.map((item) => item.manifest.name).join(', ')}.',
      );
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await _closePluginSession(plugin.manifest.id);
      await manager.uninstall(plugin.manifest.id, deleteData: eraseData);
      if (mounted) {
        setState(() => _message = '${plugin.manifest.name} desinstalado.');
      }
    } finally {
      await _reloadPlugins();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openInstalledManager() {
    final repositories = _repositories;
    if (repositories == null || _manager == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AddKoInstalledManager(
          installed: _plugins,
          repositories: repositories,
          onRemove: _uninstallManagedPlugin,
          onReload: _reloadManagedPlugins,
          onOpenStore: _openStore,
        ),
      ),
    );
  }

  void _openSettings() {
    final status = _message == null
        ? _runtimeStatus
        : '$_runtimeStatus\nÚltima atividade: $_message';
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AddKoSettingsShell(
          runtimeStatus: status,
          busy: _busy,
          onInstallPackage: () => unawaited(_installPackage()),
          onManageAddons: _openInstalledManager,
        ),
      ),
    );
  }

  Future<void> _exitApp() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await SystemNavigator.pop();
      return;
    }
    exit(0);
  }

  @override
  void dispose() {
    for (final session in _sessions.values) {
      unawaited(
        session.stop().catchError((_) => null).whenComplete(session.close),
      );
    }
    _sessions.clear();
    unawaited(_player.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AddKoLauncher(
      plugins: _plugins,
      busy: _busy,
      activePluginIds: _sessions.keys.toSet(),
      onOpenPlugin: (plugin) => unawaited(_runPlugin(plugin)),
      onOpenStore: _openStore,
      onOpenSettings: _openSettings,
      onExit: () => unawaited(_exitApp()),
    );
  }
}

String _permissionTitle(PluginPermission permission) {
  return switch (permission) {
    PluginPermission.network => 'Rede',
    PluginPermission.storage => 'Armazenamento',
    PluginPermission.media => 'Mídia',
    PluginPermission.background => 'Segundo plano',
    PluginPermission.nativeEngine => 'Motor nativo aprovado',
  };
}

String _permissionDescription(PluginPermission permission) {
  return switch (permission) {
    PluginPermission.network =>
      'Pode fazer requisições HTTP/HTTPS e, quando combinado com segundo plano, usar serviços TCP locais.',
    PluginPermission.storage =>
      'Pode ler os próprios arquivos e gravar somente no diretório privado de dados do mini-app.',
    PluginPermission.media =>
      'Pode solicitar recursos de reprodução de mídia quando o host oferecer essa capacidade.',
    PluginPermission.background =>
      'Pode manter serviços e tarefas de longa duração enquanto a sessão do mini-app estiver ativa.',
    PluginPermission.nativeEngine =>
      'Pode iniciar motores nativos aprovados que já vêm assinados no APK do AddKo. Não permite carregar bibliotecas externas.',
  };
}
