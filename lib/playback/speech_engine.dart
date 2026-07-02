import 'dart:async';
import 'package:flutter/foundation.dart';

enum PlaybackStatus { idle, loading, playing, paused }

/// Emitted as playback advances — [index] is the absolute chunk now being
/// spoken, [total] the chunk count.
class ChunkEvent {
  final int index;
  final int total;
  const ChunkEvent(this.index, this.total);
}

/// A read-aloud strategy over an ordered list of text chunks.
///
/// The two engines have very different playback machinery — the system engine
/// drives a blocking speak-loop through the platform TTS, while the Piper engine
/// drives a `just_audio` playlist fed by background synthesis — but both hide it
/// behind this one interface so [PlaybackController] never branches on engine
/// type. Each engine owns its own lifecycle state and reports progress through
/// [statusStream] / [chunkStream] / [errorStream].
abstract class SpeechEngine {
  /// Play/loading/paused/idle transitions for this engine.
  Stream<PlaybackStatus> get statusStream;

  /// Absolute index of the chunk currently being spoken.
  Stream<int> get chunkStream;

  /// Human-readable synthesis/playback failures, surfaced to the UI.
  Stream<String> get errorStream;

  PlaybackStatus get status;

  /// Speak [chunks] starting at [startIndex]. [bookId] keys any synthesis cache.
  Future<void> play(String bookId, List<String> chunks, int startIndex);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  void setSpeed(double speed);
  void dispose();
}

/// Shared plumbing for [SpeechEngine]s: the three broadcast streams plus status
/// tracking, so each concrete engine only implements its own playback logic.
abstract class BaseSpeechEngine implements SpeechEngine {
  final _statusCtrl = StreamController<PlaybackStatus>.broadcast();
  final _chunkCtrl = StreamController<int>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();

  PlaybackStatus _status = PlaybackStatus.idle;

  @override
  Stream<PlaybackStatus> get statusStream => _statusCtrl.stream;
  @override
  Stream<int> get chunkStream => _chunkCtrl.stream;
  @override
  Stream<String> get errorStream => _errorCtrl.stream;
  @override
  PlaybackStatus get status => _status;

  @protected
  void setStatus(PlaybackStatus s) {
    _status = s;
    _statusCtrl.add(s);
  }

  @protected
  void emitChunk(int index) => _chunkCtrl.add(index);

  @protected
  void emitError(String message) => _errorCtrl.add(message);

  @override
  @mustCallSuper
  void dispose() {
    _statusCtrl.close();
    _chunkCtrl.close();
    _errorCtrl.close();
  }
}
