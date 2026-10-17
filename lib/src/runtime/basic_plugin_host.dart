import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:addko/src/plugins/plugin_manifest.dart';
import 'package:addko/src/runtime/plugin_host.dart';
import 'package:path/path.dart' as p;

class BasicPluginHost extends PluginHost {
  BasicPluginHost({
    required this.manifest,
    required this.pluginDirectory,
    required this.dataDirectory,
  });

  static const int maxHttpResponseBytes = 8 * 1024 * 1024;
  static const int maxDownloadBytes = 64 * 1024 * 1024;

  final PluginManifest manifest;
  final Directory pluginDirectory;
  final Directory dataDirectory;

  final HttpClient _http = HttpClient();
  final Map<int, ServerSocket> _servers = <int, ServerSocket>{};
  final Set<Socket> _sockets = <Socket>{};
  PluginEventDispatcher? _eventDispatcher;
  int _nextServerId = 0;
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
        'process': false,
        'player': false,
        'ui': false,
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
      case 'net.tcp.listen':
        _require(_network && _background, 'network + background');
        return _listen(args);
      case 'net.tcp.close':
        _require(_network && _background, 'network + background');
        return _closeServer(_int(args['handle'], min: 1));
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
    final id = ++_nextServerId;
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
