import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/runtime/kodi/kodi_core.dart';

class KodiCorePage extends StatefulWidget {
  const KodiCorePage({super.key});
  @override
  State<KodiCorePage> createState() => _KodiCorePageState();
}

class _KodiCorePageState extends State<KodiCorePage>
    with WidgetsBindingObserver {
  Map<String, dynamic>? status;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
    }
  }

  Future<void> refresh() async {
    try {
      final value = await KodiCore.status();
      if (mounted)
        setState(() {
          status = value;
          error = null;
        });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> open({bool test = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await KodiCore.open(selfTest: test);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? report;
    final raw = status?['report'];
    if (raw is String) {
      try {
        report = const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
      } catch (_) {
        report = raw;
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Núcleo Kodi')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Motor Kodi 21.3',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'O núcleo executa os addons e a reprodução por baixo da interface do AddKo. Esta tela mostra a resposta real do motor.',
          ),
          const SizedBox(height: 12),
          Text(
            status == null
                ? 'Verificando biblioteca…'
                : status?['bundled'] == true
                    ? (status?['ready'] == true
                        ? 'Núcleo respondeu: pronto.'
                        : 'Biblioteca presente; aguardando resposta do núcleo.')
                    : 'Biblioteca do Kodi ausente no APK.',
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('COPIAR DIAGNÓSTICO'),
            onPressed: status == null
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(
                        text: const JsonEncoder.withIndent('  ')
                            .convert(status)));
                    if (context.mounted)
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Diagnóstico copiado.')));
                  },
          ),
          FilledButton.icon(
            onPressed: busy ? null : refresh,
            icon: const Icon(Icons.play_circle),
            label: const Text('VERIFICAR ESTADO'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: busy ? null : () => open(test: true),
            icon: const Icon(Icons.fact_check),
            label: const Text('TESTAR NÚCLEO NO APARELHO'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () async {
                    try {
                      await KodiCore.allowLocalFiles();
                    } catch (e) {
                      if (mounted) setState(() => error = e.toString());
                    }
                  },
            icon: const Icon(Icons.folder_open),
            label: const Text('PERMITIR ARQUIVOS LOCAIS'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Para instalar addons, use a Loja do AddKo. Os addons antigos são copiados para o perfil do núcleo. O teste de núcleo confirma APIs e componentes; reprodução e DRM precisam ser testados com mídia.',
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SelectableText(error!),
            ),
          if (status?['error'] != null)
            SelectableText(status!['error'].toString()),
          if (status?['log'] is String)
            ExpansionTile(
                title: const Text('Log do núcleo'),
                children: [SelectableText(status!['log'] as String)]),
          if (report != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SelectableText(report),
            ),
        ],
      ),
    );
  }
}
