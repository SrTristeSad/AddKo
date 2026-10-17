import 'dart:io';

import 'package:addko/src/plugins/plugin_manager.dart';
import 'package:addko/src/plugins/plugin_package.dart';
import 'package:addko/src/runtime/lua_runtime.dart';
import 'package:file_picker/file_picker.dart';
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

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['addko'],
      );
      if (result == null || result.files.isEmpty) return;

      final selected = result.files.single;
      final path = selected.path;
      if (path == null || path.isEmpty) {
        throw StateError(
          'O Android não forneceu um caminho local para o pacote selecionado.',
        );
      }

      setState(() {
        _busy = true;
        _message = 'Validando ${selected.name}...';
      });

      final installed = await manager.installFile(File(path));
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
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _runPlugin(InstalledPlugin plugin) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _message = 'Executando ${plugin.manifest.name}...';
    });

    try {
      final result = await plugin.runEntrypoint();
      if (!mounted) return;
      setState(() {
        _message = result.isEmpty
            ? '${plugin.manifest.name} executou sem retorno.'
            : '${plugin.manifest.name}: $result';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Erro ao executar plugin: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
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
                  'O AddKo agora instala pacotes .addko próprios. '
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
                        label: const Text('Abrir'),
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
