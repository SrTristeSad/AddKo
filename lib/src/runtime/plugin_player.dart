abstract class PluginPlayer {
  Future<bool> play(Object? item);

  String get currentUrl;

  bool get isPlaying;

  bool get isPaused;

  Map<String, Object?> get times;

  /// False until the media controller has initialized and is seekable.
  bool get canSeek => isPlaying || isPaused;

  /// Status exposed to Lua without leaking stream tokens or source URLs.
  Map<String, Object?> get status => <String, Object?>{
        'state': isPlaying ? 'playing' : (isPaused ? 'paused' : 'idle'),
        'can_seek': canSeek,
        ...times,
      };

  Future<void> seek(double seconds);

  List<String> get subtitles;

  Future<void> setSubtitles(List<String> urls);

  Future<void> close();
}
