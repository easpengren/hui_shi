import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';

/// Wraps [FlutterTts] which uses:
///   • Android: Android TextToSpeech (Google TTS engine by default)
///   • iOS: AVSpeechSynthesizer
class SystemTtsClient {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  double _speed = 1.0;

  Future<void> init() async {
    if (_initialized) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(1.0);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _initialized = true;
  }

  Future<void> setSpeed(double speed) async {
    _speed = speed;
    if (_initialized) await _tts.setSpeechRate(speed);
  }

  /// Returns a list of available voice maps [{'name': ..., 'locale': ...}].
  Future<List<Map<String, String>>> getVoices() async {
    await init();
    final raw = await _tts.getVoices as List<dynamic>? ?? [];
    return raw
        .whereType<Map>()
        .map((v) => {
              'name': v['name']?.toString() ?? '',
              'locale': v['locale']?.toString() ?? '',
            })
        .toList();
  }

  Future<void> setVoice(String name, String locale) async {
    await init();
    await _tts.setVoice({'name': name, 'locale': locale});
  }

  /// Speak [text] and return a [Future] that completes when the utterance
  /// finishes (or throws on error).
  Future<void> speak(String text) async {
    await init();
    await _tts.setSpeechRate(_speed);
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
        completer.completeError(Exception('flutter_tts speak() returned $result'));
      }
    }
    return completer.future;
  }

  Future<void> stop() async {
    if (_initialized) await _tts.stop();
  }

  Future<void> pause() async {
    if (_initialized) await _tts.pause();
  }

  void dispose() {
    _tts.stop();
  }
}
