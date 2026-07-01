import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';
import '../models/tts_engine.dart';
import 'tts_cache.dart';
import 'wav_utils.dart';

typedef DownloadProgress = void Function(double fraction, String status);

class PiperTtsClient {
  final TtsCache _cache;
  final Directory _modelsDir;

  String _voice;
  double _speed;

  OfflineTts? _tts;
  String? _loadedVoice;

  PiperTtsClient._({
    required TtsCache cache,
    required Directory modelsDir,
    required String voice,
    required double speed,
  }) : _cache = cache,
       _modelsDir = modelsDir,
       _voice = voice,
       _speed = speed;

  // sherpa-onnx FFI must have its native library bound before ANY runtime
  // object (OfflineTts) is constructed. Without this, engine creation throws
  // and Piper produces no audio — one half of the "Piper voices don't work" bug.
  static bool _bindingsInit = false;
  static void _ensureBindings() {
    if (_bindingsInit) return;
    initBindings();
    _bindingsInit = true;
  }

  static Future<PiperTtsClient> create({
    String voice = kDefaultPiperVoice,
    double speed = 1.0,
  }) async {
    _ensureBindings();
    final cache = TtsCache();
    final docs = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${docs.path}/piper_models')
      ..createSync(recursive: true);
    return PiperTtsClient._(
      cache: cache,
      modelsDir: modelsDir,
      voice: voice,
      speed: speed,
    );
  }

  void setVoice(String voice) {
    if (_voice != voice) {
      _voice = voice;
      // Release engine so it is re-created on next synthesis
      _tts?.free();
      _tts = null;
      _loadedVoice = null;
    }
  }

  void setSpeed(double speed) => _speed = speed;

  String get currentVoice => _voice;

  bool isModelDownloaded(String voice) {
    final modelFile = File('${_modelsDir.path}/$voice/$voice.onnx');
    return modelFile.existsSync() && modelFile.lengthSync() > 0;
  }

  /// Download and extract the Piper model tarball from sherpa-onnx releases.
  Future<void> downloadModel(String voice, DownloadProgress onProgress) async {
    final url =
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-$voice.tar.bz2';

    onProgress(0.0, 'Connecting...');
    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      throw Exception('Download failed: HTTP ${response.statusCode}');
    }

    final total = response.contentLength ?? 0;
    final bytes = <int>[];
    var received = 0;

    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
      received += chunk.length;
      if (total > 0) {
        onProgress(
          received / total * 0.70,
          'Downloading… ${(received / 1048576).toStringAsFixed(1)} MB',
        );
      }
    }

    onProgress(0.72, 'Decompressing…');
    final bz2 = BZip2Decoder().decodeBytes(bytes);
    onProgress(0.80, 'Extracting…');
    final archive = TarDecoder().decodeBytes(bz2);

    final voiceDir = Directory('${_modelsDir.path}/$voice')
      ..createSync(recursive: true);

    var done = 0;
    for (final entry in archive) {
      if (!entry.isFile) continue;
      // Strip leading archive directory (e.g. "vits-piper-en_US-lessac-medium/")
      final parts = entry.name.split('/');
      final relative = parts.length > 1
          ? parts.sublist(1).join('/')
          : entry.name;
      if (relative.isEmpty) continue;

      final outFile = File('${voiceDir.path}/$relative');
      outFile.createSync(recursive: true);
      outFile.writeAsBytesSync(entry.content as List<int>);
      done++;
      if (done % 25 == 0) {
        onProgress(
          0.80 + (done / archive.length) * 0.20,
          'Extracting ($done / ${archive.length})…',
        );
      }
    }

    onProgress(1.0, 'Done');
  }

  Future<OfflineTts> _ensureEngine(String voice) async {
    if (_tts != null && _loadedVoice == voice) return _tts!;

    _tts?.free();
    _tts = null;

    final voiceDir = '${_modelsDir.path}/$voice';
    final modelPath = '$voiceDir/$voice.onnx';
    final dataDir = '$voiceDir/espeak-ng-data';
    // Piper/VITS models require tokens.txt to map tokens→ids. It ships in the
    // model tarball (extracted next to the .onnx); leaving it empty was the
    // other half of the "Piper voices don't work" bug — synthesis produced
    // nothing without the token vocabulary.
    final tokensPath = '$voiceDir/tokens.txt';

    if (!File(modelPath).existsSync()) {
      throw Exception('Piper model not downloaded: $voice');
    }

    final config = OfflineTtsConfig(
      model: OfflineTtsModelConfig(
        vits: OfflineTtsVitsModelConfig(
          model: modelPath,
          lexicon: '',
          tokens: File(tokensPath).existsSync() ? tokensPath : '',
          dataDir: Directory(dataDir).existsSync() ? dataDir : '',
          noiseScale: 0.667,
          noiseScaleW: 0.8,
          lengthScale: 1.0,
        ),
        numThreads: 2,
        debug: false,
        provider: 'cpu',
      ),
      maxNumSenetences: 2,
    );

    _tts = OfflineTts(config);
    _loadedVoice = voice;
    return _tts!;
  }

  Future<File> synthesizeChunk(
    String bookId,
    int chunkIndex,
    String text,
  ) async {
    final cached = await _cache.get(bookId, chunkIndex, _voice);
    if (cached != null) return cached;

    final engine = await _ensureEngine(_voice);
    final result = engine.generate(text: text, sid: 0, speed: _speed);
    final wav = float32ToWav(result.samples, result.sampleRate);
    return _cache.put(bookId, chunkIndex, _voice, wav);
  }

  void dispose() {
    _tts?.free();
    _tts = null;
  }
}
