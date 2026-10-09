import '../kodi/kodi_core_page.dart';
import '../../core/runtime/kodi/kodi_core.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/addons/domain/kodi_host_capabilities.dart';
import '../../core/runtime/legacy/android_python_runtime.dart';
import '../../core/runtime/legacy/embedded_python_host.dart';
import '../../core/runtime/legacy/embedded_python_self_test.dart';

class CompatibilityPage extends StatefulWidget {
  const CompatibilityPage({super.key});
  @override
  State<CompatibilityPage> createState() => _State();
}

class _State extends State<CompatibilityPage> {
  EmbeddedPythonProbe probe = EmbeddedPythonProbe.read();
  AndroidPythonRuntimeInfo? runtime;
  EmbeddedPythonSelfTestResult? test;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid && !KodiCore.supported) unawaited(_prepare());
  }

  Future<void> _prepare() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      runtime = await AndroidPythonRuntime.prepare();
      probe = EmbeddedPythonProbe.read();
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _run() async {
    setState(() => busy = true);
    test = await runEmbeddedPythonSelfTest();
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext c) => KodiCore.supported
      ? const KodiCorePage()
      : Scaffold(
          appBar: AppBar(title: const Text('Compatibilidade Kodi')),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _card(
                c,
                'Host nativo do Python',
                probe.hostLibraryLoaded,
                probe.hostLibraryLoaded
                    ? 'libaddko_python_host carregada.'
                    : 'Biblioteca nativa indisponível.',
              ),
              if (Platform.isAndroid)
                _card(
                  c,
                  'Runtime Android extraído',
                  runtime != null,
                  runtime == null
                      ? (error ?? 'Preparando...')
                      : 'Python ${runtime!.version} • ${runtime!.abi}',
                ),
              _card(
                c,
                'CPython embarcado',
                probe.pythonLibraryLoaded,
                probe.pythonLibraryLoaded
                    ? probe.version
                    : 'libpython não encontrada.',
              ),
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Núcleo Kodi 21 (Omega)',
                        style: Theme.of(c).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      for (final e in KodiHostCapabilities.versions.entries)
                        Text('${e.key} • ${e.value}'),
                    ],
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  title: const Text('Teste real do runtime'),
                  subtitle: Text(
                    test == null
                        ? 'Importa módulos padrão do CPython.'
                        : '${test!.passed ? 'OK' : 'FALHOU'} • ${test!.message}',
                  ),
                  trailing: FilledButton(
                    onPressed: busy ? null : () => unawaited(_run()),
                    child: const Text('TESTAR'),
                  ),
                ),
              ),
            ],
          ),
        );
  Widget _card(BuildContext c, String t, bool ok, String d) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      leading: Icon(
        ok ? Icons.check_circle : Icons.info_outline,
        color: ok ? Theme.of(c).colorScheme.primary : null,
      ),
      title: Text(t),
      subtitle: Text(d),
    ),
  );
}
