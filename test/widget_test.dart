import 'package:ace/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app starts with the engine version picker', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(find.text('ACE v1'), findsOneWidget);
    expect(find.text('Turn: White'), findsOneWidget);
    expect(find.text('Playing'), findsOneWidget);
  });
}
