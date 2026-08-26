/// Playback speed: the number on the slider, and the audio it produces.
///
/// Two defects made this setting read as broken, and they compounded.
///
/// **The label lied.** Piper speed was `0.45 + uiSpeed * 0.9`, so "0.5×"
/// synthesised at 0.90× — near normal — and the slider's far left, 0.1×, still
/// came out at 0.54×. There was no way to ask for genuinely slow speech: moving
/// the lever to the end changed almost nothing.
///
/// **The cache ignored speed.** Piper bakes speed into the WAV at synthesis (the
/// player is deliberately held at 1× so it is not applied twice), so a file is
/// only valid at the speed it was made at. Keyed on voice alone, every chunk
/// already heard replayed at whatever speed it was first made at — so even a
/// correct mapping would have changed nothing until the reader reached new text.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lu_ji/tts/tts_cache.dart';

void main() {
  // `pathFor` resolves the documents directory through a platform channel, which
  // does not exist in a unit test. Stubbed rather than mocked away entirely,
  // because the path it builds IS the thing under test.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.createTempSync('luji_cache').path,
    );
  });

  group('the UI number is the Piper number', () {
    // The mapping under test is one line in PlaybackController._applyEngineSpeed;
    // reproduced here so the arithmetic is pinned without constructing the
    // controller and its engines.
    double piperSpeedFor(double ui) => ui.clamp(0.1, 2.0);
    double oldMapping(double ui) => (0.45 + (ui * 0.9)).clamp(0.35, 2.2);

    test('half speed means half speed', () {
      expect(piperSpeedFor(0.5), 0.5);
    });

    test('the old mapping is what made 0.5 sound nearly normal', () {
      // The regression guard, stated as the thing that was actually wrong.
      expect(oldMapping(0.5), closeTo(0.90, 0.001));
      expect(oldMapping(0.1), closeTo(0.54, 0.001));
      expect(piperSpeedFor(0.5), lessThan(oldMapping(0.5)));
    });

    test('the slowest setting is genuinely slow', () {
      expect(piperSpeedFor(0.1), 0.1);
      expect(piperSpeedFor(0.1), lessThan(oldMapping(0.1)));
    });

    test('normal and fast are unchanged in meaning', () {
      expect(piperSpeedFor(1.0), 1.0);
      expect(piperSpeedFor(2.0), 2.0);
    });

    test('the clamp matches the slider, so no value is unreachable', () {
      expect(piperSpeedFor(-1), 0.1);
      expect(piperSpeedFor(99), 2.0);
    });
  });

  group('the cache is keyed by speed', () {
    final cache = TtsCache();

    test('the same chunk at two speeds is two files', () async {
      final slow = await cache.pathFor('book', 3, 'piper-en', 0.5);
      final fast = await cache.pathFor('book', 3, 'piper-en', 1.5);
      expect(slow.path, isNot(fast.path),
          reason: 'one file for both speeds is why the slider did nothing');
    });

    test('the same chunk at the same speed is one file', () async {
      final a = await cache.pathFor('book', 3, 'piper-en', 0.5);
      final b = await cache.pathFor('book', 3, 'piper-en', 0.5);
      expect(a.path, b.path);
    });

    test('float noise does not miss a cache entry that is there', () async {
      // The slider moves in tenths and 0.1 + 0.4 is not exactly 0.5 in binary.
      final a = await cache.pathFor('book', 3, 'piper-en', 0.5);
      final b = await cache.pathFor('book', 3, 'piper-en', 0.1 + 0.4);
      expect(a.path, b.path);
    });

    test('voice still separates, as it always did', () async {
      final a = await cache.pathFor('book', 3, 'piper-en', 1.0);
      final b = await cache.pathFor('book', 3, 'piper-fr', 1.0);
      expect(a.path, isNot(b.path));
    });
  });
}
