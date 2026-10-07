import 'package:addko/app/addko_app.dart';
import 'package:addko/core/repositories/application/repository_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('launcher exposes Store and Settings', (tester) async {
    final registry = RepositoryRegistry();
    addTearDown(registry.dispose);

    await tester.pumpWidget(AddKoApp(repositoryRegistry: registry));

    expect(find.text('AddKo'), findsOneWidget);
    expect(find.text('Loja'), findsOneWidget);
    expect(find.text('CONFIGURAÇÕES'), findsOneWidget);
  });
}
