import 'package:addko/src/runtime/lua_runtime.dart';
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
  String _status = 'Verificando runtime Lua...';

  @override
  void initState() {
    super.initState();
    _probeLua();
  }

  void _probeLua() {
    try {
      final runtime = LuaRuntime.open();
      final version = runtime.version;
      final answer = runtime.evaluate('return 6 * 7');
      runtime.dispose();
      setState(() {
        _status = '$version ativo • teste Lua: $answer';
      });
    } catch (error) {
      setState(() {
        _status = 'Runtime ainda indisponível nesta plataforma: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.extension_rounded, size: 72),
                  const SizedBox(height: 24),
                  Text(
                    'AddKo',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Nova base: Flutter + Lua. Sem Kodi. Sem Python.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 32),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          const Icon(Icons.memory_rounded),
                          const SizedBox(width: 16),
                          Expanded(child: Text(_status)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
