import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

/// Transport primitives owned by one isolated AddKo plugin session.
///
/// This class deliberately contains no application-specific protocol logic.
/// The calling PluginHost enforces the "network" permission before invoking it.
class NetworkSocketServices {
  static const int maxUdpSockets = 8;
  static const int maxWebSockets = 8;
  static const int maxPacketBytes = 65507;
  static const int maxWebSocketMessageBytes = 64 * 1024;
  static const int maxBufferedBytes = 256 * 1024;

  final Map<int, _UdpSocket> _udp = <int, _UdpSocket>{};
  final Map<int, _WebSocketClient> _websockets =
      <int, _WebSocketClient>{};
  int _nextHandle = 0;
  bool _closed = false;

  Future<Object?> invoke(
    String operation,
    Map<String, Object?> args,
  ) async {
    if (_closed) {
      throw const NetworkSocketException('Serviços de rede encerrados.');
    }
    switch (operation) {
      case 'net.dns.lookup':
        return _lookup(args);
      case 'net.udp.open':
        return _openUdp(args);
      case 'net.udp.send':
        return _sendUdp(args);
      case 'net.udp.receive':
        return _receiveUdp(args);
      case 'net.udp.close':
        return _closeUdp(_int(args['handle'], min: 1));
      case 'net.websocket.connect':
        return _connectWebSocket(args);
      case 'net.websocket.send':
        return _sendWebSocket(args);
      case 'net.websocket.receive':
        return _receiveWebSocket(args);
      case 'net.websocket.close':
        return _closeWebSocket(_int(args['handle'], min: 1));
      default:
        throw NetworkSocketException('Operação de rede desconhecida: ' + operation);
    }
  }

  Future<List<String>> _lookup(Map<String, Object?> args) async {
    final host = _host(args['host']);
    final family = _family(args['family']);
    final addresses = await InternetAddress.lookup(
      host,
      type: family,
    ).timeout(_timeout(args, fallback: 10000));
    return addresses.take(16).map((address) => address.address).toList();
  }

  Future<int> _openUdp(Map<String, Object?> args) async {
    if (_udp.length >= maxUdpSockets) {
      throw const NetworkSocketException('Limite de sockets UDP alcançado.');
    }
    final port = _int(args['port'] ?? 0, min: 0, max: 65535);
    final family = _family(args['family']);
    final bind = args['bind'] ?? 'any';
    if (bind != 'any' && bind != 'loopback') {
      throw const NetworkSocketException('bind deve ser any ou loopback.');
    }
    final address = family == InternetAddressType.IPv6
        ? (bind == 'loopback'
            ? InternetAddress.loopbackIPv6
            : InternetAddress.anyIPv6)
        : (bind == 'loopback'
            ? InternetAddress.loopbackIPv4
            : InternetAddress.anyIPv4);
    final socket = await RawDatagramSocket.bind(
      address,
      port,
      reuseAddress: false,
    ).timeout(_timeout(args, fallback: 10000));
    if (_closed || _udp.length >= maxUdpSockets) {
      socket.close();
      throw const NetworkSocketException('Socket UDP não pode ser iniciado.');
    }
    final handle = ++_nextHandle;
    _udp[handle] = _UdpSocket(socket);
    return handle;
  }

  Future<Map<String, Object?>> _sendUdp(Map<String, Object?> args) async {
    final socket = _requireUdp(args['handle']);
    final host = _host(args['host']);
    final port = _int(args['port'], min: 1, max: 65535);
    final bytes = _bytes(args['data'], limit: maxPacketBytes);
    final family = socket.socket.address.type;
    final addresses = await InternetAddress.lookup(
      host, type: family,
    ).timeout(_timeout(args, fallback: 10000));
    if (addresses.isEmpty) {
      throw const NetworkSocketException('Destino UDP não encontrado.');
    }
    if (_closed || socket.closed) {
      throw const NetworkSocketException('Socket UDP encerrado.');
    }
    final sent = socket.socket.send(bytes, addresses.first, port);
    return <String, Object?>{'sent': sent, 'local_port': socket.socket.port};
  }

  Future<Map<String, Object?>> _receiveUdp(Map<String, Object?> args) {
    final socket = _requireUdp(args['handle']);
    return socket.receive(_timeout(args, fallback: 5000));
  }

  Future<bool> _closeUdp(int handle) async {
    final socket = _udp.remove(handle);
    if (socket == null) return false;
    await socket.close();
    return true;
  }

  Future<int> _connectWebSocket(Map<String, Object?> args) async {
    if (_websockets.length >= maxWebSockets) {
      throw const NetworkSocketException('Limite de WebSockets alcançado.');
    }
    final raw = args['url'];
    if (raw is! String || raw.length > 2048) {
      throw const NetworkSocketException('URL WebSocket inválida.');
    }
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        (uri.scheme != 'ws' && uri.scheme != 'wss') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const NetworkSocketException('URL WebSocket inválida.');
    }

    // Authentication headers are useful for third-party Lua services, but
    // connection/upgrade headers must be generated by dart:io itself.
    final headers = <String, String>{};
    final rawHeaders = args['headers'];
    if (rawHeaders != null) {
      if (rawHeaders is! Map || rawHeaders.length > 24) {
        throw const NetworkSocketException('Cabeçalhos WebSocket inválidos.');
      }
      const blocked = <String>{
        'connection', 'upgrade', 'host', 'sec-websocket-key',
        'sec-websocket-version', 'sec-websocket-accept',
        'sec-websocket-protocol', 'sec-websocket-extensions',
        'content-length',
      };
      for (final header in rawHeaders.entries) {
        final name = header.key;
        final value = header.value;
        if (name is! String ||
            value is! String ||
            name.length > 80 ||
            value.length > 4096 ||
            !RegExp(r'^[A-Za-z0-9!#$%&*+.^_\u0060|~-]+$').hasMatch(name) ||
            value.contains('\r') ||
            value.contains('\n') ||
            blocked.contains(name.toLowerCase())) {
          throw const NetworkSocketException('Cabeçalho WebSocket inseguro.');
        }
        headers[name] = value;
      }
    }

    final ws = await WebSocket.connect(
      uri.toString(),
      headers: headers,
      compression: CompressionOptions.compressionOff,
    ).timeout(_timeout(args, fallback: 10000));
    if (_closed || _websockets.length >= maxWebSockets) {
      await ws.close();
      throw const NetworkSocketException('WebSocket não pode ser iniciado.');
    }
    ws.pingInterval = const Duration(seconds: 30);
    final handle = ++_nextHandle;
    _websockets[handle] = _WebSocketClient(ws);
    return handle;
  }

  Future<bool> _sendWebSocket(Map<String, Object?> args) async {
    final socket = _requireWebSocket(args['handle']);
    final value = args['data'];
    if (socket.closed) {
      throw const NetworkSocketException('WebSocket encerrado.');
    }
    if (value is String) {
      final size = utf8.encode(value).length;
      if (size > maxWebSocketMessageBytes) {
        throw const NetworkSocketException('Mensagem WebSocket excede 64 KiB.');
      }
      socket.socket.add(value);
    } else {
      socket.socket.add(_bytes(value, limit: maxWebSocketMessageBytes));
    }
    return true;
  }

  Future<Map<String, Object?>> _receiveWebSocket(
    Map<String, Object?> args,
  ) {
    return _requireWebSocket(args['handle']).receive(
      _timeout(args, fallback: 5000),
    );
  }

  Future<bool> _closeWebSocket(int handle) async {
    final socket = _websockets.remove(handle);
    if (socket == null) return false;
    await socket.close();
    return true;
  }

  _UdpSocket _requireUdp(Object? raw) {
    final handle = _int(raw, min: 1);
    final socket = _udp[handle];
    if (socket == null) {
      throw const NetworkSocketException('Socket UDP desconhecido.');
    }
    return socket;
  }

  _WebSocketClient _requireWebSocket(Object? raw) {
    final handle = _int(raw, min: 1);
    final socket = _websockets[handle];
    if (socket == null) {
      throw const NetworkSocketException('WebSocket desconhecido.');
    }
    return socket;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final udp = _udp.values.toList();
    final websockets = _websockets.values.toList();
    _udp.clear();
    _websockets.clear();
    for (final socket in udp) {
      await socket.close();
    }
    for (final socket in websockets) {
      await socket.close();
    }
  }
}

class _UdpSocket {
  _UdpSocket(this.socket) {
    _subscription = socket.listen(
      (event) {
        if (event == RawSocketEvent.closed) {
          _closed = true;
          _wake();
        } else if (event == RawSocketEvent.read) {
          Datagram? packet;
          while ((packet = socket.receive()) != null) {
            final received = packet!;
            if (_messages.length >= 32 ||
                _buffered + received.data.length >
                    NetworkSocketServices.maxBufferedBytes) {
              _error = 'Fila UDP excedeu os limites.';
              _closed = true;
              socket.close();
              _wake();
              return;
            }
            final bytes = List<int>.of(received.data);
            _messages.add(<String, Object?>{
              'bytes': bytes,
              'host': received.address.address,
              'port': received.port,
            });
            _buffered += bytes.length;
            _wake();
          }
        }
      },
      onError: (Object error) {
        _error = error.toString();
        _closed = true;
        _wake();
      },
    );
  }

  final RawDatagramSocket socket;
  final Queue<Map<String, Object?>> _messages = Queue<Map<String, Object?>>();
  late final StreamSubscription<RawSocketEvent> _subscription;
  Completer<void>? _waiter;
  int _buffered = 0;
  bool _closed = false;
  String? _error;
  bool _reading = false;

  bool get closed => _closed;

  void _wake() {
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  Future<Map<String, Object?>> receive(Duration timeout) async {
    if (_reading) {
      throw const NetworkSocketException('Leituras UDP concorrentes.');
    }
    _reading = true;
    try {
      if (_messages.isEmpty && !_closed && _error == null) {
        final waiter = Completer<void>();
        _waiter = waiter;
        try {
          await waiter.future.timeout(timeout);
        } on TimeoutException {
          return <String, Object?>{
            'bytes': <int>[],
            'timed_out': true,
            'closed': false,
          };
        } finally {
          if (identical(_waiter, waiter)) _waiter = null;
        }
      }
      if (_error != null) {
        throw NetworkSocketException(_error!);
      }
      if (_messages.isEmpty) {
        return <String, Object?>{
          'bytes': <int>[],
          'timed_out': false,
          'closed': true,
        };
      }
      final value = _messages.removeFirst();
      _buffered -= (value['bytes'] as List).length;
      return <String, Object?>{
        ...value,
        'timed_out': false,
        'closed': false,
      };
    } finally {
      _reading = false;
    }
  }

  Future<void> close() async {
    _closed = true;
    _wake();
    socket.close();
    await _subscription.cancel();
    _messages.clear();
    _buffered = 0;
  }
}

class _WebSocketClient {
  _WebSocketClient(this.socket) {
    _subscription = socket.listen(
      (dynamic message) {
        if (_closed) return;
        final Map<String, Object?> parsed;
        final int size;
        if (message is String) {
          size = utf8.encode(message).length;
          parsed = <String, Object?>{'type': 'text', 'text': message};
        } else if (message is List<int>) {
          size = message.length;
          parsed = <String, Object?>{
            'type': 'binary',
            'bytes': List<int>.of(message),
          };
        } else {
          _error = 'Mensagem WebSocket inválida.';
          _closed = true;
          _wake();
          return;
        }
        if (size > NetworkSocketServices.maxWebSocketMessageBytes ||
            _messages.length >= 32 ||
            _buffered + size > NetworkSocketServices.maxBufferedBytes) {
          _error = 'Fila WebSocket excedeu os limites.';
          _closed = true;
          socket.close();
          _wake();
          return;
        }
        _messages.add(parsed);
        _buffered += size;
        _wake();
      },
      onDone: () {
        _closed = true;
        _wake();
      },
      onError: (Object error) {
        _error = error.toString();
        _closed = true;
        _wake();
      },
      cancelOnError: true,
    );
  }

  final WebSocket socket;
  final Queue<Map<String, Object?>> _messages = Queue<Map<String, Object?>>();
  late final StreamSubscription<dynamic> _subscription;
  Completer<void>? _waiter;
  bool _closed = false;
  bool _reading = false;
  int _buffered = 0;
  String? _error;

  bool get closed => _closed || socket.readyState != WebSocket.open;

  void _wake() {
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  Future<Map<String, Object?>> receive(Duration timeout) async {
    if (_reading) {
      throw const NetworkSocketException('Leituras WebSocket concorrentes.');
    }
    _reading = true;
    try {
      if (_messages.isEmpty && !_closed && _error == null) {
        final waiter = Completer<void>();
        _waiter = waiter;
        try {
          await waiter.future.timeout(timeout);
        } on TimeoutException {
          return <String, Object?>{'type': 'none', 'timed_out': true, 'closed': false};
        } finally {
          if (identical(_waiter, waiter)) _waiter = null;
        }
      }
      if (_error != null) {
        throw NetworkSocketException(_error!);
      }
      if (_messages.isEmpty) {
        return <String, Object?>{
          'type': 'none',
          'timed_out': false,
          'closed': true,
        };
      }
      final value = _messages.removeFirst();
      _buffered -= value['type'] == 'text'
          ? utf8.encode(value['text'] as String).length
          : (value['bytes'] as List).length;
      return <String, Object?>{
        ...value,
        'timed_out': false,
        'closed': false,
      };
    } finally {
      _reading = false;
    }
  }

  Future<void> close() async {
    _closed = true;
    _wake();
    await socket.close().timeout(const Duration(seconds: 3), onTimeout: () {});
    await _subscription.cancel();
    _messages.clear();
    _buffered = 0;
  }
}

int _int(Object? value, {required int min, required int max}) {
  if (value is! int || value < min || value > max) {
    throw NetworkSocketException('Número fora do intervalo: ' + value.toString());
  }
  return value;
}

Duration _timeout(Map<String, Object?> args, {required int fallback}) =>
    Duration(milliseconds: _int(args['timeout_ms'] ?? fallback, min: 1, max: 60000));

InternetAddressType _family(Object? value) {
  switch (value ?? 'ipv4') {
    case 'ipv4':
      return InternetAddressType.IPv4;
    case 'ipv6':
      return InternetAddressType.IPv6;
    case 'any':
      return InternetAddressType.any;
    default:
      throw const NetworkSocketException('Família IP inválida.');
  }
}

String _host(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 253 ||
      value != value.trim() ||
      value.contains(RegExp(r'[\s/\\]'))) {
    throw const NetworkSocketException('Host de rede inválido.');
  }
  return value;
}

List<int> _bytes(Object? value, {required int limit}) {
  if (value is String) {
    final bytes = utf8.encode(value);
    if (bytes.length > limit) {
      throw const NetworkSocketException('Dados excedem o limite.');
    }
    return bytes;
  }
  if (value is! List || value.length > limit) {
    throw const NetworkSocketException('Dados devem ser texto ou lista de bytes.');
  }
  return value.map((byte) => _int(byte, min: 0, max: 255)).toList();
}

class NetworkSocketException implements Exception {
  const NetworkSocketException(this.message);
  final String message;
  @override
  String toString() => 'NetworkSocketException: ' + message;
}
