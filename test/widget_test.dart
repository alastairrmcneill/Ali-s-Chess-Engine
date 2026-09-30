import 'package:ace/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("app starts with white to move", (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text("Turn: White"), findsOneWidget);
    expect(find.text("Start AI Game"), findsOneWidget);
  });
}
