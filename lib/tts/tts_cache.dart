import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

/// Maps (bookId, chunkIndex, voice, speed) → cached WAV file on disk.
///
/// **Speed is part of the key, and leaving it out was a bug.** Piper bakes speed
/// into the audio at synthesis — the player stays at 1× precisely so speed is not
/// applied twice — so a WAV is only valid for the speed it was made at. Keyed on
/// voice alone, every chunk the owner had already heard replayed at whatever
/// speed it was first synthesised at, and moving the slider changed nothing until
/// they reached new text. The setting looked broken because for most of a book it
/// was.
///
/// System TTS goes through the same cache and has the same property, so the key
/// is shared rather than special-cased per engine.
class TtsCache {
  Directory? _cacheDir;

  Future<Directory> _dir() async {
    if (_cacheDir != null) return _cacheDir!;
    final docs = await getApplicationDocumentsDirectory();
    _cacheDir = Directory('${docs.path}/tts_cache')
      ..createSync(recursive: true);
    return _cacheDir!;
  }

  String _hash(String bookId, int chunkIndex, String voice, double speed) {
    // Two decimals: the slider moves in tenths, and a raw double would put float
    // noise in the key and miss a cache entry that is really there.
    final raw = '$bookId::$chunkIndex::$voice::${speed.toStringAsFixed(2)}';
    return sha1.convert(utf8.encode(raw)).toString();
  }

  /// Public so the system-TTS client can hand the path straight to
  /// `synthesizeToFile`, which writes the file itself rather than returning
  /// bytes for [put].
  Future<File> pathFor(
    String bookId,
    int chunkIndex,
    String voice,
    double speed,
  ) async {
    final dir = await _dir();
    return File('${dir.path}/${_hash(bookId, chunkIndex, voice, speed)}.wav');
  }

  Future<File?> get(
    String bookId,
    int chunkIndex,
    String voice,
    double speed,
  ) async {
    final f = await pathFor(bookId, chunkIndex, voice, speed);
    return (f.existsSync() && f.lengthSync() > 0) ? f : null;
  }

  Future<File> put(
    String bookId,
    int chunkIndex,
    String voice,
    double speed,
    Uint8List wav,
  ) async {
    final f = await pathFor(bookId, chunkIndex, voice, speed);
    await f.writeAsBytes(wav);
    return f;
  }
}
