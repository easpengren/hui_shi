import 'dart:async';
import '../services/text_cleaner.dart';
import '../tts/system_tts_client.dart';
import 'speech_engine.dart';

/// Read-aloud via the platform TTS (Android/iOS). There is no seekable audio
/// track — the engine simply speaks each chunk in turn and advances when the
/// utterance completes. Pause is honored between chunks by the poll loop, since
/// the platform can't reliably interrupt a sentence already in flight.
class SystemSpeechEngine extends BaseSpeechEngine {
  SystemSpeechEngine(this._client);

  final SystemTtsClient _client;

  List<String> _chunks = const [];
  bool _stopped = false;

  @override
  Future<void> play(String bookId, List<String> chunks, int startIndex) async {
    _chunks = chunks;
    _stopped = false;
    if (_chunks.isEmpty) return;

    setStatus(PlaybackStatus.playing);
    try {
      for (var i = startIndex; i < _chunks.length; i++) {
        if (_stopped) break;
        emitChunk(i);
        await _client.speak(sanitizeForTts(_chunks[i]));
        if (_stopped) break;
        // Honor an external pause between chunks — the platform TTS can't pause
        // mid-utterance, so we hold here until playback resumes or stops.
        while (status == PlaybackStatus.paused && !_stopped) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    } catch (e) {
      emitError('$e');
    } finally {
      if (!_stopped) setStatus(PlaybackStatus.idle);
    }
  }

  @override
  Future<void> pause() async {
    if (status != PlaybackStatus.playing) return;
    setStatus(PlaybackStatus.paused);
    await _client.pause();
  }

  @override
  Future<void> resume() async {
    if (status != PlaybackStatus.paused) return;
    // The speak-loop resumes on its own once the status flips back to playing.
    setStatus(PlaybackStatus.playing);
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    await _client.stop();
    setStatus(PlaybackStatus.idle);
  }

  @override
  void setSpeed(double speed) => _client.setSpeed(speed);

  @override
  void dispose() {
    _stopped = true;
    // The SystemTtsClient is shared with ReaderState (voice enumeration), so it
    // is disposed by PlaybackController, not here.
    super.dispose();
  }
}
