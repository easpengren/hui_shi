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
  double _speed = 0.4;

  // FlutterTts speech-rate values are platform-dependent; on Android
  // values around 0.5 can still sound very fast. Map UI speed to a safer range.
  double _platformSpeechRate(double uiSpeed) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return (uiSpeed * 0.6).clamp(0.08, 0.9);
    }
    return uiSpeed.clamp(0.1, 1.0);
  }

  Future<void> init() async {
    if (!_supported || _initialized) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(_platformSpeechRate(_speed));
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _initialized = true;
  }

  Future<void> setSpeed(double speed) async {
    _speed = speed;
    if (_initialized) await _tts.setSpeechRate(_platformSpeechRate(speed));
  }

  /// Returns a list of available voice maps [{'name': ..., 'locale': ...}].
  Future<List<Map<String, String>>> getVoices() async {
    if (!_supported) return [];
    await init();
    final raw = await _tts.getVoices as List<dynamic>? ?? [];
    return raw
        .whereType<Map>()
        .map(
          (v) => {
            'name': v['name']?.toString() ?? '',
            'locale': v['locale']?.toString() ?? '',
            'notInstalled': v['notInstalled']?.toString() ?? 'false',
          },
        )
        .toList();
  }

  Future<void> setVoice(String name, String locale) async {
    if (!_supported) return;
    await init();
    await _tts.stop();
    final normalized = locale.replaceAll('_', '-');
    await _tts.setLanguage(normalized);
    await _tts.setVoice({'name': name, 'locale': locale});
    await _tts.setSpeechRate(_platformSpeechRate(_speed));
  }

  Future<void> setDefaultVoice() async {
    if (!_supported) return;
    await init();
    await _tts.stop();
    await _tts.setLanguage('en-US');
  }

  /// Speak [text] and return a [Future] that completes when the utterance
  /// finishes (or throws on error).
  Future<void> speak(String text) async {
    if (!_supported) return; // no-op on Linux/Windows
    await init();
    await _tts.setSpeechRate(_platformSpeechRate(_speed));
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
