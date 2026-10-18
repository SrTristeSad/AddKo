import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:addko/src/platform/system_external_launcher.dart';
import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:addko/src/runtime/plugin_host.dart';
import 'package:addko/src/runtime/network_socket_services.dart';
import 'package:addko/src/runtime/media_stream_proxy.dart';
import 'package:path/path.dart' as p;

typedef ExternalUriOpener = Future<bool> Function(Uri uri);
typedef PluginUiHandler = Future<Object?> Function(
  String operation,
  Map<String, Object?> arguments,
);

class BasicPluginHost extends PluginHost {
  BasicPluginHost({
    required this.manifest,
    required this.pluginDirectory,
    required this.dataDirectory,
    ExternalUriOpener? externalUriOpener,
    this.uiHandler,
  }) : _externalUriOpener = externalUriOpener ??
            (SystemExternalLauncher.isSupported
                ? SystemExternalLauncher.open
                : null);

  static const int maxHttpResponseBytes = 8 * 1024 * 1024;
  static const int maxDownloadBytes = 64 * 1024 * 1024;
  static const int maxTcpClients = 8;
  static const int maxTcpTransferBytes = 64 * 1024;
  static const Set<String> _blockedExternalSchemes = <String>{
    'file',
    'content',
    'data',
    'javascript',
    'intent',
  };

  final PluginManifest manifest;
  final Directory pluginDirectory;
  final Directory dataDirectory;
  final ExternalUriOpener? _externalUriOpener;
  final PluginUiHandler? uiHandler;

  final HttpClient _http = HttpClient();
  final NetworkSocketServices _networkSockets = NetworkSocketServices();
  final MediaStreamProxy _mediaStreams = MediaStreamProxy();
  final Map<int, ServerSocket> _servers = <int, ServerSocket>{};
  final Map<int, _TcpClientConnection> _tcpClients = <int, _TcpClientConnection>{};
  final Set<Socket> _sockets = <Socket>{};
  PluginEventDispatcher? _eventDispatcher;
  int _nextNetworkHandle = 0;
  bool _closed = false;

  bool get _network => manifest.permissions.contains(PluginPermission.network);
  bool get _storage => manifest.permissions.contains(PluginPermission.storage);
  bool get _background =>
      manifest.permissions.contains(PluginPermission.background);
  bool get _media => manifest.permissions.contains(PluginPermission.media);

  @override
  Map<String, bool> get capabilities => <String, bool>{
        'http': _network,
        'filesystem': _storage,
        'sleep': true,
        'tcp_server': _network && _background,
        'tcp_client': _network,
        'tcp_tls_client': _network,
        'dns_lookup': _network,
        'udp': _network,
        'websocket': _network,
        'media_stream_proxy': _network,
        'process': false,
        'player': false,
        'ui': uiHandler != null,
        'open_uri': _externalUriOpener != null,
        'media_permission': _media,
      };

  @override
  void bindEventDispatcher(PluginEventDispatcher dispatcher) {
    _eventDispatcher = dispatcher;
  }

  @override
  Future<Object?> invoke(String operation, Object? arguments) async {
    _ensureOpen();
    final args = _map(arguments);

    if (operation.startsWith('ui.') && uiHandler != null) {
      return uiHandler!(operation, args);
    }

    switch (operation) {
      case 'log':
        final level = args['level']?.toString() ?? 'info';
        final message = args['message']?.toString() ?? '';
        // ignore: avoid_print
        print('[AddKo][$level][${manifest.id}] $message');
        return true;
      case 'sleep':
        final milliseconds = _int(args['milliseconds'], min: 0, max: 60000);
        await Future<void>.delayed(Duration(milliseconds: milliseconds));
        return true;
      case 'system.open_uri':
        return _openExternalUri(args['uri']);
      case 'http.request':
        _require(_network, 'network');
        return _httpRequest(args);
      case 'http.download':
        _require(_network, 'network');
        _require(_storage, 'storage');
        return _httpDownload(args);
      case 'fs.exists':
        _require(_storage, 'storage');
        return _exists(await _readablePath(args['path']));
      case 'fs.mkdirp':
        _require(_storage, 'storage');
        final directory = Directory(await _writablePath(args['path']));
        await directory.create(recursive: true);
        return true;
      case 'fs.write_text':
        _require(_storage, 'storage');
        final path = await _writablePath(args['path']);
        final file = File(path);
        await file.parent.create(recursive: true);
        await file.writeAsString(args['text']?.toString() ?? '', flush: true);
        return true;
      case 'fs.write_bytes':
        _require(_storage, 'storage');
        final path = await _writablePath(args['path']);
        final raw = args['bytes'];
        if (raw is! List) {
          throw const PluginHostException(
            'fs.write_bytes espera uma lista de bytes.',
          );
        }
        final bytes = raw
            .map((value) => _int(value, min: 0, max: 255))
            .toList(growable: false);
        final file = File(path);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
        return true;
      case 'fs.set_executable':
      case 'fs.chmod':
        throw const PluginHostException(
          'Arquivos executáveis graváveis não são suportados pelo host Android.',
        );
      case 'stream.register':
        _require(_network, 'network');
        return _mediaStreams.register(args);
      case 'stream.revoke':
        _require(_network, 'network');
        return _mediaStreams.revoke(args['id']);
      case 'stream.stats':
        _require(_network, 'network');
        return _mediaStreams.stats(args['id']);
      case 'net.dns.lookup':
      case 'net.udp.open':
      case 'net.udp.info':
      case 'net.udp.send':
      case 'net.udp.receive':
      case 'net.udp.close':
      case 'net.websocket.connect':
      case 'net.websocket.send':
      case 'net.websocket.receive':
      case 'net.websocket.close':
        _require(_network, 'network');
        // Binding a public UDP listener to a fixed port is a background
        // capability; outbound ephemeral UDP works with network alone.
        if (operation == 'net.udp.open' &&
            (args['port'] ?? 0) != 0 &&
            args['bind'] != 'loopback') {
          _require(_background, 'background');
        }
        return _networkSockets.invoke(operation, args);
      case 'net.tcp.listen':
        _require(_network && _background, 'network + background');
        return _listen(args);
      case 'net.tcp.connect':
        _require(_network, 'network');
        return _connectTcp(args);
      case 'net.tcp.write':
        _require(_network, 'network');
        return _writeTcp(args);
      case 'net.tcp.read':
        _require(_network, 'network');
        return _readTcp(args);
      case 'net.tcp.disconnect':
        _require(_network, 'network');
        return _disconnectTcp(_int(args['handle'], min: 1));
      case 'net.tcp.close':
        _require(_network, 'network');
        final handle = _int(args['handle'], min: 1);
        if (_tcpClients.containsKey(handle)) {
          return _disconnectTcp(handle);
        }
        _require(_background, 'background');
        return _closeServer(handle);
      case 'process.spawn':
      case 'process.stop':
        throw const PluginHostException(
          'Execução de binários de plugin não é suportada neste host Android.',
        );
      case 'ui.refresh':
      case 'ui.navigate':
      case 'ui.notify':
      case 'ui.alert':
      case 'ui.progress_update':
      case 'ui.progress_close':
        return true;
      case 'ui.input':
        return args['value']?.toString() ?? '';
      case 'ui.confirm':
        return false;
      case 'ui.select':
        return -1;
      case 'ui.pick_file':
        return '';
      case 'ui.progress_create':
        return 0;
      case 'ui.progress_is_cancelled':
        return false;
      case 'player.play':
        _require(_media, 'media');
        throw const PluginHostException('Player do host ainda não foi conectado.');
      case 'player.current_url':
        return '';
      case 'player.is_playing':
      case 'player.is_paused':
        return false;
      case 'player.times':
        return const <String, Object?>{
          'position': 0,
          'duration': 0,
        };
      case 'player.seek':
      case 'player.set_subtitles':
        return false;
      case 'player.subtitles':
        return const <Object?>[];
      default:
        throw PluginHostException('Operação de host desconhecida: $operation');
    }
  }

  Future<bool> _openExternalUri(Object? raw) async {
    final opener = _externalUriOpener;
    if (opener == null) {
      throw const PluginHostException(
        'Abertura de URI externo não é suportada neste host.',
      );
    }

    final text = raw?.toString().trim() ?? '';
    final uri = Uri.tryParse(text);
    final scheme = uri?.scheme.toLowerCase() ?? '';
    if (uri == null ||
        scheme.isEmpty ||
        _blockedExternalSchemes.contains(scheme)) {
      throw const PluginHostException('URI externo inválido ou não permitido.');
    }

    return opener(uri);
  }

  Future<Map<String, Object?>> _httpRequest(Map<String, Object?> args) async {
    final uri = _uri(args['url']);
    final method = (args['method']?.toString() ?? 'GET').toUpperCase();
    final timeoutSeconds = _int(
      args['timeout_seconds'] ?? 30,
      min: 1,
      max: 300,
    );

    final request = await _http
        .openUrl(method, uri)
        .timeout(Duration(seconds: timeoutSeconds));
    request.followRedirects = args['follow_redirects'] != false;

    final headers = args['headers'];
    if (headers is Map) {
      for (final entry in headers.entries) {
        request.headers.set(entry.key.toString(), entry.value.toString());
      }
    }

    final body = args['body'];
    if (body is String && body.isNotEmpty) {
      request.add(utf8.encode(body));
    } else if (body is List) {
      request.add(
        body.map((value) => _int(value, min: 0, max: 255)).toList(),
      );
    }

    final response = await request.close().timeout(
          Duration(seconds: timeoutSeconds),
        );
    // A playback endpoint can return a 302 or a large video body.
    // Read only response headers; never ingest media into Lua.
    if (args['headers_only'] == true) {
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name] = values.join(', ');
      });
      final subscription = response.listen((_) {});
      await subscription.cancel();
      return <String, Object?>{
        'status': response.statusCode,
        'body': '',
        'headers': responseHeaders,
        'url': uri.toString(),
      };
    }

    if (response.contentLength > maxHttpResponseBytes) {
      await response.drain<void>();
      throw const PluginHostException(
        'Resposta HTTP excede o limite de 8 MiB.',
      );
    }

    final bytes = await _readBoundedResponse(
      response,
      maxBytes: maxHttpResponseBytes,
      message: 'Resposta HTTP excede o limite de 8 MiB.',
    );

    final responseHeaders = <String, String>{};
    response.headers.forEach((name, values) {
      responseHeaders[name] = values.join(', ');
    });

    return <String, Object?>{
      'status': response.statusCode,
      'body': utf8.decode(bytes, allowMalformed: true),
      'headers': responseHeaders,
      'url': uri.toString(),
    };
  }

  Future<Map<String, Object?>> _httpDownload(Map<String, Object?> args) async {
    final uri = _uri(args['url']);
    final destination = await _writablePath(args['path']);
    final timeoutSeconds = _int(
      args['timeout_seconds'] ?? 180,
      min: 1,
      max: 600,
    );

    final request = await _http
        .getUrl(uri)
        .timeout(Duration(seconds: timeoutSeconds));
    request.followRedirects = true;
    final response = await request.close().timeout(
          Duration(seconds: timeoutSeconds),
        );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      return <String, Object?>{
        'status': response.statusCode,
        'path': destination,
      };
    }

    if (response.contentLength > maxDownloadBytes) {
      await response.drain<void>();
      throw const PluginHostException(
        'Download excede o limite de 64 MiB.',
      );
    }

    final file = File(destination);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    var total = 0;
    try {
      await for (final data in response) {
        total += data.length;
        if (total > maxDownloadBytes) {
          throw const PluginHostException(
            'Download excede o limite de 64 MiB.',
          );
        }
        sink.add(data);
      }
      await sink.flush();
      await sink.close();
    } on Object {
      await sink.close();
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    }

    return <String, Object?>{
      'status': response.statusCode,
      'path': destination,
    };
  }

// Outbound connections are generic transport handles. Plugins implement
  // their own protocols on top; the host never knows about torrent/SMB/etc.
  Future<int> _connectTcp(Map<String, Object?> args) async {
    if (_tcpClients.length >= maxTcpClients) {
      throw const PluginHostException('Limite de 8 conexões TCP por plugin.');
    }
    final rawHost = args['host'];
    if (rawHost is! String ||
        rawHost.isEmpty ||
        rawHost.length > 253 ||
        rawHost.trim() != rawHost ||
        rawHost.contains(RegExp(r'[\s/\\]'))) {
      throw const PluginHostException('Host TCP inválido.');
    }
    final port = _int(args['port'], min: 1, max: 65535);
    final timeout = Duration(
      milliseconds: _int(args['timeout_ms'] ?? 10000, min: 1, max: 60000),
    );
    final tls = args['tls'] == true;
    final Socket socket = tls
        ? await SecureSocket.connect(rawHost, port, timeout: timeout)
        : await Socket.connect(rawHost, port, timeout: timeout);
    if (_closed) {
      socket.destroy();
      throw const PluginHostException('Host do plugin já foi encerrado.');
    }
    if (_tcpClients.length >= maxTcpClients) {
      socket.destroy();
      throw const PluginHostException('Limite de 8 conexões TCP por plugin.');
    }
    final handle = ++_nextNetworkHandle;
    _tcpClients[handle] = _TcpClientConnection(socket);
    return handle;
  }

  Future<int> _writeTcp(Map<String, Object?> args) async {
    final handle = _int(args['handle'], min: 1);
    final client = _tcpClients[handle];
    if (client == null) {
      throw const PluginHostException('Conexão TCP desconhecida.');
    }
    final raw = args['data'];
    final List<int> bytes;
    if (raw is String) {
      bytes = utf8.encode(raw);
    } else if (raw is List) {
      if (raw.length > maxTcpTransferBytes) {
        throw const PluginHostException('Escrita TCP excede 64 KiB.');
      }
      bytes = raw.map((value) => _int(value, min: 0, max: 255)).toList();
    } else {
      throw const PluginHostException(
        'net.tcp.write exige texto ou uma lista de bytes.',
      );
    }
    if (bytes.length > maxTcpTransferBytes) {
      throw const PluginHostException('Escrita TCP excede 64 KiB.');
    }
    final timeout = Duration(
      milliseconds: _int(args['timeout_ms'] ?? 10000, min: 1, max: 60000),
    );
    await client.write(bytes, timeout: timeout);
    return bytes.length;
  }

  Future<Map<String, Object?>> _readTcp(Map<String, Object?> args) async {
    final handle = _int(args['handle'], min: 1);
    final client = _tcpClients[handle];
    if (client == null) {
      throw const PluginHostException('Conexão TCP desconhecida.');
    }
    final maxBytes = _int(
      args['max_bytes'] ?? 8192,
      min: 1,
      max: maxTcpTransferBytes,
    );
    final timeout = Duration(
      milliseconds: _int(args['timeout_ms'] ?? 5000, min: 1, max: 60000),
    );
    return client.read(maxBytes: maxBytes, timeout: timeout);
  }

  Future<bool> _disconnectTcp(int handle) async {
    final client = _tcpClients.remove(handle);
    if (client == null) return false;
    await client.close();
    return true;
  }

  Future<int> _listen(Map<String, Object?> args) async {
    final host = args['host']?.toString() ?? '127.0.0.1';
    if (host != '127.0.0.1' && host != 'localhost' && host != '::1') {
      throw const PluginHostException(
        'Servidor TCP de plugin só pode ouvir no loopback.',
      );
    }

    final port = _int(args['port'], min: 1, max: 65535);
    final callbackId = _int(args['callback_id'], min: 1);
    final framing = args['framing']?.toString() ?? 'lines';
    if (framing != 'lines') {
      throw const PluginHostException('Somente framing TCP por linhas é suportado.');
    }

    final address = host == '::1'
        ? InternetAddress.loopbackIPv6
        : InternetAddress.loopbackIPv4;
    final server = await ServerSocket.bind(address, port, shared: false);
    final id = ++_nextNetworkHandle;
    _servers[id] = server;

    server.listen((socket) {
      _sockets.add(socket);
      socket.done.whenComplete(() => _sockets.remove(socket));
      unawaited(_serveLines(socket, callbackId));
    });

    return id;
  }

  Future<void> _serveLines(Socket socket, int callbackId) async {
    try {
      await for (final line
          in utf8.decoder.bind(socket).transform(const LineSplitter())) {
        final dispatcher = _eventDispatcher;
        if (dispatcher == null) {
          throw const PluginHostException('Event dispatcher não conectado.');
        }
        final response = await dispatcher(callbackId, <Object?>[line]);
        if (response != null) {
          socket.write(response.toString());
        }
        socket.write('\n');
        await socket.flush();
      }
    } on Object {
      // The peer may disconnect while a plugin event is being processed.
    } finally {
      _sockets.remove(socket);
      await socket.close();
    }
  }

  Future<bool> _closeServer(int id) async {
    final server = _servers.remove(id);
    if (server == null) return false;
    await server.close();
    return true;
  }

  Future<bool> _exists(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    return type != FileSystemEntityType.notFound;
  }

  Future<String> _readablePath(Object? raw) async {
    final candidate = _absolute(raw);
    final pluginRoot = _absoluteRoot(pluginDirectory.path);
    final dataRoot = _absoluteRoot(dataDirectory.path);

    if (_isInside(candidate, pluginRoot)) {
      await _rejectSymlinkSegments(candidate, pluginRoot);
      return candidate;
    }
    if (_isInside(candidate, dataRoot)) {
      await _rejectSymlinkSegments(candidate, dataRoot);
      return candidate;
    }
    throw const PluginHostException('Acesso fora do escopo do plugin.');
  }

  Future<String> _writablePath(Object? raw) async {
    final candidate = _absolute(raw);
    final dataRoot = _absoluteRoot(dataDirectory.path);
    if (_isInside(candidate, dataRoot)) {
      await _rejectSymlinkSegments(candidate, dataRoot);
      return candidate;
    }
    throw const PluginHostException(
      'Plugin só pode gravar no próprio diretório de dados.',
    );
  }

  String _absolute(Object? raw) {
    final value = raw?.toString();
    if (value == null || value.isEmpty) {
      throw const PluginHostException('Caminho vazio.');
    }
    return p.normalize(p.absolute(value));
  }

  String _absoluteRoot(String root) => p.normalize(p.absolute(root));

  bool _isInside(String candidate, String root) {
    return candidate == root || p.isWithin(root, candidate);
  }

  Future<void> _rejectSymlinkSegments(String candidate, String root) async {
    final rootType = await FileSystemEntity.type(root, followLinks: false);
    if (rootType == FileSystemEntityType.link) {
      throw const PluginHostException(
        'Raiz de armazenamento não pode ser link simbólico.',
      );
    }

    final relative = p.relative(candidate, from: root);
    if (relative == '.') return;

    var current = root;
    for (final segment in p.split(relative)) {
      current = p.join(current, segment);
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw const PluginHostException(
          'Links simbólicos não podem atravessar o sandbox do plugin.',
        );
      }
      if (type == FileSystemEntityType.notFound) {
        return;
      }
    }
  }

  Uri _uri(Object? value) {
    final text = value?.toString() ?? '';
    final uri = Uri.tryParse(text);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const PluginHostException('URL HTTP/HTTPS inválida.');
    }
    return uri;
  }

  void _require(bool allowed, String permission) {
    if (!allowed) {
      throw PluginHostException('Plugin não possui capacidade $permission.');
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw const PluginHostException('Host do plugin já foi encerrado.');
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    await _mediaStreams.close();
    await _networkSockets.close();

    for (final client in _tcpClients.values.toList()) {
      await client.close();
    }
    _tcpClients.clear();

    for (final socket in List<Socket>.of(_sockets)) {
      await socket.close();
    }
    _sockets.clear();

    for (final server in _servers.values) {
      await server.close();
    }
    _servers.clear();
    _http.close(force: true);
  }
}

/// Bounded receive queue; keeps network callbacks out of the Lua scheduler.
/// Reads return raw bytes, EOF and timeout flags, never silently truncate data.
class _TcpClientConnection {
  _TcpClientConnection(this.socket) {
    _subscription = socket.listen(
      (chunk) {
        if (_buffered + chunk.length > maxBufferedBytes) {
          _error = const PluginHostException('Buffer TCP excede 256 KiB.');
          socket.destroy();
          _ended = true;
          _wake();
          return;
        }
        _chunks.add(List<int>.of(chunk));
        _buffered += chunk.length;
        _wake();
      },
      onError: (Object error) {
        _error = error;
        _ended = true;
        _wake();
      },
      onDone: () {
        _ended = true;
        _wake();
      },
      cancelOnError: true,
    );
  }

  static const int maxBufferedBytes = 256 * 1024;

  final Socket socket;
  late final StreamSubscription<List<int>> _subscription;
  final Queue<List<int>> _chunks = Queue<List<int>>();
  int _buffered = 0;
  bool _ended = false;
  bool _reading = false;
  Object? _error;
  Completer<void>? _waiter;

  void _wake() {
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete();
    }
  }

  Future<void> write(List<int> bytes, {required Duration timeout}) async {
    if (_ended) {
      throw const PluginHostException('Conexão TCP encerrada.');
    }
    socket.add(bytes);
    await socket.flush().timeout(timeout);
  }

  Future<Map<String, Object?>> read({
    required int maxBytes,
    required Duration timeout,
  }) async {
    if (_reading) {
      throw const PluginHostException('Leitura TCP concorrente não permitida.');
    }
    _reading = true;
    try {
      if (_chunks.isEmpty && !_ended && _error == null) {
        final waiter = Completer<void>();
        _waiter = waiter;
        try {
          await waiter.future.timeout(timeout);
        } on TimeoutException {
          return <String, Object?>{
            'bytes': <int>[],
            'eof': false,
            'timed_out': true,
          };
        } finally {
          if (identical(_waiter, waiter)) _waiter = null;
        }
      }
      if (_error != null) {
        throw PluginHostException('Erro na conexão TCP: ' + _error.toString());
      }
      final output = <int>[];
      while (_chunks.isNotEmpty && output.length < maxBytes) {
        final chunk = _chunks.removeFirst();
        final count = maxBytes - output.length;
        if (chunk.length <= count) {
          output.addAll(chunk);
          _buffered -= chunk.length;
        } else {
          output.addAll(chunk.take(count));
          _chunks.addFirst(chunk.sublist(count));
          _buffered -= count;
        }
      }
      return <String, Object?>{
        'bytes': output,
        'eof': _ended && _chunks.isEmpty,
        'timed_out': false,
      };
    } finally {
      _reading = false;
    }
  }

  Future<void> close() async {
    _ended = true;
    _wake();
    socket.destroy();
    await _subscription.cancel();
    _chunks.clear();
    _buffered = 0;
  }
}

class PluginHostException implements Exception {
  const PluginHostException(this.message);

  final String message;

  @override
  String toString() => 'PluginHostException: $message';
}

Future<List<int>> _readBoundedResponse(
  HttpClientResponse response, {
  required int maxBytes,
  required String message,
}) async {
  final bytes = <int>[];
  await for (final data in response) {
    if (bytes.length > maxBytes - data.length) {
      throw PluginHostException(message);
    }
    bytes.addAll(data);
  }
  return bytes;
}

Map<String, Object?> _map(Object? value) {
  if (value == null) return <String, Object?>{};
  if (value is! Map) {
    throw const PluginHostException('Argumentos da operação devem ser objeto.');
  }
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

int _int(Object? value, {required int min, int? max}) {
  final number = value is num ? value.toInt() : int.tryParse(value.toString());
  if (number == null || number < min || (max != null && number > max)) {
    throw PluginHostException('Inteiro fora do intervalo: $value');
  }
  return number;
}
