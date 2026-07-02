import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/book.dart';
import '../models/document.dart';
import '../models/tts_engine.dart';
import '../playback/audio_handler.dart';
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

  // Chapter structure laid over the flat chunk list: chapters[i] spans the
  // chunks [chapterChunkStarts[i], chapterChunkStarts[i+1]). TTS stays
  // continuous over `chunks`; the reader works one chapter at a time.
  List<Chapter> chapters = [];
  List<int> chapterChunkStarts = [];
  double fontScale = 1.0;
  PlaybackStatus playbackStatus = PlaybackStatus.idle;
  TtsEngine selectedEngine = TtsEngine.system;
  String selectedVoice = kDefaultPiperVoice;
  // System (Android/iOS) engine voices — enumerated from the platform. Empty
  // selection means "engine default".
  List<Map<String, String>> systemVoices = [];
  String? systemVoiceName;
  String? systemVoiceLocale;
  // Last read-aloud error (e.g. Piper synthesis failure), surfaced in the UI.
  String? ttsError;
  double playbackSpeed = 1.0;
  bool piperModelDownloaded = false;
  double downloadProgress = 0.0;
  String downloadStatus = '';
  bool isDownloading = false;

  List<LibraryEntry> library = [];

  // System media session (lock screen / notification / headset controls).
  final LuJiAudioHandler _handler;
  int _lastNotifiedChapter = -1;

  StreamSubscription<PlaybackStatus>? _statusSub;
  StreamSubscription<ChunkEvent>? _chunkSub;
  StreamSubscription<String>? _errorSub;

  // True once the TTS engines and playback controller have been built. Guards
  // dispose so tearing down before (or without) init() can't touch the late
  // fields — which also makes ReaderState safe to construct in tests.
  bool _initialized = false;

  ReaderState(this._handler);

  /// Build the TTS engines + playback controller, wire the media session, and
  /// load the library. Kept separate from the constructor so this native-heavy
  /// setup only runs when the real app starts, not when a test builds the state.
  Future<void> init() async {
    _piper = await PiperTtsClient.create(voice: selectedVoice);
    _system = SystemTtsClient();
    _playback = PlaybackController(piper: _piper, system: _system);
    _initialized = true;

    // System-media controls drive the same playback.
    _handler.onPlay = () =>
        playbackStatus == PlaybackStatus.paused ? resume() : play();
    _handler.onPause = pause;
    _handler.onNext = nextChapter;
    _handler.onPrevious = prevChapter;
    _handler.onStop = () => _playback.stop();

    _statusSub = _playback.statusStream.listen((s) {
      playbackStatus = s;
      _handler.setPlaying(s == PlaybackStatus.playing,
          idle: s == PlaybackStatus.idle);
      notifyListeners();
    });
    _chunkSub = _playback.chunkStream.listen((e) {
      currentChunkIndex = e.index;
      if (currentChapterIndex != _lastNotifiedChapter) {
        _lastNotifiedChapter = currentChapterIndex;
        _handler.setNowPlaying(book: title, chapter: currentChapterTitle);
      }
      _saveProgress();
      notifyListeners();
    });
    _errorSub = _playback.errorStream.listen((msg) {
      ttsError = msg;
      notifyListeners();
    });

    piperModelDownloaded = _piper.isModelDownloaded(selectedVoice);
    await _loadLibrary();
    loadSystemVoices();
  }

  /// Enumerate the platform's TTS voices for the picker (Android/iOS only).
  Future<void> loadSystemVoices() async {
    systemVoices = await _system.getVoices();
    notifyListeners();
  }

  Future<void> setSystemVoice(String name, String locale) async {
    systemVoiceName = name;
    systemVoiceLocale = locale;
    await _system.setVoice(name, locale);
    notifyListeners();
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
    rawText = result.content;
    chapters = result.chapters;

    // Chunk each chapter and record where it begins in the flat chunk list.
    chunks = [];
    chapterChunkStarts = [];
    for (final ch in chapters) {
      chapterChunkStarts.add(chunks.length);
      chunks.addAll(chunkText(cleanText(ch.text)));
    }
    if (chunks.isEmpty) {
      chunks = chunkText(cleanText(result.content));
      chapterChunkStarts = [0];
      chapters = [Chapter(title: title, paragraphs: chunks)];
    }

    currentChunkIndex = startChunk.clamp(
      0,
      chunks.isEmpty ? 0 : chunks.length - 1,
    );

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

    _lastNotifiedChapter = currentChapterIndex;
    _handler.setNowPlaying(book: title, chapter: currentChapterTitle);
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
    await _library.save(
      existing.copyWith(
        lastChunkIndex: currentChunkIndex,
        lastOpenedMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  // ── Playback controls ─────────────────────────────────────────────────────

  Future<void> play() {
    ttsError = null;
    return _playback.play();
  }
  Future<void> pause() => _playback.pause();
  Future<void> resume() => _playback.resume();
  Future<void> seekToChunk(int index) => _playback.seekToChunk(index);

  /// Seek to [index] and immediately start playing from there.
  Future<void> seekAndPlay(int index) async {
    await _playback.seekToChunk(index);
    await _playback.play();
  }

  // ── Chapters ──────────────────────────────────────────────────────────────

  /// The chapter that contains the currently-active chunk.
  int get currentChapterIndex {
    var idx = 0;
    for (var i = 0; i < chapterChunkStarts.length; i++) {
      if (currentChunkIndex >= chapterChunkStarts[i]) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  int get _chapterStart =>
      chapterChunkStarts.isEmpty ? 0 : chapterChunkStarts[currentChapterIndex];

  int get _chapterEnd {
    final next = currentChapterIndex + 1;
    return next < chapterChunkStarts.length
        ? chapterChunkStarts[next]
        : chunks.length;
  }

  /// The chunks of the chapter being read — these are both the reading units and
  /// the TTS units, so the highlight is always exactly what's being spoken.
  List<String> get currentChapterChunks =>
      chunks.isEmpty ? const [] : chunks.sublist(_chapterStart, _chapterEnd);

  /// Index (within the current chapter) of the active chunk, or -1 if elsewhere.
  int get activeChunkInChapter {
    final local = currentChunkIndex - _chapterStart;
    return (local >= 0 && local < currentChapterChunks.length) ? local : -1;
  }

  String get currentChapterTitle =>
      currentChapterIndex < chapters.length ? chapters[currentChapterIndex].title : '';

  double get progress =>
      chunks.isEmpty ? 0 : (currentChunkIndex + 1) / chunks.length;

  Future<void> goToChapter(int index) async {
    if (index < 0 || index >= chapterChunkStarts.length) return;
    await seekToChunk(chapterChunkStarts[index]);
  }

  Future<void> nextChapter() => goToChapter(currentChapterIndex + 1);
  Future<void> prevChapter() => goToChapter(currentChapterIndex - 1);

  /// Seek to a chunk by its position WITHIN the current chapter and play (used by
  /// tap-to-read in the reader view).
  Future<void> playChapterChunk(int localIndex) =>
      seekAndPlay(_chapterStart + localIndex);

  void setFontScale(double scale) {
    fontScale = scale.clamp(0.8, 1.8);
    notifyListeners();
  }

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
    // Piper plays through just_audio, which retunes speed live. System TTS
    // can't retune the sentence it's already speaking, so restart the current
    // chunk at the new speed for that engine only.
    if (playbackStatus == PlaybackStatus.playing &&
        selectedEngine == TtsEngine.system) {
      await _playback.seekToChunk(currentChunkIndex);
      await _playback.play();
    }
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
    _errorSub?.cancel();
    if (_initialized) _playback.dispose();
    super.dispose();
  }
}
