import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/runtime/kodi/kodi_core.dart';

/// Transparent Flutter controls over the native Kodi renderer, including InputStream.
class NativePlayerPage extends StatefulWidget {
  const NativePlayerPage({required this.url, required this.title, super.key});
  final String url, title;
  @override
  State<NativePlayerPage> createState() => _NativePlayerPageState();
}

class _NativePlayerPageState extends State<NativePlayerPage> {
  Timer? _timer;
  int? _player;
  String? _error;
  bool _starting = true, _polling = false;
  String _time = '';
  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await KodiCore.rpc('Player.Open', {
        'item': {'file': widget.url},
        'options': {'resume': false}
      });
      if (!mounted) return;
      _timer =
          Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_poll()));
      await _poll();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      final players = await KodiCore.rpc('Player.GetActivePlayers') as List;
      if (players.isNotEmpty) {
        final id = (players.first as Map)['playerid'] as int;
        final props = await KodiCore.rpc('Player.GetProperties', {
          'playerid': id,
          'properties': ['time', 'totaltime', 'speed']
        }) as Map;
        final t = props['time'] as Map;
        if (mounted)
          setState(() {
            _player = id;
            _time =
                '${t['hours']}:${t['minutes'].toString().padLeft(2, '0')}:${t['seconds'].toString().padLeft(2, '0')}';
          });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      _polling = false;
    }
  }

  Future<void> _control(String method,
      [Map<String, dynamic> params = const {}]) async {
    if (_player == null) return;
    try {
      await KodiCore.rpc(method, {'playerid': _player, ...params});
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_player != null)
      unawaited(KodiCore.rpc('Player.Stop', {'playerid': _player})
          .catchError((_) => null));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
            backgroundColor: Colors.black54,
            foregroundColor: Colors.white,
            title: Text(widget.title)),
        body: Stack(children: [
          if (_starting) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Center(
                child: Container(
                    color: Colors.black87,
                    padding: const EdgeInsets.all(24),
                    child: SelectableText(_error!,
                        style: const TextStyle(color: Colors.white)))),
          Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                  color: Colors.black54,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                            color: Colors.white,
                            tooltip: 'Voltar 30 segundos',
                            onPressed: () => _control('Player.Seek', {
                                  'value': {'seconds': -30}
                                }),
                            icon: const Icon(Icons.replay_30)),
                        IconButton(
                            color: Colors.white,
                            tooltip: 'Pausar ou continuar',
                            onPressed: () => _control('Player.PlayPause'),
                            icon: const Icon(Icons.pause_circle)),
                        IconButton(
                            color: Colors.white,
                            tooltip: 'Avançar 30 segundos',
                            onPressed: () => _control('Player.Seek', {
                                  'value': {'seconds': 30}
                                }),
                            icon: const Icon(Icons.forward_30)),
                        Text(_time,
                            style: const TextStyle(color: Colors.white)),
                      ]))),
        ]),
      );
}
