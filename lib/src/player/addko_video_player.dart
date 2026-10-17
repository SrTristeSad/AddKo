import 'package:addko/src/runtime/plugin_player.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class AddKoVideoPlayer extends ChangeNotifier implements PluginPlayer {
  VideoPlayerController? _controller;
  String _currentUrl = '';
  bool _closed = false;
  bool _loading = false;
  String? _errorMessage;

  VideoPlayerController? get controller => _controller;
  bool get isLoading => _loading;
  String? get errorMessage => _errorMessage;

  bool get hasVideo =>
      !_closed && _controller != null && _controller!.value.isInitialized;

  @override
  String get currentUrl => _currentUrl;

  @override
  bool get isPlaying =>
      !_closed && _controller?.value.isInitialized == true &&
      _controller!.value.isPlaying;

  @override
  bool get isPaused =>
      !_closed && _controller?.value.isInitialized == true &&
      !_controller!.value.isPlaying;

  @override
  Map<String, Object?> get times {
    final value = _controller?.value;
    if (_closed || value == null || !value.isInitialized) {
      return const <String, Object?>{
        'position': 0.0,
        'duration': 0.0,
      };
    }

    return <String, Object?>{
      'position': value.position.inMilliseconds / 1000.0,
      'duration': value.duration.inMilliseconds / 1000.0,
    };
  }

  @override
  List<String> get subtitles => const <String>[];

  @override
  Future<bool> play(Object? item) async {
    _ensureOpen();
    final url = _extractUrl(item);
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ArgumentError.value(url, 'item', 'URL de mídia HTTP/HTTPS inválida');
    }

    final existing = _controller;
    if (_currentUrl == url && existing?.value.isInitialized == true) {
      await existing!.play();
      notifyListeners();
      return true;
    }

    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _disposeController();

      final next = VideoPlayerController.networkUrl(uri);
      _controller = next;
      _currentUrl = url;
      next.addListener(_onControllerChanged);

      await next.initialize();
      await next.setLooping(false);
      await next.play();
      return true;
    } on Object catch (error) {
      _errorMessage = error.toString();
      await _disposeController();
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> togglePlayPause() async {
    _ensureOpen();
    final value = _controller;
    if (value == null || !value.value.isInitialized) return;
    if (value.value.isPlaying) {
      await value.pause();
    } else {
      await value.play();
    }
    notifyListeners();
  }

  @override
  Future<void> seek(double seconds) async {
    _ensureOpen();
    final value = _controller;
    if (value == null || !value.value.isInitialized) return;
    final target = seconds.isFinite ? seconds.clamp(0.0, 86400.0) : 0.0;
    await value.seekTo(Duration(milliseconds: (target * 1000).round()));
    notifyListeners();
  }

  @override
  Future<void> setSubtitles(List<String> urls) async {
    // video_player does not expose runtime replacement of external subtitle
    // tracks. The generic contract remains here so another player backend can
    // add this without changing the Lua API.
  }

  Future<void> stop() async {
    if (_closed) return;
    final value = _controller;
    if (value != null && value.value.isInitialized) {
      await value.pause();
      await value.seekTo(Duration.zero);
    }
    notifyListeners();
  }

  Future<void> clear() async {
    if (_closed) return;
    await _disposeController();
    _loading = false;
    _errorMessage = null;
    notifyListeners();
  }

  void _onControllerChanged() {
    if (!_closed) notifyListeners();
  }

  Future<void> _disposeController() async {
    final previous = _controller;
    _controller = null;
    _currentUrl = '';
    if (previous == null) return;
    previous.removeListener(_onControllerChanged);
    await previous.dispose();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    await _disposeController();
    _closed = true;
    notifyListeners();
    dispose();
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('Player do AddKo já foi encerrado.');
    }
  }

  static String _extractUrl(Object? item) {
    if (item is String && item.trim().isNotEmpty) {
      return item.trim();
    }
    if (item is Map) {
      final value = item['url'] ?? item['path'];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    throw ArgumentError.value(item, 'item', 'Mídia sem URL reproduzível');
  }
}

class AddKoVideoSurface extends StatelessWidget {
  const AddKoVideoSurface({
    required this.player,
    super.key,
  });

  final AddKoVideoPlayer player;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final controller = player.controller;
        if (controller == null || !controller.value.isInitialized) {
          final error = player.errorMessage;
          return Card(
            clipBehavior: Clip.antiAlias,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (player.isLoading) ...[
                        const CircularProgressIndicator(),
                        const SizedBox(height: 20),
                        const Text(
                          'Preparando reprodução…',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Torrents podem demorar para obter dados e iniciar o vídeo.',
                          textAlign: TextAlign.center,
                        ),
                      ] else if (error != null) ...[
                        const Icon(Icons.error_outline_rounded, size: 36),
                        const SizedBox(height: 12),
                        const Text(
                          'Falha ao reproduzir o vídeo',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          error.length > 360
                              ? '${error.substring(0, 360)}…'
                              : error,
                          textAlign: TextAlign.center,
                        ),
                      ] else
                        const Text(
                          'Aguardando vídeo…',
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final duration = controller.value.duration.inMilliseconds.toDouble();
        final position = controller.value.position.inMilliseconds
            .clamp(0, controller.value.duration.inMilliseconds)
            .toDouble();

        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: controller.value.aspectRatio == 0
                    ? 16 / 9
                    : controller.value.aspectRatio,
                child: ColoredBox(
                  color: Colors.black,
                  child: VideoPlayer(controller),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: controller.value.isPlaying ? 'Pausar' : 'Reproduzir',
                      onPressed: player.togglePlayPause,
                      icon: Icon(
                        controller.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        min: 0,
                        max: duration <= 0 ? 1 : duration,
                        value: duration <= 0 ? 0 : position,
                        onChanged: duration <= 0
                            ? null
                            : (value) => player.seek(value / 1000.0),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fechar vídeo',
                      onPressed: player.clear,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
