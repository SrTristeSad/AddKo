import 'dart:convert';
import 'dart:typed_data';

import 'package:addko/src/ui/plugin_game_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a bounded game experience', () {
    final config = PluginGameConfig.fromMap(<String, Object?>{
      'type': 'game',
      'title': 'Demo',
      'width': 320,
      'height': 180,
      'fps': 60,
      'frame_action': 'frame',
      'pixel_art': true,
    });

    expect(config.title, 'Demo');
    expect(config.width, 320);
    expect(config.height, 180);
    expect(config.fps, 60);
    expect(config.frameAction, 'frame');
    expect(config.pixelArt, isTrue);
  });

  test('rejects unsafe game configuration', () {
    expect(
      () => PluginGameConfig.fromMap(<String, Object?>{
        'type': 'game',
        'width': 320,
        'height': 180,
        'fps': 61,
        'frame_action': '../frame',
      }),
      throwsA(isA<PluginGameException>()),
    );
  });

  test('parses draw commands and emulator framebuffer', () {
    final pixel = base64Encode(Uint8List.fromList(<int>[255, 0, 0, 255]));
    final frame = PluginGameFrame.fromObject(<String, Object?>{
      'type': 'game_frame',
      'clear': '#101820',
      'pixels': <String, Object?>{
        'format': 'rgba8888',
        'width': 1,
        'height': 1,
        'data': pixel,
      },
      'commands': <Object?>[
        <String, Object?>{
          'type': 'rect',
          'x': 10,
          'y': 12,
          'width': 30,
          'height': 20,
          'color': '#FF0000',
        },
        <String, Object?>{
          'type': 'text',
          'x': 4,
          'y': 4,
          'text': 'Lua',
          'size': 12,
          'color': '#FFFFFF',
        },
      ],
    });

    expect(frame.commands, hasLength(2));
    expect(frame.pixels, isNotNull);
    expect(frame.pixels!.bytes, <int>[255, 0, 0, 255]);
  });

  test('rejects sprite traversal', () {
    expect(
      () => PluginGameCommand.fromMap(<String, Object?>{
        'type': 'image',
        'src': 'asset:assets/../secret.png',
        'x': 0,
        'y': 0,
        'width': 32,
        'height': 32,
      }),
      throwsA(isA<PluginGameException>()),
    );
  });

  testWidgets('game surface drives Lua frames without overlapping UI widgets', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PluginGameSurface(
            virtualWidth: 320,
            virtualHeight: 180,
            fps: 30,
            frameAction: 'frame',
            pixelArt: true,
            onAction: (method, arguments) async {
              expect(method, 'frame');
              expect(arguments, hasLength(2));
              calls += 1;
              return <String, Object?>{
                'type': 'game_frame',
                'commands': <Object?>[
                  <String, Object?>{
                    'type': 'circle',
                    'x': 20,
                    'y': 20,
                    'radius': 8,
                    'color': '#00FF00',
                  },
                ],
              };
            },
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump();
    expect(calls, greaterThanOrEqualTo(1));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
