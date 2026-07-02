import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import '../services/text_cleaner.dart';
import '../tts/piper_tts_client.dart';
import 'speech_engine.dart';

/// Offline read-aloud via Piper (sherpa-onnx). Chunks are synthesized to WAV in
/// the background and appended to a `just_audio` playlist; playback starts the
/// moment the first chunk lands, so the reader doesn't wait for the whole
/// chapter to render. Speed is applied by the player (see [setSpeed]).
class PiperSpeechEngine extends BaseSpeechEngine {
  PiperSpeechEngine(this._client);

  final PiperTtsClient _client;
  final AudioPlayer _player = AudioPlayer();

  List<String> _chunks = const [];
  int _startIndex = 0;
  bool _stopped = false;

  ConcatenatingAudioSource? _playlist;
  StreamSubscription<int?>? _indexSub;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  Future<void> play(String bookId, List<String> chunks, int startIndex) async {
    _chunks = chunks;
    _startIndex = startIndex;
    _stopped = false;
    if (_chunks.isEmpty) return;

    setStatus(PlaybackStatus.loading);

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());

    _playlist = ConcatenatingAudioSource(children: []);
    await _player.setAudioSource(_playlist!);

    _indexSub?.cancel();
    _indexSub = _player.currentIndexStream.listen((idx) {
      if (idx != null) emitChunk(_startIndex + idx);
    });

    _stateSub?.cancel();
    _stateSub = _player.playerStateStream
        .where((s) => s.processingState == ProcessingState.completed)
        .listen((_) => setStatus(PlaybackStatus.idle));

    // Synthesize in the background; start playback as soon as chunk one lands.
    _synthesizeAndAppend(bookId).ignore();
  }

  Future<void> _synthesizeAndAppend(String bookId) async {
    var started = false;
    try {
      for (var i = _startIndex; i < _chunks.length && !_stopped; i++) {
        final file = await _client.synthesizeChunk(
          bookId,
          i,
          sanitizeForTts(_chunks[i]),
        );
        if (_stopped) break;
        await _playlist!.add(AudioSource.uri(Uri.file(file.path)));
        if (!started) {
          started = true;
          setStatus(PlaybackStatus.playing);
          await _player.play();
        }
      }
    } catch (e) {
      // Surface the failure instead of silently going quiet — this is what made
      // Piper "act like it's loading then play nothing" with no explanation.
      emitError('$e');
      setStatus(PlaybackStatus.idle);
    }
  }

  @override
  Future<void> pause() async {
    if (status != PlaybackStatus.playing) return;
    setStatus(PlaybackStatus.paused);
    await _player.pause();
  }

  @override
  Future<void> resume() async {
    if (status != PlaybackStatus.paused) return;
    setStatus(PlaybackStatus.playing);
    await _player.play();
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    _indexSub?.cancel();
    _indexSub = null;
    _stateSub?.cancel();
    _stateSub = null;
    await _player.stop();
    setStatus(PlaybackStatus.idle);
  }

  @override
  void setSpeed(double speed) {
    // Piper audio is synthesized at neutral tempo; the player is its single
    // speed control (baking speed into the WAV would double-apply it and poison
    // the book/chunk/voice-keyed cache).
    _player.setSpeed(speed);
  }

  @override
  void dispose() {
    _stopped = true;
    _indexSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    // The PiperTtsClient is shared with ReaderState (voice/model management), so
    // it is disposed by PlaybackController, not here.
    super.dispose();
  }
}
