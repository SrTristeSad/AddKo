import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/addons/domain/installed_addon.dart';
import '../../core/player/playback_request.dart';
import '../../core/runtime/legacy/legacy_plugin_item.dart';
import '../../core/runtime/legacy/legacy_plugin_result.dart';
import '../../core/runtime/legacy/legacy_plugin_runtime.dart';
import '../player/player_page.dart';

class LegacyAddonPage extends StatefulWidget {
  const LegacyAddonPage({
    required this.addon,
    required this.runtime,
    super.key,
  });

  final InstalledAddon addon;
  final LegacyPluginRuntime runtime;

  @override
  State<LegacyAddonPage> createState() => _LegacyAddonPageState();
}

class _LegacyAddonPageState extends State<LegacyAddonPage> {
  final List<String> _history = [];

  LegacyPluginResult? _result;
  String? _currentUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_open('plugin://${widget.addon.manifest.id}/', pushHistory: false));
  }

  Future<void> _open(String url, {bool pushHistory = true}) async {
    if (_loading && _currentUrl == url) {
      return;
    }

    final previousUrl = _currentUrl;
    setState(() {
      _loading = true;
      _currentUrl = url;
    });

    final result = await widget.runtime.invokeUrl(url);
    if (!mounted) {
      return;
    }

    if (pushHistory && previousUrl != null && result.succeeded) {
      _history.add(previousUrl);
    }

    setState(() {
      _loading = false;
      _result = result;
    });

    final resolved = result.resolvedItem;
    if (resolved != null && result.succeeded) {
      _openPlayback(resolved);
    }
  }

  Future<bool> _goBack() async {
    if (_history.isEmpty) {
      return true;
    }
    final previous = _history.removeLast();
    await _open(previous, pushHistory: false);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final title = result?.category?.trim().isNotEmpty == true
        ? '${widget.addon.manifest.name} • ${result!.category}'
        : widget.addon.manifest.name;

    return PopScope(
      canPop: _history.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _history.isNotEmpty) {
          unawaited(_goBack());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Voltar',
            onPressed: () async {
              if (await _goBack() && context.mounted) {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(title),
          actions: [
            IconButton(
              tooltip: 'Atualizar',
              onPressed: _currentUrl == null || _loading
                  ? null
                  : () => unawaited(_open(_currentUrl!, pushHistory: false)),
              icon: const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: _body(result),
      ),
    );
  }

  Widget _body(LegacyPluginResult? result) {
    if (_loading && result == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (result == null) {
      return const Center(child: Text('O addon não retornou conteúdo.'));
    }

    if (!result.succeeded) {
      return _RuntimeError(
        message: result.errorMessage ?? 'Falha desconhecida ao executar o addon.',
        logs: result.logs,
        onRetry: _currentUrl == null
            ? null
            : () => unawaited(_open(_currentUrl!, pushHistory: false)),
      );
    }

    if (result.items.isEmpty) {
      return Stack(
        children: [
          const Center(child: Text('O addon não adicionou itens a esta pasta.')),
          if (_loading) const LinearProgressIndicator(),
        ],
      );
    }

    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
          itemCount: result.items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = result.items[index];
            return _LegacyItemTile(
              item: item,
              onTap: () => _activate(item),
            );
          },
        ),
        if (_loading) const LinearProgressIndicator(),
      ],
    );
  }

  void _activate(LegacyPluginItem item) {
    final target = item.url.isNotEmpty ? item.url : item.path;
    if (target.startsWith('plugin://')) {
      unawaited(_open(target));
      return;
    }

    if (item.isFolder) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Caminho de pasta ainda não suportado: $target')),
      );
      return;
    }

    _openPlayback(item);
  }

  void _openPlayback(LegacyPluginItem item) {
    final request = PlaybackRequest.fromLegacyItem(item);
    if (request.uri.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O addon não informou um caminho de mídia.'),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerPage(request: request),
      ),
    );
  }
}

class _LegacyItemTile extends StatelessWidget {
  const _LegacyItemTile({
    required this.item,
    required this.onTap,
  });

  final LegacyPluginItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final artwork = item.art['thumb'] ??
        item.art['icon'] ??
        item.art['poster'] ??
        item.art['fanart'];

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      leading: SizedBox.square(
        dimension: 52,
        child: _Artwork(
          url: artwork,
          fallback: item.isFolder
              ? Icons.folder_rounded
              : Icons.play_circle_outline_rounded,
        ),
      ),
      title: Text(
        item.label.isEmpty ? '(sem nome)' : item.label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: item.label2.isEmpty
          ? null
          : Text(
              item.label2,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: Icon(
        item.isFolder ? Icons.chevron_right_rounded : Icons.play_arrow_rounded,
      ),
      onTap: onTap,
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.url, required this.fallback});

  final String? url;
  final IconData fallback;

  @override
  Widget build(BuildContext context) {
    final value = url?.trim();
    if (value == null || value.isEmpty) {
      return Icon(fallback, size: 38);
    }

    final uri = Uri.tryParse(value);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          value,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(fallback, size: 38),
        ),
      );
    }

    return Icon(fallback, size: 38);
  }
}

class _RuntimeError extends StatelessWidget {
  const _RuntimeError({
    required this.message,
    required this.logs,
    required this.onRetry,
  });

  final String message;
  final List<String> logs;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 58,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (logs.isNotEmpty) ...[
                const SizedBox(height: 18),
                ExpansionTile(
                  title: const Text('Log do addon'),
                  children: [
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 260),
                      padding: const EdgeInsets.all(12),
                      child: SingleChildScrollView(
                        child: SelectableText(logs.join('\n')),
                      ),
                    ),
                  ],
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
