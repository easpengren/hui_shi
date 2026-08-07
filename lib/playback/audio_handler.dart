import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

/// Bridges LuJi's read-aloud to the system media session — so the lock screen,
/// notification, Bluetooth/headset buttons, and Android Auto can control it.
///
/// This is a control + notification surface only: the callbacks drive the
/// existing PlaybackController (via ReaderState), which works for both the
/// system TTS and Piper engines. ReaderState pushes title/chapter and play
/// state in via [setNowPlaying] / [setPlaying].
class LuJiAudioHandler extends BaseAudioHandler {
  VoidCallback? onPlay;
  VoidCallback? onPause;
  VoidCallback? onNext;
  VoidCallback? onPrevious;
  VoidCallback? onStop;

  void setNowPlaying({required String book, required String chapter}) {
    final title = chapter.isNotEmpty ? chapter : (book.isNotEmpty ? book : 'Lu Ji');
    mediaItem.add(MediaItem(
      id: book.isEmpty ? 'lu_ji' : book,
      title: title,
      album: book,
      artist: 'Lu Ji',
    ));
  }

  void setPlaying(bool playing, {bool idle = false}) {
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.skipToPrevious,
        MediaAction.skipToNext,
        MediaAction.play,
        MediaAction.pause,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState:
          idle ? AudioProcessingState.idle : AudioProcessingState.ready,
      playing: playing,
    ));
  }

  @override
  Future<void> play() async => onPlay?.call();

  @override
  Future<void> pause() async => onPause?.call();

  @override
  Future<void> skipToNext() async => onNext?.call();

  @override
  Future<void> skipToPrevious() async => onPrevious?.call();

  @override
  Future<void> stop() async => onStop?.call();
}
