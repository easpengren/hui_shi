import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import '../models/tts_engine.dart';
import '../services/text_cleaner.dart';
import '../tts/piper_tts_client.dart';
import '../tts/system_tts_client.dart';
import '../tts/tts_cache.dart';

enum PlaybackStatus { idle, loading, playing, paused }

class ChunkEvent {
  final int index;
  final int total;
  const ChunkEvent(this.index, this.total);
}

class PlaybackController {
  final PiperTtsClient _piper;
  final SystemTtsClient _system;
  final AudioPlayer _player = AudioPlayer();
  final TtsCache _systemCache = TtsCache();

  TtsEngine _engine = TtsEngine.system;
  PlaybackStatus _status = PlaybackStatus.idle;
  double _uiSpeed = 1.0;

  String? _bookId;
  List<String> _chunks = [];
  int _currentIndex = 0;
  bool _stopped = false;
  int _playSession = 0;

  ConcatenatingAudioSource? _playlist;
  final List<int> _playlistChunkIndexes = [];
  StreamSubscription<int?>? _playerIndexSub;
  StreamSubscription<PlayerState>? _playerCompleteSub;

  final _statusCtrl = StreamController<PlaybackStatus>.broadcast();
  final _chunkCtrl = StreamController<ChunkEvent>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();

  Stream<PlaybackStatus> get statusStream => _statusCtrl.stream;
  Stream<ChunkEvent> get chunkStream => _chunkCtrl.stream;
  Stream<String> get errorStream => _errorCtrl.stream;

  PlaybackStatus get status => _status;
  int get currentIndex => _currentIndex;
  int get totalChunks => _chunks.length;

  PlaybackController({
    required PiperTtsClient piper,
    required SystemTtsClient system,
  }) : _piper = piper,
       _system = system;

  void setEngine(TtsEngine engine) {
    _engine = engine;
    _applyEngineSpeed();
  }

  void setSpeed(double speed) {
    _uiSpeed = speed.clamp(0.1, 2.0);
    _system.setSpeed(_uiSpeed);
    _applyEngineSpeed();
  }

  void _applyEngineSpeed() {
    if (_engine == TtsEngine.piper) {
      // Piper speed is baked into synthesis. Keep player at 1x to avoid
      // double-applying speed and causing mismatch vs. system voices.
      //
      // The UI number is the Piper number. It used to be
      // `0.45 + uiSpeed * 0.9`, which made the label dishonest in the one
      // direction that matters: "0.5×" synthesised at 0.90× — near normal — and
      // the slider's far left, 0.1×, still came out at 0.54×. There was no way
      // to ask for genuinely slow speech, and the setting read as broken because
      // it was: moving the lever to the end changed almost nothing.
      //
      // Sherpa's `speed` is a direct multiplier — lower is slower — so passing
      // it through needs no mapping at all. The clamp matches the slider's own
      // range rather than a wider one, because a value the UI cannot produce is
      // a value nobody can debug.
      _piper.setSpeed(_uiSpeed.clamp(0.1, 2.0));
      _player.setSpeed(1.0);
      return;
    }

    // System TTS handles speed directly; keep audio player neutral.
    _piper.setSpeed(1.0);
    _player.setSpeed(1.0);
  }

  Future<void> load(
    String bookId,
    List<String> chunks, {
    int startIndex = 0,
  }) async {
    await stop();
    _bookId = bookId;
    _chunks = chunks;
    _currentIndex = startIndex.clamp(0, chunks.isEmpty ? 0 : chunks.length - 1);
    _stopped = false;
    _setStatus(PlaybackStatus.idle);
  }

  Future<void> play() async {
    if (_chunks.isEmpty) return;
    _stopped = false;
    // Both engines go through just_audio now. That is what makes read-aloud a
    // real media player: audio_service's foreground service is held up by
    // *playback*, so an engine that speaks outside the player leaves the
    // service with nothing to keep alive, and Android suspends it when the
    // screen goes off. The lock-screen controls were equally empty for the same
    // reason — they control the player, and the player was idle.
    //
    // _playSpoken below is kept as the fallback for devices whose TTS engine
    // cannot synthesise to a file.
    await _playSynthesized();
  }

  // ── System TTS, spoken directly (fallback only) ───────────────────────────

  Future<void> _playSpoken() async {
    _setStatus(PlaybackStatus.playing);
    try {
      for (var i = _currentIndex; i < _chunks.length; i++) {
        if (_stopped) break;
        _currentIndex = i;
        _emitChunk(i);
        final sanitized = sanitizeForTts(_chunks[i]);
        if (sanitized.isEmpty) continue;
        await _system.speak(sanitized);
        if (_stopped) break;
        // After each chunk, check if we were paused externally
        while (_status == PlaybackStatus.paused && !_stopped) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    } finally {
      if (!_stopped) _setStatus(PlaybackStatus.idle);
    }
  }

  // ── Synthesised playback (just_audio + progressive synthesis) ────────────
  //
  // Shared by both engines. Piper generates WAV via sherpa-onnx; the system
  // engine writes one with synthesizeToFile. Either way just_audio owns the
  // audio, which is what keeps the media session real.

  Future<void> _playSynthesized() async {
    final sessionId = ++_playSession;
    _setStatus(PlaybackStatus.loading);

    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());

      _playlist = ConcatenatingAudioSource(children: []);
      _playlistChunkIndexes.clear();
      await _player.setAudioSource(_playlist!);

      _playerIndexSub?.cancel();
      _playerIndexSub = _player.currentIndexStream.listen((idx) {
        if (idx != null) {
          if (idx >= 0 && idx < _playlistChunkIndexes.length) {
            _currentIndex = _playlistChunkIndexes[idx];
          } else {
            _currentIndex = _chunkOffset + idx;
          }
          _emitChunk(_currentIndex);
        }
      });

      _playerCompleteSub?.cancel();
      _playerCompleteSub = _player.playerStateStream
          .where((s) => s.processingState == ProcessingState.completed)
          .listen((_) => _setStatus(PlaybackStatus.idle));

      // Synthesize in background; start playback as soon as first chunk lands.
      _synthesizeAndAppend(_bookId!, _currentIndex, sessionId).ignore();
    } catch (e) {
      _emitError('Playback setup failed: $e');
      _setStatus(PlaybackStatus.idle);
    }
  }

  int _chunkOffset = 0;

  Future<void> _synthesizeAndAppend(
    String bookId,
    int startIndex,
    int sessionId,
  ) async {
    _chunkOffset = startIndex;
    bool started = false;
    try {
      for (var i = startIndex; i < _chunks.length && !_stopped; i++) {
        if (sessionId != _playSession) break;
        final sanitized = sanitizeForTts(_chunks[i]);
        if (sanitized.isEmpty) continue;
        final file = _engine == TtsEngine.piper
            ? await _piper.synthesizeChunk(bookId, i, sanitized)
            : await _system.synthesizeChunk(bookId, i, sanitized, _systemCache);
        if (_stopped || sessionId != _playSession) break;
        if (file == null) {
          // The device's TTS engine will not synthesise to a file. Speaking
          // directly is worse — it leaves the media session empty and dies on
          // sleep — but it is far better than silence, and it is the only
          // option on such a device.
          if (!started && sessionId == _playSession) {
            await _playSpoken();
            return;
          }
          continue;
        }
        await _playlist!.add(AudioSource.uri(Uri.file(file.path)));
        _playlistChunkIndexes.add(i);
        if (!started) {
          started = true;
          if (sessionId != _playSession) break;
          _setStatus(PlaybackStatus.playing);
          await _player.play();
        }
      }
      if (!started && !_stopped && sessionId == _playSession) {
        _emitError('No speakable text chunks were generated.');
        _setStatus(PlaybackStatus.idle);
      }
    } catch (e) {
      if (sessionId == _playSession) {
        _emitError('Speech synthesis failed: $e');
        _setStatus(PlaybackStatus.idle);
      }
    }
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  Future<void> pause() async {
    if (_status != PlaybackStatus.playing) return;
    _setStatus(PlaybackStatus.paused);
    // The player owns playback for both engines now, so pause is just pause —
    // no more skipping a chunk to work around flutter_tts's unreliable
    // pause/resume, which was only ever needed because it spoke outside the
    // player.
    await _player.pause();
    // The spoken fallback has no pausable player, so it is stopped outright.
    // Harmless when the player owns playback: flutter_tts is idle then anyway.
    await _system.stop();
  }

  Future<void> resume() async {
    if (_status != PlaybackStatus.paused) return;
    _setStatus(PlaybackStatus.playing);
    await _player.play();
  }

  Future<void> stop() async {
    _stopped = true;
    _playSession += 1;
    _playerIndexSub?.cancel();
    _playerIndexSub = null;
    _playerCompleteSub?.cancel();
    _playerCompleteSub = null;
    _playlistChunkIndexes.clear();
    await _player.stop();
    await _system.stop();
    _setStatus(PlaybackStatus.idle);
  }

  /// Jump to [index] and restart playback from there.
  Future<void> seekToChunk(int index) async {
    if (index < 0 || index >= _chunks.length) return;
    final wasPlaying = _status == PlaybackStatus.playing;
    await stop();
    _stopped = false;
    _currentIndex = index;
    _emitChunk(index);
    if (wasPlaying) await play();
  }

  void _setStatus(PlaybackStatus s) {
    _status = s;
    _statusCtrl.add(s);
  }

  void _emitChunk(int index) =>
      _chunkCtrl.add(ChunkEvent(index, _chunks.length));

  void _emitError(String message) => _errorCtrl.add(message);

  void dispose() {
    stop();
    _playerIndexSub?.cancel();
    _playerCompleteSub?.cancel();
    _player.dispose();
    _system.dispose();
    _piper.dispose();
    _statusCtrl.close();
    _chunkCtrl.close();
    _errorCtrl.close();
  }
}
