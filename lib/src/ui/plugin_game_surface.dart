import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef PluginGameAction = Future<Object?> Function(
  String method,
  List<Object?> arguments,
);

class PluginGameConfig {
  const PluginGameConfig({
    required this.title,
    required this.width,
    required this.height,
    required this.fps,
    required this.frameAction,
    required this.pixelArt,
  });

  final String title;
  final int width;
  final int height;
  final int fps;
  final String frameAction;
  final bool pixelArt;

  static PluginGameConfig? tryParse(Object? value) {
    if (value is! Map) return null;
    final map = _stringMap(value);
    if (map['type'] != 'game') return null;
    return PluginGameConfig.fromMap(map);
  }

  factory PluginGameConfig.fromMap(Map<String, Object?> map) {
    if (map['type'] != 'game') {
      throw const PluginGameException('Experiência de jogo precisa usar type="game".');
    }
    final frameAction = _requiredGameString(
      map['frame_action'],
      field: 'game.frame_action',
      max: 128,
    );
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(frameAction)) {
      throw const PluginGameException('game.frame_action contém método Lua inválido.');
    }
    return PluginGameConfig(
      title: map['title'] == null
          ? 'Jogo Lua'
          : _requiredGameString(map['title'], field: 'game.title', max: 256),
      width: _boundedGameInt(
        map['width'] ?? 320,
        field: 'game.width',
        min: 64,
        max: 1920,
      ),
      height: _boundedGameInt(
        map['height'] ?? 180,
        field: 'game.height',
        min: 64,
        max: 1080,
      ),
      fps: _boundedGameInt(
        map['fps'] ?? 30,
        field: 'game.fps',
        min: 1,
        max: 60,
      ),
      frameAction: frameAction,
      pixelArt: map['pixel_art'] is bool ? map['pixel_art'] as bool : true,
    );
  }
}

class PluginGamePage extends StatelessWidget {
  const PluginGamePage({
    super.key,
    required this.config,
    required this.onAction,
    this.pluginRoot,
  });

  final PluginGameConfig config;
  final PluginGameAction onAction;
  final String? pluginRoot;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(config.title)),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final ratio = config.width / config.height;
            var width = constraints.maxWidth;
            var height = width / ratio;
            if (height > constraints.maxHeight) {
              height = constraints.maxHeight;
              width = height * ratio;
            }
            return Center(
              child: SizedBox(
                width: width,
                height: height,
                child: PluginGameSurface(
                  virtualWidth: config.width,
                  virtualHeight: config.height,
                  fps: config.fps,
                  frameAction: config.frameAction,
                  onAction: onAction,
                  pixelArt: config.pixelArt,
                  pluginRoot: pluginRoot,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class PluginGameFrame {
  const PluginGameFrame({
    required this.clearColor,
    required this.commands,
    this.pixels,
  });

  static const int maxCommands = 1024;
  static const int maxWireBytes = 2 * 1024 * 1024;
  static const int maxPixelWidth = 512;
  static const int maxPixelHeight = 512;

  final Color clearColor;
  final List<PluginGameCommand> commands;
  final PluginPixelBuffer? pixels;

  factory PluginGameFrame.fromObject(Object? value) {
    if (value is! Map) {
      throw const PluginGameException('Frame do jogo precisa ser um objeto.');
    }
    final map = _stringMap(value);
    if (map['type'] != 'game_frame') {
      throw const PluginGameException('Frame precisa usar type="game_frame".');
    }

    final encoded = utf8.encode(jsonEncode(map));
    if (encoded.length > maxWireBytes) {
      throw const PluginGameException('Frame excede o limite de 2 MiB.');
    }

    final rawCommands = map['commands'];
    if (rawCommands != null &&
        (rawCommands is! List || rawCommands.length > maxCommands)) {
      throw const PluginGameException(
        'commands precisa ser uma lista com no máximo 1024 itens.',
      );
    }

    final commands = <PluginGameCommand>[];
    if (rawCommands is List) {
      for (final raw in rawCommands) {
        if (raw is! Map) {
          throw const PluginGameException('Comando de desenho inválido.');
        }
        commands.add(PluginGameCommand.fromMap(_stringMap(raw)));
      }
    }

    return PluginGameFrame(
      clearColor: _gameColor(
        map['clear'],
        fallback: const Color(0xFF000000),
        field: 'game_frame.clear',
      ),
      commands: List<PluginGameCommand>.unmodifiable(commands),
      pixels: map['pixels'] == null
          ? null
          : PluginPixelBuffer.fromObject(map['pixels']),
    );
  }
}

class PluginPixelBuffer {
  const PluginPixelBuffer({
    required this.width,
    required this.height,
    required this.bytes,
  });

  final int width;
  final int height;
  final Uint8List bytes;

  factory PluginPixelBuffer.fromObject(Object? value) {
    if (value is! Map) {
      throw const PluginGameException('game_frame.pixels é inválido.');
    }
    final map = _stringMap(value);
    final format = map['format'];
    if (format != 'rgba8888') {
      throw const PluginGameException(
        'Somente pixel buffer format="rgba8888" é aceito.',
      );
    }

    final width = _boundedGameInt(
      map['width'],
      field: 'pixels.width',
      min: 1,
      max: PluginGameFrame.maxPixelWidth,
    );
    final height = _boundedGameInt(
      map['height'],
      field: 'pixels.height',
      min: 1,
      max: PluginGameFrame.maxPixelHeight,
    );
    final data = map['data'];
    if (data is! String || data.isEmpty) {
      throw const PluginGameException('pixels.data precisa ser Base64.');
    }

    Uint8List bytes;
    try {
      bytes = base64Decode(data);
    } on FormatException {
      throw const PluginGameException('pixels.data contém Base64 inválido.');
    }

    final expected = width * height * 4;
    if (bytes.length != expected) {
      throw PluginGameException(
        'Pixel buffer deveria ter $expected bytes, recebeu ${bytes.length}.',
      );
    }
    return PluginPixelBuffer(width: width, height: height, bytes: bytes);
  }
}

class PluginGameCommand {
  const PluginGameCommand._(this.type, this.values);

  final String type;
  final Map<String, Object?> values;

  factory PluginGameCommand.fromMap(Map<String, Object?> map) {
    final type = _requiredGameString(
      map['type'],
      field: 'command.type',
      max: 32,
    );
    const supported = <String>{
      'rect',
      'circle',
      'line',
      'text',
      'image',
    };
    if (!supported.contains(type)) {
      throw PluginGameException('Comando de desenho não suportado: $type');
    }

    final values = <String, Object?>{};
    switch (type) {
      case 'rect':
        values
          ..['x'] = _gameNumber(map['x'], field: 'rect.x')
          ..['y'] = _gameNumber(map['y'], field: 'rect.y')
          ..['width'] = _positiveGameNumber(map['width'], field: 'rect.width')
          ..['height'] =
              _positiveGameNumber(map['height'], field: 'rect.height')
          ..['color'] = _gameColor(
            map['color'],
            fallback: Colors.white,
            field: 'rect.color',
          )
          ..['fill'] = map['fill'] is bool ? map['fill'] : true
          ..['strokeWidth'] = _gameNumber(
            map['stroke_width'],
            field: 'rect.stroke_width',
            fallback: 1,
            min: 0.1,
            max: 64,
          );
      case 'circle':
        values
          ..['x'] = _gameNumber(map['x'], field: 'circle.x')
          ..['y'] = _gameNumber(map['y'], field: 'circle.y')
          ..['radius'] =
              _positiveGameNumber(map['radius'], field: 'circle.radius')
          ..['color'] = _gameColor(
            map['color'],
            fallback: Colors.white,
            field: 'circle.color',
          )
          ..['fill'] = map['fill'] is bool ? map['fill'] : true
          ..['strokeWidth'] = _gameNumber(
            map['stroke_width'],
            field: 'circle.stroke_width',
            fallback: 1,
            min: 0.1,
            max: 64,
          );
      case 'line':
        values
          ..['x1'] = _gameNumber(map['x1'], field: 'line.x1')
          ..['y1'] = _gameNumber(map['y1'], field: 'line.y1')
          ..['x2'] = _gameNumber(map['x2'], field: 'line.x2')
          ..['y2'] = _gameNumber(map['y2'], field: 'line.y2')
          ..['color'] = _gameColor(
            map['color'],
            fallback: Colors.white,
            field: 'line.color',
          )
          ..['strokeWidth'] = _gameNumber(
            map['width'],
            field: 'line.width',
            fallback: 1,
            min: 0.1,
            max: 64,
          );
      case 'text':
        values
          ..['x'] = _gameNumber(map['x'], field: 'text.x')
          ..['y'] = _gameNumber(map['y'], field: 'text.y')
          ..['text'] = _requiredGameString(
            map['text'],
            field: 'text.text',
            max: 2048,
          )
          ..['size'] = _gameNumber(
            map['size'],
            field: 'text.size',
            fallback: 16,
            min: 4,
            max: 256,
          )
          ..['color'] = _gameColor(
            map['color'],
            fallback: Colors.white,
            field: 'text.color',
          );
      case 'image':
        final source = _requiredGameString(
          map['src'],
          field: 'image.src',
          max: 512,
        );
        values
          ..['assetPath'] = parsePluginGameAssetSource(source)
          ..['x'] = _gameNumber(map['x'], field: 'image.x')
          ..['y'] = _gameNumber(map['y'], field: 'image.y')
          ..['width'] =
              _positiveGameNumber(map['width'], field: 'image.width')
          ..['height'] =
              _positiveGameNumber(map['height'], field: 'image.height');
    }
    return PluginGameCommand._(
      type,
      Map<String, Object?>.unmodifiable(values),
    );
  }

  num number(String name) => values[name]! as num;
  String string(String name) => values[name]! as String;
  Color color(String name) => values[name]! as Color;
  bool boolean(String name) => values[name]! as bool;
}

class PluginGameSurface extends StatefulWidget {
  const PluginGameSurface({
    super.key,
    required this.virtualWidth,
    required this.virtualHeight,
    required this.fps,
    required this.frameAction,
    required this.onAction,
    required this.pixelArt,
    this.pluginRoot,
  });

  final int virtualWidth;
  final int virtualHeight;
  final int fps;
  final String frameAction;
  final PluginGameAction onAction;
  final bool pixelArt;
  final String? pluginRoot;

  @override
  State<PluginGameSurface> createState() => _PluginGameSurfaceState();
}

class _PluginGameSurfaceState extends State<PluginGameSurface>
    with WidgetsBindingObserver {
  final FocusNode _focusNode = FocusNode(debugLabel: 'AddKo game surface');
  final Set<String> _keys = <String>{};
  final Map<int, _GamePointer> _pointers = <int, _GamePointer>{};
  final Map<String, ui.Image> _assetImages = <String, ui.Image>{};

  Timer? _timer;
  DateTime? _lastTick;
  PluginGameFrame _frame = const PluginGameFrame(
    clearColor: Color(0xFF000000),
    commands: <PluginGameCommand>[],
  );
  ui.Image? _pixelImage;
  bool _inFlight = false;
  bool _active = true;
  int _consecutiveErrors = 0;
  String? _fatalError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startLoop();
  }

  @override
  void didUpdateWidget(covariant PluginGameSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fps != widget.fps ||
        oldWidget.frameAction != widget.frameAction) {
      _startLoop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) {
      _startLoop();
    } else {
      _timer?.cancel();
      _timer = null;
      _keys.clear();
      _pointers.clear();
    }
  }

  void _startLoop() {
    _timer?.cancel();
    _lastTick = DateTime.now();
    final interval = Duration(
      microseconds: (Duration.microsecondsPerSecond / widget.fps).round(),
    );
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  Future<void> _tick() async {
    if (!mounted || !_active || _inFlight || _fatalError != null) return;

    final now = DateTime.now();
    final previous = _lastTick ?? now;
    _lastTick = now;
    final dt = (now.difference(previous).inMicroseconds /
            Duration.microsecondsPerSecond)
        .clamp(0.0, 0.1)
        .toDouble();

    _inFlight = true;
    try {
      final result = await widget.onAction(
        widget.frameAction,
        <Object?>[dt, _inputSnapshot()],
      );
      if (!mounted || result == null) return;

      final next = PluginGameFrame.fromObject(result);
      await _prepareFrameResources(next);
      if (!mounted) return;
      setState(() {
        _frame = next;
        _consecutiveErrors = 0;
      });
    } on Object catch (error) {
      _consecutiveErrors += 1;
      if (_consecutiveErrors >= 3 && mounted) {
        _timer?.cancel();
        setState(() {
          _fatalError =
              'Game surface pausada após 3 erros consecutivos: $error';
        });
      }
    } finally {
      _inFlight = false;
    }
  }

  Map<String, Object?> _inputSnapshot() {
    final keys = _keys.toList()..sort();
    final pointers = _pointers.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return <String, Object?>{
      'keys': keys,
      'pointers': <Object?>[
        for (final pointer in pointers)
          <String, Object?>{
            'id': pointer.id,
            'x': pointer.x,
            'y': pointer.y,
            'pressure': pointer.pressure,
            'buttons': pointer.buttons,
          },
      ],
    };
  }

  Future<void> _prepareFrameResources(PluginGameFrame frame) async {
    final pixels = frame.pixels;
    if (pixels != null) {
      final image = await _decodePixels(pixels);
      final previous = _pixelImage;
      _pixelImage = image;
      previous?.dispose();
    } else if (_pixelImage != null) {
      final previous = _pixelImage;
      _pixelImage = null;
      previous?.dispose();
    }

    final root = widget.pluginRoot;
    if (root == null || root.isEmpty) return;

    final wanted = <String>{};
    for (final command in frame.commands) {
      if (command.type == 'image') {
        wanted.add(command.string('assetPath'));
      }
    }
    for (final path in wanted) {
      if (_assetImages.containsKey(path)) continue;
      final image = await _loadAssetImage(root, path);
      if (image != null) {
        _assetImages[path] = image;
      }
    }

    final stale = _assetImages.keys.where((key) => !wanted.contains(key)).toList();
    for (final key in stale) {
      _assetImages.remove(key)?.dispose();
    }
  }

  Future<ui.Image> _decodePixels(PluginPixelBuffer buffer) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      buffer.bytes,
      buffer.width,
      buffer.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  Future<ui.Image?> _loadAssetImage(String root, String assetPath) async {
    try {
      final file = File(resolvePluginGameAsset(root, assetPath));
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        return frame.image;
      } finally {
        codec.dispose();
      }
    } on Object {
      return null;
    }
  }

  void _onKeyEvent(KeyEvent event) {
    final name = _gameKeyName(event.logicalKey);
    if (name == null) return;
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _keys.add(name);
    } else if (event is KeyUpEvent) {
      _keys.remove(name);
    }
  }

  void _pointerDown(PointerDownEvent event, Size size) {
    _focusNode.requestFocus();
    _setPointer(event, size);
  }

  void _pointerMove(PointerMoveEvent event, Size size) {
    if (_pointers.containsKey(event.pointer)) {
      _setPointer(event, size);
    }
  }

  void _setPointer(PointerEvent event, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final x = (event.localPosition.dx / size.width * widget.virtualWidth)
        .clamp(0.0, widget.virtualWidth.toDouble());
    final y = (event.localPosition.dy / size.height * widget.virtualHeight)
        .clamp(0.0, widget.virtualHeight.toDouble());
    _pointers[event.pointer] = _GamePointer(
      id: event.pointer,
      x: x.toDouble(),
      y: y.toDouble(),
      pressure: event.pressure.clamp(0.0, 1.0).toDouble(),
      buttons: event.buttons,
    );
  }

  void _pointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: widget.virtualWidth / widget.virtualHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: KeyboardListener(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: _onKeyEvent,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) => _pointerDown(event, size),
                  onPointerMove: (event) => _pointerMove(event, size),
                  onPointerUp: _pointerUp,
                  onPointerCancel: _pointerUp,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        painter: _PluginGamePainter(
                          virtualWidth: widget.virtualWidth,
                          virtualHeight: widget.virtualHeight,
                          frame: _frame,
                          pixelImage: _pixelImage,
                          assetImages: _assetImages,
                          pixelArt: widget.pixelArt,
                        ),
                      ),
                      if (_fatalError != null)
                        ColoredBox(
                          color: const Color(0xCC000000),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                _fatalError!,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _focusNode.dispose();
    _pixelImage?.dispose();
    for (final image in _assetImages.values) {
      image.dispose();
    }
    _assetImages.clear();
    super.dispose();
  }
}

class _PluginGamePainter extends CustomPainter {
  const _PluginGamePainter({
    required this.virtualWidth,
    required this.virtualHeight,
    required this.frame,
    required this.pixelImage,
    required this.assetImages,
    required this.pixelArt,
  });

  final int virtualWidth;
  final int virtualHeight;
  final PluginGameFrame frame;
  final ui.Image? pixelImage;
  final Map<String, ui.Image> assetImages;
  final bool pixelArt;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / virtualWidth;
    final sy = size.height / virtualHeight;
    canvas.save();
    canvas.scale(sx, sy);

    canvas.drawRect(
      Rect.fromLTWH(
        0,
        0,
        virtualWidth.toDouble(),
        virtualHeight.toDouble(),
      ),
      Paint()..color = frame.clearColor,
    );

    final pixels = pixelImage;
    if (pixels != null) {
      canvas.drawImageRect(
        pixels,
        Rect.fromLTWH(
          0,
          0,
          pixels.width.toDouble(),
          pixels.height.toDouble(),
        ),
        Rect.fromLTWH(
          0,
          0,
          virtualWidth.toDouble(),
          virtualHeight.toDouble(),
        ),
        Paint()
          ..filterQuality =
              pixelArt ? FilterQuality.none : FilterQuality.low,
      );
    }

    for (final command in frame.commands) {
      _drawCommand(canvas, command);
    }
    canvas.restore();
  }

  void _drawCommand(Canvas canvas, PluginGameCommand command) {
    switch (command.type) {
      case 'rect':
        final paint = Paint()
          ..color = command.color('color')
          ..style = command.boolean('fill')
              ? PaintingStyle.fill
              : PaintingStyle.stroke
          ..strokeWidth = command.number('strokeWidth').toDouble();
        canvas.drawRect(
          Rect.fromLTWH(
            command.number('x').toDouble(),
            command.number('y').toDouble(),
            command.number('width').toDouble(),
            command.number('height').toDouble(),
          ),
          paint,
        );
      case 'circle':
        final paint = Paint()
          ..color = command.color('color')
          ..style = command.boolean('fill')
              ? PaintingStyle.fill
              : PaintingStyle.stroke
          ..strokeWidth = command.number('strokeWidth').toDouble();
        canvas.drawCircle(
          Offset(
            command.number('x').toDouble(),
            command.number('y').toDouble(),
          ),
          command.number('radius').toDouble(),
          paint,
        );
      case 'line':
        canvas.drawLine(
          Offset(
            command.number('x1').toDouble(),
            command.number('y1').toDouble(),
          ),
          Offset(
            command.number('x2').toDouble(),
            command.number('y2').toDouble(),
          ),
          Paint()
            ..color = command.color('color')
            ..strokeWidth = command.number('strokeWidth').toDouble(),
        );
      case 'text':
        final painter = TextPainter(
          text: TextSpan(
            text: command.string('text'),
            style: TextStyle(
              color: command.color('color'),
              fontSize: command.number('size').toDouble(),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(
          canvas,
          Offset(
            command.number('x').toDouble(),
            command.number('y').toDouble(),
          ),
        );
      case 'image':
        final image = assetImages[command.string('assetPath')];
        if (image == null) return;
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(
            0,
            0,
            image.width.toDouble(),
            image.height.toDouble(),
          ),
          Rect.fromLTWH(
            command.number('x').toDouble(),
            command.number('y').toDouble(),
            command.number('width').toDouble(),
            command.number('height').toDouble(),
          ),
          Paint()
            ..filterQuality =
                pixelArt ? FilterQuality.none : FilterQuality.low,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _PluginGamePainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.pixelImage != pixelImage ||
        oldDelegate.assetImages != assetImages ||
        oldDelegate.pixelArt != pixelArt;
  }
}

class _GamePointer {
  const _GamePointer({
    required this.id,
    required this.x,
    required this.y,
    required this.pressure,
    required this.buttons,
  });

  final int id;
  final double x;
  final double y;
  final double pressure;
  final int buttons;
}

class PluginGameException implements Exception {
  const PluginGameException(this.message);

  final String message;

  @override
  String toString() => 'PluginGameException: $message';
}

String parsePluginGameAssetSource(String source) {
  if (!source.startsWith('asset:assets/')) {
    throw const PluginGameException(
      'Sprites precisam usar asset:assets/... dentro do pacote.',
    );
  }
  final path = source.substring('asset:'.length);
  if (path.isEmpty ||
      path.length > 512 ||
      path.startsWith('/') ||
      path.contains(r'\') ||
      path.contains(':') ||
      path.contains('\u0000')) {
    throw const PluginGameException('Caminho de sprite inválido.');
  }
  final segments = path.split('/');
  if (segments.length < 2 ||
      segments.first != 'assets' ||
      segments.any(
        (segment) => segment.isEmpty || segment == '.' || segment == '..',
      )) {
    throw const PluginGameException('Traversal em sprite local foi bloqueado.');
  }
  return segments.join('/');
}

String resolvePluginGameAsset(String root, String assetPath) {
  final suffix = assetPath.split('/').join(Platform.pathSeparator);
  return root.endsWith(Platform.pathSeparator)
      ? '$root$suffix'
      : '$root${Platform.pathSeparator}$suffix';
}

String? _gameKeyName(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.arrowUp) return 'arrowUp';
  if (key == LogicalKeyboardKey.arrowDown) return 'arrowDown';
  if (key == LogicalKeyboardKey.arrowLeft) return 'arrowLeft';
  if (key == LogicalKeyboardKey.arrowRight) return 'arrowRight';
  if (key == LogicalKeyboardKey.space) return 'space';
  if (key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter) {
    return 'enter';
  }
  if (key == LogicalKeyboardKey.escape) return 'escape';
  if (key == LogicalKeyboardKey.tab) return 'tab';
  if (key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight) {
    return 'shift';
  }
  if (key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight) {
    return 'control';
  }
  if (key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight) {
    return 'alt';
  }

  final label = key.keyLabel;
  if (RegExp(r'^[A-Za-z]$').hasMatch(label)) {
    return 'key${label.toUpperCase()}';
  }
  if (RegExp(r'^[0-9]$').hasMatch(label)) {
    return 'digit$label';
  }
  return null;
}

Map<String, Object?> _stringMap(Map raw) {
  final map = <String, Object?>{};
  for (final entry in raw.entries) {
    if (entry.key is! String) {
      throw const PluginGameException('Objeto do game contém chave inválida.');
    }
    map[entry.key as String] = entry.value;
  }
  return map;
}

String _requiredGameString(
  Object? value, {
  required String field,
  required int max,
}) {
  if (value is! String || value.isEmpty || value.length > max) {
    throw PluginGameException('$field é inválido.');
  }
  return value;
}

int _boundedGameInt(
  Object? value, {
  required String field,
  required int min,
  required int max,
}) {
  if (value is! num || !value.isFinite) {
    throw PluginGameException('$field é inválido.');
  }
  final integer = value.toInt();
  if (integer != value || integer < min || integer > max) {
    throw PluginGameException('$field está fora dos limites.');
  }
  return integer;
}

double _positiveGameNumber(
  Object? value, {
  required String field,
}) {
  return _gameNumber(value, field: field, min: 0.01, max: 100000);
}

double _gameNumber(
  Object? value, {
  required String field,
  double? fallback,
  double min = -100000,
  double max = 100000,
}) {
  if (value == null && fallback != null) return fallback;
  if (value is! num || !value.isFinite) {
    throw PluginGameException('$field é inválido.');
  }
  final result = value.toDouble();
  if (result < min || result > max) {
    throw PluginGameException('$field está fora dos limites.');
  }
  return result;
}

Color _gameColor(
  Object? value, {
  required Color fallback,
  required String field,
}) {
  if (value == null) return fallback;
  if (value is! String ||
      !RegExp(r'^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$').hasMatch(value)) {
    throw PluginGameException('$field precisa usar #RRGGBB ou #RRGGBBAA.');
  }
  final hex = value.substring(1);
  if (hex.length == 6) {
    return Color(0xFF000000 | int.parse(hex, radix: 16));
  }
  final rgb = int.parse(hex.substring(0, 6), radix: 16);
  final alpha = int.parse(hex.substring(6, 8), radix: 16);
  return Color((alpha << 24) | rgb);
}
