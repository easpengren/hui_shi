import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

/// Maps (bookId, chunkIndex, voice) → cached WAV file on disk.
class TtsCache {
  Directory? _cacheDir;

  Future<Directory> _dir() async {
    if (_cacheDir != null) return _cacheDir!;
    final docs = await getApplicationDocumentsDirectory();
    _cacheDir = Directory('${docs.path}/tts_cache')
      ..createSync(recursive: true);
    return _cacheDir!;
  }

  String _hash(String bookId, int chunkIndex, String voice) {
    final raw = '$bookId::$chunkIndex::$voice';
    return sha1.convert(utf8.encode(raw)).toString();
  }

  Future<File> _pathFor(String bookId, int chunkIndex, String voice) async {
    final dir = await _dir();
    return File('${dir.path}/${_hash(bookId, chunkIndex, voice)}.wav');
  }

  Future<File?> get(String bookId, int chunkIndex, String voice) async {
    final f = await _pathFor(bookId, chunkIndex, voice);
    return (f.existsSync() && f.lengthSync() > 0) ? f : null;
  }

  Future<File> put(
      String bookId, int chunkIndex, String voice, Uint8List wav) async {
    final f = await _pathFor(bookId, chunkIndex, voice);
    await f.writeAsBytes(wav);
    return f;
  }
}
