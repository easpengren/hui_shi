import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';
import '../models/tts_engine.dart';
import 'tts_cache.dart';
import 'wav_utils.dart';

typedef DownloadProgress = void Function(double fraction, String status);

class _ExtractRequest {
  final String archivePath;
  final String outputDir;

  const _ExtractRequest({required this.archivePath, required this.outputDir});
}

void _extractTarBz2Archive(_ExtractRequest req) {
  final archiveBytes = File(req.archivePath).readAsBytesSync();
  final bz2 = BZip2Decoder().decodeBytes(archiveBytes);
  final archive = TarDecoder().decodeBytes(bz2);

  final outDir = Directory(req.outputDir)..createSync(recursive: true);

  for (final entry in archive) {
    if (!entry.isFile) continue;
    final parts = entry.name.split('/');
    final relative = parts.length > 1 ? parts.sublist(1).join('/') : entry.name;
    if (relative.isEmpty) continue;

    final outFile = File('${outDir.path}/$relative');
    outFile.createSync(recursive: true);
    outFile.writeAsBytesSync(entry.content as List<int>);
  }
}

class PiperTtsClient {
  static bool _bindingsInitialized = false;

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

  static Future<PiperTtsClient> create({
    String voice = kDefaultPiperVoice,
    double speed = 1.0,
  }) async {
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
      // Defer engine recreation to _ensureEngine to avoid freeing while active.
      _loadedVoice = null;
    }
  }

  void setSpeed(double speed) => _speed = speed;

  String get currentVoice => _voice;

  bool isModelDownloaded(String voice) {
    final modelFile = File('${_modelsDir.path}/$voice/$voice.onnx');
    final tokensFile = File('${_modelsDir.path}/$voice/tokens.txt');
    final dataDir = Directory('${_modelsDir.path}/$voice/espeak-ng-data');
    return modelFile.existsSync() &&
        modelFile.lengthSync() > 0 &&
        tokensFile.existsSync() &&
        tokensFile.lengthSync() > 0 &&
        dataDir.existsSync();
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
    final tmpArchive = File('${_modelsDir.path}/$voice.tar.bz2.part');
    tmpArchive.createSync(recursive: true);
    final sink = tmpArchive.openWrite();
    var received = 0;

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress(
            received / total * 0.70,
            'Downloading… ${(received / 1048576).toStringAsFixed(1)} MB',
          );
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    onProgress(0.72, 'Decompressing and extracting…');

    final voiceDir = Directory('${_modelsDir.path}/$voice')
      ..createSync(recursive: true);

    try {
      await Isolate.run(
        () => _extractTarBz2Archive(
          _ExtractRequest(
            archivePath: tmpArchive.path,
            outputDir: voiceDir.path,
          ),
        ),
      );
    } finally {
      if (tmpArchive.existsSync()) {
        tmpArchive.deleteSync();
      }
    }

    onProgress(1.0, 'Done');
  }

  Future<OfflineTts> _ensureEngine(String voice) async {
    if (_tts != null && _loadedVoice == voice) return _tts!;

    if (!_bindingsInitialized) {
      initBindings();
      _bindingsInitialized = true;
    }

    _tts?.free();
    _tts = null;

    final voiceDir = '${_modelsDir.path}/$voice';
    final modelPath = '$voiceDir/$voice.onnx';
    final tokensPath = '$voiceDir/tokens.txt';
    final dataDir = '$voiceDir/espeak-ng-data';

    if (!File(modelPath).existsSync()) {
      throw Exception('Piper model not downloaded: $voice');
    }
    if (!File(tokensPath).existsSync()) {
      throw Exception('Piper model is missing tokens.txt: $voice');
    }
    if (!Directory(dataDir).existsSync()) {
      throw Exception('Piper model is missing espeak-ng-data: $voice');
    }

    final config = OfflineTtsConfig(
      model: OfflineTtsModelConfig(
        vits: OfflineTtsVitsModelConfig(
          model: modelPath,
          lexicon: '',
          tokens: tokensPath,
          dataDir: dataDir,
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
