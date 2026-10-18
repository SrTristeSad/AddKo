import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Session-scoped HTTP media bridge. Streams bytes directly to the native
/// player without passing video payloads through the Lua/JSON protocol.
class MediaStreamProxy {
  MediaStreamProxy() {
    _client.autoUncompress = false;
    _client.connectionTimeout = const Duration(seconds: 15);
  }

  static const int maxSources = 8;
  static const int maxActiveRequests = 8;
  static const int maxRedirects = 4;

  final HttpClient _client = HttpClient();
  final Map<String, _MediaSource> _sources = <String, _MediaSource>{};
  final Random _random = Random.secure();
  HttpServer? _server;
  Future<HttpServer>? _opening;
  int _active = 0;
  bool _closed = false;

  static final RegExp _headerName =
      RegExp(r"^[A-Za-z0-9!#$%&'*+.^_|~-]+$");
  static final RegExp _singleRange =
      RegExp(r'^bytes=(?:[0-9]+-[0-9]*|-[0-9]+)$');
  static const Set<String> _blockedRequestHeaders = <String>{
    'host', 'connection', 'upgrade', 'transfer-encoding', 'content-length',
    'content-type', 'range', 'if-range', 'if-none-match', 'if-modified-since',
    'proxy-authorization', 'proxy-connection', 'keep-alive', 'te', 'trailer',
    'accept-encoding',
  };
  static const List<String> _responseHeaders = <String>[
    'content-type', 'content-length', 'content-range', 'accept-ranges',
    'etag', 'last-modified', 'cache-control', 'expires', 'content-encoding',
  ];

  Future<Map<String, Object?>> register(Map<String, Object?> args) async {
    if (_closed) throw const MediaStreamException('Ponte encerrada.');
    if (_sources.length >= maxSources) {
      throw const MediaStreamException('Limite de 8 fontes por plugin.');
    }
    final uri = _sourceUri(args['url']);
    final headers = _headers(args['headers']);
    final server = await _ensureServer();
    if (_closed || _sources.length >= maxSources) {
      throw const MediaStreamException('Ponte encerrada ou sem capacidade.');
    }
    String token;
    do {
      final bytes = List<int>.generate(24, (_) => _random.nextInt(256));
      token = base64UrlEncode(bytes).replaceAll('=', '');
    } while (_sources.containsKey(token));
    _sources[token] = _MediaSource(uri, headers);
    return <String, Object?>{
      'id': token,
      'url': 'http://127.0.0.1:' + server.port.toString() + '/media/' + token,
    };
  }


  /// Lightweight diagnostics for a registered source. No bearer token,
  /// authorization header or upstream URL is ever returned.
  Map<String, Object?> stats(Object? rawId) {
    if (_closed) throw const MediaStreamException('Ponte encerrada.');
    if (rawId is! String || rawId.isEmpty) {
      throw const MediaStreamException('ID de fonte inválido.');
    }
    final source = _sources[rawId];
    if (source == null) {
      throw const MediaStreamException('Fonte de mídia desconhecida.');
    }
    return <String, Object?>{
      'requests': source.requests,
      'head_requests': source.headRequests,
      'range_requests': source.rangeRequests,
      'upstream_requests': source.upstreamRequests,
      'bytes_forwarded': source.bytesForwarded,
      'active_requests': source.activeRequests,
      'failed_requests': source.failedRequests,
      'last_http_status': source.lastHttpStatus,
      'last_error': source.lastError,
    };
  }

  bool revoke(Object? rawId) {
    if (_closed) return false;
    if (rawId is! String) {
      throw const MediaStreamException('ID de fonte inválido.');
    }
    // An in-flight request can finish; new requests and seeks are rejected.
    return _sources.remove(rawId) != null;
  }

  Future<HttpServer> _ensureServer() async {
    if (_server != null) return _server!;
    if (_opening != null) return _opening!;
    final future = HttpServer.bind(
      InternetAddress.loopbackIPv4, 0, shared: false,
    );
    _opening = future;
    try {
      final server = await future;
      if (_closed) {
        await server.close(force: true);
        throw const MediaStreamException('Ponte encerrada.');
      }
      _server = server;
      server.listen(
        (request) => unawaited(_handle(request)),
        onError: (Object _) {},
      );
      return server;
    } finally {
      _opening = null;
    }
  }

  Future<void> _handle(HttpRequest incoming) async {
    final outgoing = incoming.response;
    try {
      if (_closed) {
        await _reject(outgoing, HttpStatus.serviceUnavailable);
        return;
      }
      final path = incoming.uri.pathSegments;
      if (path.length != 2 || path.first != 'media' ||
          !_sources.containsKey(path.last)) {
        await _reject(outgoing, HttpStatus.notFound);
        return;
      }
      if (incoming.method != 'GET' && incoming.method != 'HEAD') {
        outgoing.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
        await _reject(outgoing, HttpStatus.methodNotAllowed);
        return;
      }
      if (_active >= maxActiveRequests) {
        await _reject(outgoing, HttpStatus.serviceUnavailable);
        return;
      }
      final range = incoming.headers.value(HttpHeaders.rangeHeader);
      if (range != null &&
          (range.length > 128 || !_singleRange.hasMatch(range))) {
        await _reject(outgoing, HttpStatus.requestedRangeNotSatisfiable);
        return;
      }
      final source = _sources[path.last]!;
      source.requests++;
      if (incoming.method == 'HEAD') source.headRequests++;
      if (range != null) source.rangeRequests++;
      source.activeRequests++;
      _active++;
      try {
        await _pipe(source, incoming, outgoing);
      } catch (error) {
        source.failedRequests++;
        // Avoid logging credentials, tokens or full user-provided URLs.
        source.lastError = error.runtimeType.toString();
        rethrow;
      } finally {
        source.activeRequests--;
        _active--;
      }
    } on Object {
      try {
        // If headers were already sent, updating them fails; only close.
        outgoing.statusCode = HttpStatus.badGateway;
        outgoing.headers.contentType = ContentType.text;
        outgoing.write('Upstream media unavailable');
      } on Object {
        // Player disconnected while seeking.
      }
      try {
        await outgoing.close();
      } on Object {
        // Connection already closed.
      }
    }
  }

  Future<void> _pipe(
    _MediaSource source,
    HttpRequest incoming,
    HttpResponse outgoing,
  ) async {
    var url = source.uri;
    final origin = source.uri.origin;
    for (var redirects = 0; redirects <= maxRedirects; redirects++) {
      final request = await _client.openUrl(incoming.method, url)
          .timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      // Keep byte positions stable; the proxy forwards upstream encoding as-is.
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      // Never leak plugin credentials across redirect origins.
      if (url.origin == origin) {
        for (final entry in source.headers.entries) {
          request.headers.set(entry.key, entry.value);
        }
      }
      for (final name in <String>[
        HttpHeaders.rangeHeader,
        HttpHeaders.ifRangeHeader,
        HttpHeaders.ifNoneMatchHeader,
        HttpHeaders.ifModifiedSinceHeader,
      ]) {
        final value = incoming.headers.value(name);
        if (value != null) request.headers.set(name, value);
      }
      final upstream = await request.close()
          .timeout(const Duration(seconds: 15));
      source.upstreamRequests++;
      source.lastHttpStatus = upstream.statusCode;
      if (upstream.isRedirect) {
        final location = upstream.headers.value(HttpHeaders.locationHeader);
        await upstream.listen((_) {}).cancel();
        if (location == null || redirects == maxRedirects) {
          await _reject(outgoing, HttpStatus.badGateway);
          return;
        }
        url = _sourceUri(url.resolve(location).toString());
        continue;
      }

      outgoing.statusCode = upstream.statusCode;
      outgoing.bufferOutput = false;
      for (final name in _responseHeaders) {
        final values = upstream.headers[name];
        if (values != null && values.isNotEmpty) {
          outgoing.headers.set(name, values.join(', '));
        }
      }
      if (incoming.method == 'HEAD') {
        await upstream.listen((_) {}).cancel();
        await outgoing.close();
        return;
      }
      try {
        // addStream preserves backpressure and never buffers a whole video.
        await outgoing.addStream(
          upstream.timeout(const Duration(seconds: 60)).map((chunk) {
            source.bytesForwarded += chunk.length;
            return chunk;
          }),
        );
      } finally {
        try {
          await outgoing.close();
        } on Object {
          // Seeks and navigation legitimately end an active connection.
        }
      }
      return;
    }
  }

  static Future<void> _reject(HttpResponse response, int status) async {
    response.statusCode = status;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    await response.close();
  }

  static Uri _sourceUri(Object? raw) {
    if (raw is! String || raw.isEmpty || raw.length > 4096) {
      throw const MediaStreamException('URL de mídia inválida.');
    }
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const MediaStreamException('A fonte deve usar HTTP ou HTTPS.');
    }
    return uri;
  }

  static Map<String, String> _headers(Object? raw) {
    if (raw == null) return const <String, String>{};
    if (raw is! Map || raw.length > 20) {
      throw const MediaStreamException('Cabeçalhos de mídia inválidos.');
    }
    final values = <String, String>{};
    for (final item in raw.entries) {
      final name = item.key;
      final value = item.value;
      if (name is! String ||
          value is! String ||
          name.length > 80 ||
          value.length > 4096 ||
          !_headerName.hasMatch(name) ||
          value.contains('\r') ||
          value.contains('\n') ||
          _blockedRequestHeaders.contains(name.toLowerCase())) {
        throw const MediaStreamException('Cabeçalho de mídia não permitido.');
      }
      values[name] = value;
    }
    return values;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _sources.clear();
    final opening = _opening;
    if (opening != null) {
      try {
        await opening;
      } on Object {
        // Bind failure does not prevent cleanup.
      }
    }
    await _server?.close(force: true);
    _server = null;
    _client.close(force: true);
  }
}

class _MediaSource {
  _MediaSource(this.uri, this.headers);

  final Uri uri;
  final Map<String, String> headers;

  int requests = 0;
  int headRequests = 0;
  int rangeRequests = 0;
  int upstreamRequests = 0;
  int bytesForwarded = 0;
  int activeRequests = 0;
  int failedRequests = 0;
  int? lastHttpStatus;
  String? lastError;
}

class MediaStreamException implements Exception {
  const MediaStreamException(this.message);
  final String message;
  @override
  String toString() => 'MediaStreamException: ' + message;
}
