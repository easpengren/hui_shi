import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'tts_cache.dart';

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
  Completer<void>? _activeSpeakCompleter;

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
    _activeSpeakCompleter = completer;
    _tts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
      if (identical(_activeSpeakCompleter, completer)) {
        _activeSpeakCompleter = null;
      }
    });
    _tts.setErrorHandler((msg) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('TTS error: $msg'));
      }
      if (identical(_activeSpeakCompleter, completer)) {
        _activeSpeakCompleter = null;
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
      if (identical(_activeSpeakCompleter, completer)) {
        _activeSpeakCompleter = null;
      }
    }
    try {
      return await completer.future;
    } finally {
      if (identical(_activeSpeakCompleter, completer)) {
        _activeSpeakCompleter = null;
      }
    }
  }

  /// Render [text] to a WAV file instead of speaking it.
  ///
  /// This is what makes read-aloud survive the screen going off. `speak()` hands
  /// the words to the platform speech engine, which plays them *outside*
  /// `just_audio` — so `audio_service`'s foreground service has no audio to hold
  /// up, Android suspends the engine on sleep, and the lock-screen controls have
  /// nothing to control. Synthesising to a file and letting `just_audio` play it
  /// makes the system engine behave exactly like Piper: real audio, inside the
  /// media session.
  ///
  /// Returns null when the device's TTS engine cannot synthesise to a file —
  /// support varies, and the caller falls back to [speak] rather than failing.
  /// Same cache and signature as `PiperTtsClient.synthesizeChunk`, so both
  /// engines share one playback path.
  Future<File?> synthesizeChunk(
    String bookId,
    int chunkIndex,
    String text,
    TtsCache cache,
  ) async {
    if (!_supported) return null;
    await init();

    const voice = 'system';
    final cached = await cache.get(bookId, chunkIndex, voice, _speed);
    if (cached != null) return cached;

    try {
      final target = await cache.pathFor(bookId, chunkIndex, voice, _speed);
      // Must be set before synthesising, or the call returns before the file
      // is written and playback gets a zero-byte source.
      await _tts.awaitSynthCompletion(true);
      // Android wants a bare filename and writes to its own directory; iOS
      // accepts a full path. Pass the full path and reconcile below.
      final result = await _tts.synthesizeToFile(text, target.path);
      if (result != 1) return null;
      if (target.existsSync() && target.lengthSync() > 0) return target;

      // Android ignored the path and used its own external files dir.
      final produced = File(target.path.split('/').last);
      if (produced.existsSync() && produced.lengthSync() > 0) return produced;
      return null;
    } catch (_) {
      // An engine without synthesizeToFile support throws rather than
      // returning a code. Not an error — the caller speaks instead.
      return null;
    }
  }

  Future<void> stop() async {
    if (_supported && _initialized) {
      await _tts.stop();
      final pending = _activeSpeakCompleter;
      if (pending != null && !pending.isCompleted) {
        pending.complete();
      }
      _activeSpeakCompleter = null;
    }
  }

  Future<void> pause() async {
    if (_supported && _initialized) await _tts.pause();
  }

  void dispose() {
    if (_supported) _tts.stop();
  }
}
