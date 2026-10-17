import 'dart:async';
import 'dart:io';

import 'package:addko/src/platform/system_file_picker.dart';
import 'package:addko/src/player/addko_video_player.dart';
import 'package:addko/src/plugins/plugin_inspection.dart';
import 'package:addko/src/plugins/plugin_manager.dart';
import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:addko/src/plugins/plugin_package.dart';
import 'package:addko/src/runtime/lua_plugin_session.dart';
import 'package:addko/src/runtime/lua_runtime.dart';
import 'package:addko/src/ui/plugin_host_dialogs.dart';
import 'package:addko/src/ui/plugin_ui.dart';
import 'package:flutter/material.dart';

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
  List<InstalledPlugin> _plugins = const <InstalledPlugin>[];
  final Map<String, LuaPluginSession> _sessions = <String, LuaPluginSession>{};
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
      final plugins = await manager.listInstalled();

      if (!mounted) return;
      setState(() {
        _manager = manager;
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

    setState(() {
      _busy = true;
      _message = 'Iniciando ${plugin.manifest.name}...';
    });

    LuaPluginSession? pendingSession;
    try {
      await _closePluginSession(plugin.manifest.id);
      pendingSession = await plugin.openSession(
        player: _player,
        uiHandler: (operation, arguments) => handlePluginHostUi(
          context,
          operation,
          arguments,
          player: _player,
        ),
      );
      final result = await pendingSession.start();
      final document = PluginUiDocument.tryParse(result);

      _sessions[plugin.manifest.id] = pendingSession;
      final session = pendingSession;
      pendingSession = null;

      if (!mounted) return;
      setState(() {
        _message = document == null
            ? '${plugin.manifest.name}: $result'
            : '${plugin.manifest.name} aberto.';
        _busy = false;
      });

      if (document != null) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (context) => PluginUiPage(
              initialDocument: document,
              allowNetworkImages: plugin.manifest.permissions
                  .contains(PluginPermission.network),
              onAction: session.call,
            ),
          ),
        );

        if (!plugin.manifest.permissions.contains(PluginPermission.background)) {
          await _closePluginSession(plugin.manifest.id);
          if (mounted) setState(() {});
        }
      }
    } on Object catch (error) {
      if (pendingSession != null) {
        await pendingSession.close();
      }
      if (!mounted) return;
      setState(() => _message = 'Erro ao iniciar plugin: $error');
    } finally {
      if (mounted && _busy) {
        setState(() => _busy = false);
      }
    }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('AddKo'),
        actions: [
          IconButton(
            tooltip: 'Instalar .addko',
            onPressed: _busy ? null : _installPackage,
            icon: const Icon(Icons.add_box_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Mini-apps Lua',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'O AddKo instala pacotes .addko próprios com runtime Lua persistente. '
                  'Kodi e Python não fazem parte deste runtime.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.memory_rounded),
                    title: const Text('Runtime'),
                    subtitle: Text(_runtimeStatus),
                  ),
                ),
                AddKoVideoSurface(player: _player),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _installPackage,
                  icon: const Icon(Icons.install_mobile_rounded),
                  label: const Text('Instalar pacote .addko'),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_message!),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Instalados',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (_busy)
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!_busy && _plugins.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Nenhum mini-app instalado. Escolha um arquivo .addko para começar.',
                      ),
                    ),
                  ),
                for (final plugin in _plugins)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.extension_rounded),
                      title: Text(plugin.manifest.name),
                      subtitle: Text(
                        '${plugin.manifest.id} • ${plugin.manifest.version}',
                      ),
                      trailing: FilledButton.tonalIcon(
                        onPressed: _busy ? null : () => _runPlugin(plugin),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(
                          _sessions.containsKey(plugin.manifest.id)
                              ? 'Reiniciar'
                              : 'Abrir',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _permissionTitle(PluginPermission permission) {
  return switch (permission) {
    PluginPermission.network => 'Rede',
    PluginPermission.storage => 'Armazenamento',
    PluginPermission.media => 'Mídia',
    PluginPermission.background => 'Segundo plano',
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
  };
}
