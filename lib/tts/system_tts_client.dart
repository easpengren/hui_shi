import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Wraps [FlutterTts] which uses:
///   • Android: Android TextToSpeech (Google TTS engine by default)
///   • iOS: AVSpeechSynthesizer
/// On unsupported platforms (Linux, Windows) all methods are no-ops.
class SystemTtsClient {
  // flutter_tts only supports Android, iOS, macOS, and web.
  static bool get _supported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      kIsWeb;

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  double _speed = 1.0;

  /// Map the user-facing speed (1.0 = natural) to a flutter_tts speech rate.
  /// On Android the engine's rate runs 0.0–1.0 where ~0.5 is natural speech and
  /// 1.0 is near-max — so feeding the raw 1.0 made the default read frantically.
  double _rateFor(double speed) => (speed * 0.5).clamp(0.05, 1.0);

  Future<void> init() async {
    if (!_supported || _initialized) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(_rateFor(_speed));
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _initialized = true;
  }

  Future<void> setSpeed(double speed) async {
    _speed = speed;
    if (_initialized) await _tts.setSpeechRate(_rateFor(speed));
  }

  /// Returns available English voices as [{'name': ..., 'locale': ...}],
  /// de-duplicated and sorted. The raw engine list can carry hundreds of
  /// locales plus duplicates; we keep only en-* so the picker is usable.
  Future<List<Map<String, String>>> getVoices() async {
    if (!_supported) return [];
    await init();
    final raw = await _tts.getVoices as List<dynamic>? ?? [];
    final seen = <String>{};
    final voices = <Map<String, String>>[];
    for (final v in raw.whereType<Map>()) {
      final name = v['name']?.toString() ?? '';
      final locale = v['locale']?.toString() ?? '';
      if (name.isEmpty) continue;
      if (!locale.toLowerCase().startsWith('en')) continue;
      final key = '$name|$locale';
      if (!seen.add(key)) continue;
      voices.add({'name': name, 'locale': locale});
    }
    voices.sort((a, b) {
      final byLocale = (a['locale'] ?? '').compareTo(b['locale'] ?? '');
      return byLocale != 0 ? byLocale : (a['name'] ?? '').compareTo(b['name'] ?? '');
    });
    return voices;
  }

  /// Human label for a system voice map, for the picker.
  static String voiceLabel(Map<String, String> v) {
    final name = v['name'] ?? '';
    final locale = v['locale'] ?? '';
    return locale.isEmpty ? name : '$name  ·  $locale';
  }

  Future<void> setVoice(String name, String locale) async {
    if (!_supported) return;
    await init();
    await _tts.setVoice({'name': name, 'locale': locale});
  }

  /// Speak [text] and return a [Future] that completes when the utterance
  /// finishes (or throws on error).
  Future<void> speak(String text) async {
    if (!_supported) return; // no-op on Linux/Windows
    await init();
    await _tts.setSpeechRate(_rateFor(_speed));
    final completer = Completer<void>();
    _tts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
    });
    _tts.setErrorHandler((msg) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('TTS error: $msg'));
      }
    });
    final result = await _tts.speak(text);
    if (result != 1) {
      // speak() returns 1 on success; anything else means it didn't queue.
      if (!completer.isCompleted) {
        completer.completeError(
          Exception('flutter_tts speak() returned $result'),
        );
      }
    }
    return completer.future;
  }

  Future<void> stop() async {
    if (_supported && _initialized) await _tts.stop();
  }

  Future<void> pause() async {
    if (_supported && _initialized) await _tts.pause();
  }

  void dispose() {
    if (_supported) _tts.stop();
  }
}
