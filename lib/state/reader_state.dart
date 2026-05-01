import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/book.dart';
import '../models/tts_engine.dart';
import '../playback/playback_controller.dart';
import '../services/chunking_service.dart';
import '../services/file_reader_service.dart';
import '../services/library_service.dart';
import '../services/text_cleaner.dart';
import '../tts/piper_tts_client.dart';
import '../tts/system_tts_client.dart';

enum LoadState { idle, loading, ready, error }

class ReaderState extends ChangeNotifier {
  // ── Dependencies ──────────────────────────────────────────────────────────
  final FileReaderService _fileReader = FileReaderService();
  final LibraryService _library = LibraryService();
  late final PiperTtsClient _piper;
  late final SystemTtsClient _system;
  late final PlaybackController _playback;

  // ── State ─────────────────────────────────────────────────────────────────
  LoadState loadState = LoadState.idle;
  String? errorMessage;

  String bookId = '';
  String title = '';
  String rawText = '';
  List<String> chunks = [];
  int currentChunkIndex = 0;
  PlaybackStatus playbackStatus = PlaybackStatus.idle;
  TtsEngine selectedEngine = TtsEngine.system;
  String selectedVoice = kDefaultPiperVoice;
  double playbackSpeed = 1.0;
  bool piperModelDownloaded = false;
  double downloadProgress = 0.0;
  String downloadStatus = '';
  bool isDownloading = false;

  List<LibraryEntry> library = [];

  StreamSubscription<PlaybackStatus>? _statusSub;
  StreamSubscription<ChunkEvent>? _chunkSub;

  ReaderState() {
    _init();
  }

  Future<void> _init() async {
    _piper = await PiperTtsClient.create(
      voice: selectedVoice,
      speed: playbackSpeed,
    );
    _system = SystemTtsClient();
    _playback = PlaybackController(piper: _piper, system: _system);

    _statusSub = _playback.statusStream.listen((s) {
      playbackStatus = s;
      notifyListeners();
    });
    _chunkSub = _playback.chunkStream.listen((e) {
      currentChunkIndex = e.index;
      _saveProgress();
      notifyListeners();
    });

    piperModelDownloaded = _piper.isModelDownloaded(selectedVoice);
    await _loadLibrary();
  }

  // ── Library ───────────────────────────────────────────────────────────────

  Future<void> _loadLibrary() async {
    library = await _library.loadAll();
    notifyListeners();
  }

  Future<void> openFromLibrary(LibraryEntry entry) async {
    final result = await _fileReader.readFromPath(entry.filePath);
    if (result == null) {
      errorMessage = 'File not found: ${entry.filePath}';
      loadState = LoadState.error;
      notifyListeners();
      return;
    }
    await _loadDocument(
      result,
      existingId: entry.id,
      startChunk: entry.lastChunkIndex,
    );
  }

  Future<void> removeFromLibrary(String id) async {
    await _library.remove(id);
    await _loadLibrary();
  }

  // ── Document loading ──────────────────────────────────────────────────────

  Future<void> pickFile() async {
    loadState = LoadState.loading;
    errorMessage = null;
    notifyListeners();

    try {
      final result = await _fileReader.pickAndRead();
      if (result == null) {
        loadState = LoadState.idle;
        notifyListeners();
        return;
      }
      await _loadDocument(result);
    } catch (e) {
      errorMessage = e.toString();
      loadState = LoadState.error;
      notifyListeners();
    }
  }

  Future<void> _loadDocument(
    FileReadResult result, {
    String? existingId,
    int startChunk = 0,
  }) async {
    loadState = LoadState.loading;
    notifyListeners();

    await _playback.stop();

    bookId = existingId ?? const Uuid().v4();
    title = result.title;
    rawText = cleanText(result.content);
    chunks = chunkText(rawText);
    currentChunkIndex = startChunk.clamp(0, chunks.isEmpty ? 0 : chunks.length - 1);

    await _playback.load(bookId, chunks, startIndex: currentChunkIndex);
    _playback.setEngine(selectedEngine);
    _playback.setSpeed(playbackSpeed);

    final entry = LibraryEntry(
      id: bookId,
      title: title,
      filePath: result.path,
      sourceType: result.type.name,
      lastChunkIndex: currentChunkIndex,
      totalChunks: chunks.length,
      lastOpenedMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _library.save(entry);
    await _loadLibrary();

    loadState = LoadState.ready;
    notifyListeners();
  }

  Future<void> _saveProgress() async {
    if (bookId.isEmpty || chunks.isEmpty) return;
    final existing = library.firstWhere(
      (e) => e.id == bookId,
      orElse: () => LibraryEntry(
        id: bookId,
        title: title,
        filePath: '',
        sourceType: '',
        lastChunkIndex: currentChunkIndex,
        totalChunks: chunks.length,
        lastOpenedMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await _library.save(existing.copyWith(
      lastChunkIndex: currentChunkIndex,
      lastOpenedMs: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  // ── Playback controls ─────────────────────────────────────────────────────

  Future<void> play() => _playback.play();
  Future<void> pause() => _playback.pause();
  Future<void> resume() => _playback.resume();
  Future<void> seekToChunk(int index) => _playback.seekToChunk(index);

  Future<void> setEngine(TtsEngine engine) async {
    selectedEngine = engine;
    _playback.setEngine(engine);
    notifyListeners();
  }

  Future<void> setVoice(String voice) async {
    selectedVoice = voice;
    _piper.setVoice(voice);
    piperModelDownloaded = _piper.isModelDownloaded(voice);
    notifyListeners();
  }

  Future<void> setSpeed(double speed) async {
    playbackSpeed = speed;
    _playback.setSpeed(speed);
    notifyListeners();
  }

  // ── Piper model download ──────────────────────────────────────────────────

  Future<void> downloadPiperModel() async {
    if (isDownloading) return;
    isDownloading = true;
    downloadProgress = 0;
    downloadStatus = 'Starting…';
    notifyListeners();

    try {
      await _piper.downloadModel(selectedVoice, (fraction, status) {
        downloadProgress = fraction;
        downloadStatus = status;
        notifyListeners();
      });
      piperModelDownloaded = true;
    } catch (e) {
      downloadStatus = 'Failed: $e';
    } finally {
      isDownloading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _chunkSub?.cancel();
    _playback.dispose();
    super.dispose();
  }
}
