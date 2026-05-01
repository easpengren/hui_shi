import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lu_ji/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const LuJiApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
