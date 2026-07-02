import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:lu_ji/main.dart';
import 'package:lu_ji/playback/audio_handler.dart';
import 'package:lu_ji/state/reader_state.dart';

void main() {
  testWidgets('App builds its MaterialApp', (tester) async {
    // Provide a ReaderState without calling init() — the smoke test just checks
    // the app scaffolds, and init() would pull in native TTS/model setup that
    // isn't available under the test binding.
    final state = ReaderState(LuJiAudioHandler());
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ReaderState>.value(
        value: state,
        child: const LuJiApp(),
      ),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
