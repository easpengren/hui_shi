import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import '../models/tts_engine.dart';
import '../services/text_cleaner.dart';
import '../tts/piper_tts_client.dart';
import '../tts/system_tts_client.dart';

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

  TtsEngine _engine = TtsEngine.system;
  PlaybackStatus _status = PlaybackStatus.idle;
  double _uiSpeed = 1.0;

  String? _bookId;
  List<String> _chunks = [];
  int _currentIndex = 0;
  bool _stopped = false;

  ConcatenatingAudioSource? _playlist;
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
      final piperSpeed = (0.45 + (_uiSpeed * 0.9)).clamp(0.35, 2.2);
      _piper.setSpeed(piperSpeed);
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
    if (_engine == TtsEngine.system) {
      await _playSystem();
    } else {
      await _playPiper();
    }
  }

  // ── System TTS ────────────────────────────────────────────────────────────

  Future<void> _playSystem() async {
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

  // ── Piper TTS (just_audio + progressive synthesis) ─────────────────────

  Future<void> _playPiper() async {
    _setStatus(PlaybackStatus.loading);

    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());

      _playlist = ConcatenatingAudioSource(children: []);
      await _player.setAudioSource(_playlist!);

      _playerIndexSub?.cancel();
      _playerIndexSub = _player.currentIndexStream.listen((idx) {
        if (idx != null) {
          _currentIndex = _chunkOffset + idx;
          _emitChunk(_currentIndex);
        }
      });

      _playerCompleteSub?.cancel();
      _playerCompleteSub = _player.playerStateStream
          .where((s) => s.processingState == ProcessingState.completed)
          .listen((_) => _setStatus(PlaybackStatus.idle));

      // Synthesize in background; start playback as soon as first chunk lands.
      _synthesizeAndAppend(_bookId!, _currentIndex).ignore();
    } catch (e) {
      _emitError('Piper playback setup failed: $e');
      _setStatus(PlaybackStatus.idle);
    }
  }

  int _chunkOffset = 0;

  Future<void> _synthesizeAndAppend(String bookId, int startIndex) async {
    _chunkOffset = startIndex;
    bool started = false;
    try {
      for (var i = startIndex; i < _chunks.length && !_stopped; i++) {
        final sanitized = sanitizeForTts(_chunks[i]);
        if (sanitized.isEmpty) continue;
        final file = await _piper.synthesizeChunk(bookId, i, sanitized);
        if (_stopped) break;
        await _playlist!.add(AudioSource.uri(Uri.file(file.path)));
        if (!started) {
          started = true;
          _setStatus(PlaybackStatus.playing);
          await _player.play();
        }
      }
      if (!started && !_stopped) {
        _emitError('Piper failed: no speakable text chunks were generated.');
        _setStatus(PlaybackStatus.idle);
      }
    } catch (e) {
      _emitError('Piper synthesis failed: $e');
      _setStatus(PlaybackStatus.idle);
    }
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  Future<void> pause() async {
    if (_status != PlaybackStatus.playing) return;
    _setStatus(PlaybackStatus.paused);
    if (_engine == TtsEngine.piper) {
      await _player.pause();
      return;
    }

    // flutter_tts pause/resume is not reliable on Android across engines.
    // Stop current utterance and resume from the next chunk to avoid replaying
    // from the start of the same chunk after every pause.
    if (_currentIndex < _chunks.length - 1) {
      _currentIndex += 1;
      _emitChunk(_currentIndex);
    }
    _stopped = true;
    await _system.stop();
  }

  Future<void> resume() async {
    if (_status != PlaybackStatus.paused) return;
    if (_engine == TtsEngine.piper) {
      _setStatus(PlaybackStatus.playing);
      await _player.play();
      return;
    }

    _stopped = false;
    await _playSystem();
  }

  Future<void> stop() async {
    _stopped = true;
    _playerIndexSub?.cancel();
    _playerIndexSub = null;
    _playerCompleteSub?.cancel();
    _playerCompleteSub = null;
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
