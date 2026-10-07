import 'package:addko/app/addko_app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('launcher exposes Store and Settings', (tester) async {
    await tester.pumpWidget(const AddKoApp());

    expect(find.text('AddKo'), findsOneWidget);
    expect(find.text('Loja'), findsOneWidget);
    expect(find.text('CONFIGURAÇÕES'), findsOneWidget);
  });
}
