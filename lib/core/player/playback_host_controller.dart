import 'dart:async';

import 'playback_request.dart';

typedef PlaybackRequestHandler = Future<void> Function(PlaybackRequest request);
typedef PlaybackVoidHandler = Future<void> Function();
typedef PlaybackSeekHandler = Future<void> Function(Duration position);

class PlaybackHostController {
  PlaybackHostController._();

  static final PlaybackHostController shared = PlaybackHostController._();

  Object? _ownerToken;
  PlaybackRequestHandler? _openHandler;
  PlaybackVoidHandler? _playHandler;
  PlaybackVoidHandler? _pauseHandler;
  PlaybackVoidHandler? _stopHandler;
  PlaybackSeekHandler? _seekHandler;

  bool get isAttached => _ownerToken != null;

  Object attach({
    required PlaybackRequestHandler onOpen,
    required PlaybackVoidHandler onPlay,
    required PlaybackVoidHandler onPause,
    required PlaybackVoidHandler onStop,
    required PlaybackSeekHandler onSeek,
  }) {
    final token = Object();
    _ownerToken = token;
    _openHandler = onOpen;
    _playHandler = onPlay;
    _pauseHandler = onPause;
    _stopHandler = onStop;
    _seekHandler = onSeek;
    return token;
  }

  void detach(Object token) {
    if (!identical(_ownerToken, token)) {
      return;
    }
    _ownerToken = null;
    _openHandler = null;
    _playHandler = null;
    _pauseHandler = null;
    _stopHandler = null;
    _seekHandler = null;
  }

  Future<bool> open(PlaybackRequest request) async {
    final handler = _openHandler;
    if (handler == null) return false;
    await handler(request);
    return true;
  }

  Future<bool> play() => _invoke(_playHandler);

  Future<bool> pause() => _invoke(_pauseHandler);

  Future<bool> stop() => _invoke(_stopHandler);

  Future<bool> seek(Duration position) async {
    final handler = _seekHandler;
    if (handler == null) return false;
    await handler(position);
    return true;
  }

  Future<bool> _invoke(PlaybackVoidHandler? handler) async {
    if (handler == null) return false;
    await handler();
    return true;
  }
}
