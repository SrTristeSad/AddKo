import 'package:addko/src/player/addko_seek_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('drag previews position but emits only one seek on release',
      (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: AddKoSeekSlider(
                duration: const Duration(seconds: 120),
                position: Duration.zero,
                onSeek: (position) async {
                  seeks.add(position);
                },
              ),
            ),
          ),
        ),
      ),
    );

    final rect = tester.getRect(find.byType(Slider));
    final gesture = await tester.startGesture(
      Offset(rect.left + 24, rect.center.dy),
    );
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(70, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(70, 0));
    await tester.pump();

    expect(seeks, isEmpty, reason: 'Never send Range requests while dragging');
    expect(tester.widget<Slider>(find.byType(Slider)).value, greaterThan(0));

    await gesture.up();
    await tester.pumpAndSettle();

    expect(seeks, hasLength(1));
    expect(seeks.single, greaterThan(Duration.zero));
    expect(seeks.single, lessThan(const Duration(seconds: 120)));
  });

  testWidgets('seeking is disabled when duration is unknown',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddKoSeekSlider(
            duration: Duration.zero,
            position: Duration.zero,
            onSeek: (position) async {
              calls++;
            },
          ),
        ),
      ),
    );

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.onChanged, isNull);
    expect(slider.onChangeEnd, isNull);

    await tester.tap(find.byType(Slider));
    await tester.pump();
    expect(calls, 0);
  });

  testWidgets('clears stale drag preview when a different video is loaded',
      (tester) async {
    final seeks = <Duration>[];
    Future<void> build(Duration duration) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: AddKoSeekSlider(
                  duration: duration,
                  position: Duration.zero,
                  onSeek: (position) async => seeks.add(position),
                ),
              ),
            ),
          ),
        );

    await build(const Duration(seconds: 80));
    final rect = tester.getRect(find.byType(Slider));
    final gesture = await tester.startGesture(
      Offset(rect.left + 24, rect.center.dy),
    );
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, greaterThan(0));

    await build(const Duration(seconds: 30));
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0);

    await gesture.up();
    await tester.pumpAndSettle();
    // The seek from the old video must not be applied to the new video.
    expect(seeks, isEmpty);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0);
  });
}
