import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/runtime/legacy/android_python_runtime.dart';
import '../../core/runtime/legacy/embedded_python_host.dart';

class CompatibilityPage extends StatefulWidget {
  const CompatibilityPage({super.key});

  @override
  State<CompatibilityPage> createState() => _CompatibilityPageState();
}

class _CompatibilityPageState extends State<CompatibilityPage> {
  EmbeddedPythonProbe _probe = EmbeddedPythonProbe.read();
  AndroidPythonRuntimeInfo? _androidRuntime;
  String? _prepareError;
  bool _preparing = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      unawaited(_prepareAndroidRuntime());
    }
  }

  Future<void> _prepareAndroidRuntime() async {
    if (_preparing) return;
    setState(() {
      _preparing = true;
      _prepareError = null;
    });
    try {
      final info = await AndroidPythonRuntime.prepare();
      if (!mounted) return;
      setState(() {
        _androidRuntime = info;
        _probe = EmbeddedPythonProbe.read();
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _prepareError = error.toString());
    } finally {
      if (mounted) {
        setState(() => _preparing = false);
      }
    }
  }

  Future<void> _refresh() async {
    if (Platform.isAndroid) {
      await _prepareAndroidRuntime();
    }
    if (!mounted) return;
    setState(() => _probe = EmbeddedPythonProbe.read());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compatibilidade Kodi'),
        actions: [
          IconButton(
            tooltip: 'Verificar novamente',
            onPressed: _preparing ? null : () => unawaited(_refresh()),
            icon: _preparing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _StatusCard(
            icon: Icons.memory_rounded,
            title: 'Host nativo do Python',
            ok: _probe.hostLibraryLoaded,
            detail: _probe.hostLibraryLoaded
                ? 'libaddko_python_host carregada.'
                : 'A biblioteca nativa ainda não está disponível nesta plataforma/build.',
          ),
          if (Platform.isAndroid)
            _StatusCard(
              icon: Icons.folder_zip_rounded,
              title: 'Runtime Android extraído',
              ok: _androidRuntime != null,
              neutralWhenFalse: _preparing,
              detail: _androidRuntime != null
                  ? 'Python ${_androidRuntime!.version} • ${_androidRuntime!.abi}\n${_androidRuntime!.home}'
                  : _preparing
                      ? 'Preparando a biblioteca padrão do CPython...'
                      : (_prepareError ?? 'Runtime ainda não preparado.'),
            ),
          _StatusCard(
            icon: Icons.code_rounded,
            title: 'CPython embarcado',
            ok: _probe.pythonLibraryLoaded,
            detail: _probe.pythonLibraryLoaded
                ? (_probe.version.isEmpty ? 'CPython encontrado.' : _probe.version)
                : 'libpython não foi encontrada para a ABI atual.',
          ),
          _StatusCard(
            icon: Icons.play_circle_outline_rounded,
            title: 'Runtime inicializado',
            ok: _probe.initialized,
            neutralWhenFalse: true,
            detail: _probe.initialized
                ? 'O interpretador está ativo${_probe.home.isEmpty ? '.' : ' em ${_probe.home}.'}'
                : 'O interpretador será inicializado no primeiro addon executado.',
          ),
          if (_probe.error.trim().isNotEmpty)
            Card(
              margin: const EdgeInsets.only(top: 6),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SelectableText(
                        _probe.error,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.ok,
    required this.detail,
    this.neutralWhenFalse = false,
  });

  final IconData icon;
  final String title;
  final bool ok;
  final String detail;
  final bool neutralWhenFalse;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = ok
        ? scheme.primary
        : neutralWhenFalse
            ? scheme.onSurfaceVariant
            : scheme.error;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.12),
          child: Icon(icon, color: statusColor),
        ),
        title: Text(title),
        subtitle: Text(detail),
        trailing: Icon(
          ok
              ? Icons.check_circle_rounded
              : neutralWhenFalse
                  ? Icons.schedule_rounded
                  : Icons.error_outline_rounded,
          color: statusColor,
        ),
      ),
    );
  }
}
