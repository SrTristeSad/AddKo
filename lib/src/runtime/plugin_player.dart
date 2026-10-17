abstract class PluginPlayer {
  Future<bool> play(Object? item);

  String get currentUrl;

  bool get isPlaying;

  bool get isPaused;

  Map<String, Object?> get times;

  Future<void> seek(double seconds);

  List<String> get subtitles;

  Future<void> setSubtitles(List<String> urls);

  Future<void> close();
}
