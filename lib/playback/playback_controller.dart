import 'dart:async';
import '../models/tts_engine.dart';
import '../tts/piper_tts_client.dart';
import '../tts/system_tts_client.dart';
import 'piper_speech_engine.dart';
import 'speech_engine.dart';
import 'system_speech_engine.dart';

// Re-export so existing callers keep importing these from playback_controller.
export 'speech_engine.dart' show PlaybackStatus, ChunkEvent;

/// Coordinates read-aloud across the available [SpeechEngine]s. It owns the
/// current book/chunk position and forwards the *active* engine's progress out
/// to the UI; the engine-specific playback machinery lives behind the
/// [SpeechEngine] strategy, so this class no longer branches on engine type.
class PlaybackController {
  PlaybackController({
    required PiperTtsClient piper,
    required SystemTtsClient system,
  }) : _piper = piper,
       _system = system {
    _engines = {
      TtsEngine.system: SystemSpeechEngine(system),
      TtsEngine.piper: PiperSpeechEngine(piper),
    };
    _active = _engines[_engineType]!;
    _bindActive();
  }

  final PiperTtsClient _piper;
  final SystemTtsClient _system;
  late final Map<TtsEngine, SpeechEngine> _engines;
  late SpeechEngine _active;
  TtsEngine _engineType = TtsEngine.system;

  String? _bookId;
  List<String> _chunks = [];
  int _currentIndex = 0;
  PlaybackStatus _status = PlaybackStatus.idle;

  final _statusCtrl = StreamController<PlaybackStatus>.broadcast();
  final _chunkCtrl = StreamController<ChunkEvent>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();

  StreamSubscription<PlaybackStatus>? _statusSub;
  StreamSubscription<int>? _chunkSub;
  StreamSubscription<String>? _errorSub;

  Stream<PlaybackStatus> get statusStream => _statusCtrl.stream;
  Stream<ChunkEvent> get chunkStream => _chunkCtrl.stream;
  Stream<String> get errorStream => _errorCtrl.stream;

  PlaybackStatus get status => _status;
  int get currentIndex => _currentIndex;
  int get totalChunks => _chunks.length;

  /// Forward the active engine's progress to this controller's own streams,
  /// re-subscribing whenever the engine changes.
  void _bindActive() {
    _statusSub?.cancel();
    _chunkSub?.cancel();
    _errorSub?.cancel();
    _statusSub = _active.statusStream.listen(_setStatus);
    _chunkSub = _active.chunkStream.listen((i) {
      _currentIndex = i;
      _chunkCtrl.add(ChunkEvent(i, _chunks.length));
    });
    _errorSub = _active.errorStream.listen(_errorCtrl.add);
  }

  void setEngine(TtsEngine engine) {
    if (engine == _engineType) return;
    _engineType = engine;
    _active = _engines[engine]!;
    _bindActive();
  }

  void setSpeed(double speed) {
    // Apply to every engine so switching engines preserves the chosen speed.
    for (final e in _engines.values) {
      e.setSpeed(speed);
    }
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
    _setStatus(PlaybackStatus.idle);
  }

  Future<void> play() async {
    if (_chunks.isEmpty) return;
    await _active.play(_bookId ?? '', _chunks, _currentIndex);
  }

  Future<void> pause() => _active.pause();
  Future<void> resume() => _active.resume();

  Future<void> stop() async {
    // Stop every engine so a mid-flight engine switch can't leave one talking.
    for (final e in _engines.values) {
      await e.stop();
    }
    _setStatus(PlaybackStatus.idle);
  }

  /// Jump to [index] and restart playback from there if it was playing.
  Future<void> seekToChunk(int index) async {
    if (index < 0 || index >= _chunks.length) return;
    final wasPlaying = _status == PlaybackStatus.playing;
    await stop();
    _currentIndex = index;
    _chunkCtrl.add(ChunkEvent(index, _chunks.length));
    if (wasPlaying) await play();
  }

  void _setStatus(PlaybackStatus s) {
    _status = s;
    _statusCtrl.add(s);
  }

  void dispose() {
    _statusSub?.cancel();
    _chunkSub?.cancel();
    _errorSub?.cancel();
    for (final e in _engines.values) {
      e.dispose();
    }
    // The shared TTS clients (also used by ReaderState for voice/model
    // management) are owned here for their whole lifetime.
    _system.dispose();
    _piper.dispose();
    _statusCtrl.close();
    _chunkCtrl.close();
    _errorCtrl.close();
  }
}
