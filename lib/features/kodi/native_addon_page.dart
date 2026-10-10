import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/addons/domain/installed_addon.dart';
import '../../core/runtime/kodi/kodi_core.dart';
import '../../core/ui/kodi_text.dart';
import 'native_player_page.dart';

/// Lists returned by Kodi's real PluginDirectory are drawn by AddKo.
class NativeAddonPage extends StatefulWidget {
  const NativeAddonPage({required this.addon, super.key});
  final InstalledAddon addon;
  @override
  State<NativeAddonPage> createState() => _NativeAddonPageState();
}

class _NativeAddonPageState extends State<NativeAddonPage> {
  final List<String> _history = [];
  List<Map<String, dynamic>> _items = [];
  String? _error;
  String _url = '';
  bool _busy = true;
  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await KodiCore.prepareAddon(widget.addon.manifest.id);
      await _load('plugin://${widget.addon.manifest.id}/');
    } catch (e) {
      if (mounted)
        setState(() {
          _busy = false;
          _error = e.toString();
        });
    }
  }

  Future<void> _load(String url, {bool remember = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final items = await KodiCore.directory(url);
      if (!mounted) return;
      setState(() {
        if (remember) _history.add(_url);
        _url = url;
        _items = items;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select(Map<String, dynamic> item) async {
    final path = item['file']?.toString() ?? '';
    if (path.isEmpty) return;
    if (item['filetype'] == 'directory') {
      await _load(path, remember: true);
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => NativePlayerPage(
            url: path, title: item['label']?.toString() ?? 'Reprodução')));
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _history.isEmpty,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && !_busy && _history.isNotEmpty)
            unawaited(_load(_history.removeLast()));
        },
        child: Scaffold(
          appBar: AppBar(title: Text(widget.addon.manifest.name), actions: [
            IconButton(
              tooltip: 'Configurações do addon',
              icon: const Icon(Icons.settings),
              onPressed: _busy
                  ? null
                  : () async {
                      try {
                        await KodiCore.rpc('Addons.ExecuteAddon', {
                          'addonid': 'script.addko.bridge',
                          'params': ['settings', widget.addon.manifest.id],
                        });
                      } catch (e) {
                        if (mounted) setState(() => _error = e.toString());
                      }
                    },
            ),
            IconButton(
                tooltip: 'Atualizar',
                onPressed:
                    _busy ? null : () => _url.isEmpty ? _start() : _load(_url),
                icon: const Icon(Icons.refresh)),
          ]),
          body: _busy
              ? const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Executando no núcleo…')
                ]))
              : _error != null
                  ? Center(
                      child: Padding(
                          padding: const EdgeInsets.all(24),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            SelectableText(_error!),
                            const SizedBox(height: 16),
                            FilledButton(
                                onPressed: _start,
                                child: const Text('TENTAR NOVAMENTE'))
                          ])))
                  : _items.isEmpty
                      ? const Center(
                          child: Text('O addon retornou uma lista vazia.'))
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return ListTile(
                                leading: Icon(item['filetype'] == 'directory'
                                    ? Icons.folder
                                    : Icons.play_arrow),
                                title:
                                    KodiText(item['label']?.toString() ?? ''),
                                subtitle: Text(item['plot']?.toString() ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                onTap: () => _select(item));
                          }),
        ),
      );
}
