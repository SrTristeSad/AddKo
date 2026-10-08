import 'package:addko/core/ui/kodi_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('strips Kodi formatting tags while preserving text and CR', () {
    expect(
      KodiMarkup.strip('[B][COLOR red]TEA[/COLOR][/B][CR]Addon'),
      'TEA\nAddon',
    );
  });

  test('parses nested bold and color tags', () {
    final spans = KodiMarkup.parse(
      '[B][COLOR orange]Vikings[/COLOR][/B]',
      fallbackColor: Colors.white,
    ).whereType<TextSpan>().toList(growable: false);

    expect(spans, hasLength(1));
    expect(spans.single.text, 'Vikings');
    expect(spans.single.style?.fontWeight, FontWeight.w700);
    expect(spans.single.style?.color, const Color(0xffffa500));
  });

  testWidgets('KodiText renders the label without exposing markup', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: KodiText('[B][COLOR yellow]Vikings[/COLOR][/B]'),
        ),
      ),
    );

    final richFinder = find.descendant(
      of: find.byType(KodiText),
      matching: find.byType(RichText),
    );
    expect(richFinder, findsOneWidget);
    final richText = tester.widget<RichText>(richFinder);
    expect(richText.text.toPlainText(), 'Vikings');
  });
}
