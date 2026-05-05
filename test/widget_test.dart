import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lu_ji/main.dart' as app;

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    app.main();
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
