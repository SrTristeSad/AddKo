import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/player/playback_request.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    required this.request,
    super.key,
  });

  final PlaybackRequest request;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  StreamSubscription<String>? _errorSubscription;
  String? _error;
  bool _opening = true;

  @override
  void initState() {
    super.initState();
    _errorSubscription = _player.stream.error.listen((message) {
      if (mounted) {
        setState(() => _error = message);
      }
    });
    unawaited(_open());
  }

  Future<void> _open() async {
    final request = widget.request;
    if (request.uri.trim().isEmpty) {
      setState(() {
        _opening = false;
        _error = 'O addon não forneceu uma URL ou arquivo para reprodução.';
      });
      return;
    }

    if (request.requiresKodiInputStream) {
      setState(() => _opening = false);
      return;
    }

    try {
      await _player.open(
        Media(
          request.uri,
          httpHeaders: request.headers.isEmpty ? null : request.headers,
          extras: {
            if (request.mimeType != null) 'mimeType': request.mimeType,
            if (request.title != null) 'title': request.title,
          },
        ),
        play: true,
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }

  @override
  void dispose() {
    unawaited(_errorSubscription?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(request.title ?? 'Reprodução'),
      ),
      body: request.requiresKodiInputStream
          ? _InputStreamRequired(request: request)
          : Stack(
              fit: StackFit.expand,
              children: [
                Video(
                  controller: _controller,
                  fit: BoxFit.contain,
                ),
                if (_opening)
                  const Center(
                    child: CircularProgressIndicator(),
                  ),
                if (_error case final error?)
                  _PlaybackError(
                    message: error,
                    onRetry: () {
                      setState(() {
                        _error = null;
                        _opening = true;
                      });
                      unawaited(_open());
                    },
                  ),
              ],
            ),
    );
  }
}

class _InputStreamRequired extends StatelessWidget {
  const _InputStreamRequired({required this.request});

  final PlaybackRequest request;

  @override
  Widget build(BuildContext context) {
    final addon = request.inputStreamAddon ?? 'InputStream';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.extension_rounded,
                size: 64,
                color: Colors.white,
              ),
              const SizedBox(height: 18),
              Text(
                'Este vídeo precisa de $addon',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                request.hasDrmConfiguration
                    ? 'O addon forneceu configuração de InputStream/DRM. O AddKo preservou essas propriedades, mas a ABI binária do Kodi ainda precisa ser conectada ao player.'
                    : 'O addon solicitou a camada InputStream do Kodi. A URL foi preservada e será entregue ao Binary Addon Host quando essa camada estiver habilitada.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              if (request.manifestType case final manifest? when manifest.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Manifesto: $manifest',
                  style: const TextStyle(color: Colors.white54),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaybackError extends StatelessWidget {
  const _PlaybackError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 60,
                  color: Colors.white,
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
