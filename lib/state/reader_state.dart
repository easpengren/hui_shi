import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

class ReaderState extends ChangeNotifier with WidgetsBindingObserver {
  // ── Dependencies ──────────────────────────────────────────────────────────
  final FileReaderService _fileReader = FileReaderService();
  final LibraryService _library = LibraryService();
  late final PiperTtsClient _piper;
  late final SystemTtsClient _system;
  late final PlaybackController _playback;
  late final Future<void> _ready;
  bool _playbackReady = false;

  // ── State ─────────────────────────────────────────────────────────────────
  LoadState loadState = LoadState.idle;
  String? errorMessage;
  String loadStatus = '';

  String bookId = '';
  String title = '';
  String rawText = '';
  List<String> chunks = [];
  int currentChunkIndex = 0;
  PlaybackStatus playbackStatus = PlaybackStatus.idle;
  TtsEngine selectedEngine = TtsEngine.system;
  String selectedVoice = kDefaultPiperVoice;
  double playbackSpeed = 0.4;
  List<Map<String, String>> systemVoices = [];
  List<Map<String, String>> systemVoiceOptions = [];
  String selectedSystemVoiceName = '';
  String selectedSystemVoiceLocale = '';
  bool piperModelDownloaded = false;
  double downloadProgress = 0.0;
  String downloadStatus = '';
  bool isDownloading = false;
  ThemeMode themeMode = ThemeMode.light;

  List<LibraryEntry> library = [];

  StreamSubscription<PlaybackStatus>? _statusSub;
  StreamSubscription<ChunkEvent>? _chunkSub;
  StreamSubscription<String>? _errorSub;

  ReaderState() {
    WidgetsBinding.instance.addObserver(this);
    _ready = _init();
  }

  Future<void> _ensureReady() async {
    await _ready;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _saveProgress();
    }
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    themeMode = _themeModeFromPref(prefs.getString('themeMode') ?? 'light');
    playbackSpeed = prefs.getDouble('playbackSpeed') ?? 0.4;
    // One-time migration: normalize previously over-corrected speed values.
    final migrated = prefs.getBool('speedMigratedV3') ?? false;
    if (!migrated && playbackSpeed < 0.2) {
      playbackSpeed = 0.4;
      await prefs.setDouble('playbackSpeed', playbackSpeed);
    }
    await prefs.setBool('speedMigratedV3', true);

    // selectedVoice may be updated below before _piper is created, so defer
    // until after prefs are read. Use a temporary late-init sequence.
    _system = SystemTtsClient();
    // _piper and _playback initialised after prefs are loaded (see below).

    final savedEngine = prefs.getString('selectedEngine');
    if (savedEngine != null) {
      selectedEngine = TtsEngine.values.firstWhere(
        (e) => e.name == savedEngine,
        orElse: () => TtsEngine.system,
      );
    }
    selectedVoice = prefs.getString('selectedPiperVoice') ?? selectedVoice;

    selectedSystemVoiceName = prefs.getString('systemVoiceName') ?? '';
    selectedSystemVoiceLocale = prefs.getString('systemVoiceLocale') ?? '';
    if (selectedSystemVoiceName.isNotEmpty) {
      await _system.setVoice(
        selectedSystemVoiceName,
        selectedSystemVoiceLocale,
      );
    }
    await _loadSystemVoices();

    _piper = await PiperTtsClient.create(
      voice: selectedVoice,
      speed: playbackSpeed,
    );
    _playback = PlaybackController(piper: _piper, system: _system);
    _playback.setSpeed(playbackSpeed);
    _playback.setEngine(selectedEngine);
    _playbackReady = true;

    _statusSub = _playback.statusStream.listen((s) {
      playbackStatus = s;
      notifyListeners();
    });
    _chunkSub = _playback.chunkStream.listen((e) {
      currentChunkIndex = e.index;
      _saveProgress();
      notifyListeners();
    });
    _errorSub = _playback.errorStream.listen((message) {
      downloadStatus = message;
      notifyListeners();
    });

    piperModelDownloaded = _piper.isModelDownloaded(selectedVoice);
    await _loadLibrary();
  }

  ThemeMode _themeModeFromPref(String value) {
    switch (value) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      case 'light':
      default:
        return ThemeMode.light;
    }
  }

  String _themeModeToPref(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
      case ThemeMode.light:
        return 'light';
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', _themeModeToPref(mode));
    notifyListeners();
  }

  Future<void> toggleThemeMode() async {
    final next = themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await setThemeMode(next);
  }

  // ── Library ───────────────────────────────────────────────────────────────

  Future<void> _loadLibrary() async {
    library = await _library.loadAll();
    notifyListeners();
  }

  Future<void> openFromLibrary(LibraryEntry entry) async {
    loadState = LoadState.loading;
    loadStatus = 'Opening ${entry.title}...';
    notifyListeners();

    final result = await _fileReader.readFromPath(
      entry.filePath,
      onProgress: (s) {
        loadStatus = s;
        notifyListeners();
      },
    );
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
    loadStatus = 'Selecting file...';
    notifyListeners();

    try {
      final result = await _fileReader.pickAndRead(
        onProgress: (s) {
          loadStatus = s;
          notifyListeners();
        },
      );
      if (result == null) {
        loadState = LoadState.idle;
        loadStatus = '';
        notifyListeners();
        return;
      }
      await _loadDocument(result);
    } catch (e, st) {
      debugPrint('[LuJi] pickFile error: $e\n$st');
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
    loadStatus = 'Preparing text...';
    notifyListeners();

    await _ensureReady();
    await _playback.stop();

    bookId = existingId ?? const Uuid().v4();
    title = result.title;
    rawText = cleanText(result.content);
    loadStatus = 'Chunking text...';
    notifyListeners();
    chunks = chunkText(rawText);

    if (chunks.isEmpty) {
      if (result.type == SupportedFileType.pdf) {
        errorMessage =
            'No readable text found in this PDF. It may be a scanned image PDF '
            'with no text layer — Lu Ji can only read PDFs that contain selectable text.';
      } else {
        errorMessage =
            'The file appears to be empty or contains no readable text.';
      }
      loadState = LoadState.error;
      notifyListeners();
      return;
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

    loadState = LoadState.ready;
    loadStatus = '';
    notifyListeners();

    if (result.type == SupportedFileType.pdf &&
        result.hasMorePdfContent &&
        result.pdfNextPage != null) {
      _continuePdfLoadInBackground(result.path, result.pdfNextPage!);
    }
  }

  Future<void> _continuePdfLoadInBackground(String path, int startPage) async {
    try {
      final remainder = await _fileReader.continuePdfExtraction(
        path,
        startPage,
        onProgress: (s) {
          // Do not switch screen state back to loading; keep this as passive status.
          downloadStatus = s;
          notifyListeners();
        },
      );
      final cleaned = cleanText(remainder);
      if (cleaned.isEmpty) return;

      final previousChunkText =
          (chunks.isNotEmpty && currentChunkIndex < chunks.length)
          ? chunks[currentChunkIndex]
          : null;

      rawText = '${rawText.trim()} $cleaned'.trim();
      final newChunks = chunkText(rawText);
      if (newChunks.isEmpty) return;

      var newIndex = currentChunkIndex;
      if (previousChunkText != null) {
        final idx = newChunks.indexOf(previousChunkText);
        if (idx >= 0) newIndex = idx;
      }
      newIndex = newIndex.clamp(0, newChunks.length - 1);

      final canReloadPlayback =
          playbackStatus != PlaybackStatus.playing &&
          playbackStatus != PlaybackStatus.loading;

      chunks = newChunks;
      currentChunkIndex = newIndex;

      if (canReloadPlayback) {
        await _ensureReady();
        await _playback.load(bookId, chunks, startIndex: currentChunkIndex);
        _playback.setEngine(selectedEngine);
        _playback.setSpeed(playbackSpeed);
      }

      final existing = library.firstWhere(
        (e) => e.id == bookId,
        orElse: () => LibraryEntry(
          id: bookId,
          title: title,
          filePath: path,
          sourceType: SupportedFileType.pdf.name,
          lastChunkIndex: currentChunkIndex,
          totalChunks: chunks.length,
          lastOpenedMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await _library.save(
        LibraryEntry(
          id: existing.id,
          title: existing.title,
          filePath: existing.filePath,
          sourceType: existing.sourceType,
          lastChunkIndex: currentChunkIndex,
          totalChunks: chunks.length,
          lastOpenedMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await _loadLibrary();

      downloadStatus = 'Finished loading full PDF.';
      notifyListeners();
    } catch (_) {
      // Keep the partial document available even if continuation fails.
    }
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

  Future<void> play() async {
    await _ensureReady();
    if (selectedEngine == TtsEngine.piper && !piperModelDownloaded) {
      downloadStatus = 'Download the selected Piper voice before playback.';
      notifyListeners();
      return;
    }

    // Anchor playback to the UI-visible chunk before starting from idle.
    if (_playback.status == PlaybackStatus.idle && chunks.isNotEmpty) {
      await _playback.seekToChunk(currentChunkIndex);
    }

    await _playback.play();
  }

  Future<void> pause() async {
    await _ensureReady();
    await _playback.pause();
  }

  Future<void> resume() async {
    await _ensureReady();
    await _playback.resume();
  }

  Future<void> stop() async {
    await _ensureReady();
    await _playback.stop();
  }

  Future<void> seekToChunk(int index) async {
    await _ensureReady();
    await _playback.seekToChunk(index);
  }

  PlaybackStatus get livePlaybackStatus =>
      _playbackReady ? _playback.status : playbackStatus;

  Future<void> togglePlayPause() async {
    await _ensureReady();
    if (chunks.isEmpty) return;

    final status = _playback.status;
    if (status == PlaybackStatus.loading) {
      await _playback.stop();
    } else if (status == PlaybackStatus.playing) {
      await _playback.pause();
    } else if (status == PlaybackStatus.paused) {
      await _playback.resume();
    } else {
      await play();
    }

    playbackStatus = _playback.status;
    notifyListeners();
  }

  /// Seek to [index] and immediately start playing from there.
  Future<void> seekAndPlay(int index) async {
    await _ensureReady();
    await _playback.seekToChunk(index);
    await _playback.play();
  }

  Future<void> _loadSystemVoices() async {
    final allAvailable = (await _system.getVoices())
        .where((v) => (v['notInstalled'] ?? 'false') != 'true')
        .toList();

    final preferredAllLocales = allAvailable
        .where((v) => _isPreferredSystemVoice(v['name'] ?? ''))
        .toList();
    final preferredEnglish = preferredAllLocales
        .where((v) => (v['locale'] ?? '').toLowerCase().startsWith('en'))
        .toList();
    final fallbackEnglish = allAvailable
        .where((v) => (v['locale'] ?? '').toLowerCase().startsWith('en'))
        .toList();

    List<Map<String, String>> shortlist;
    if (preferredEnglish.isNotEmpty) {
      shortlist = preferredEnglish;
    } else if (preferredAllLocales.isNotEmpty) {
      shortlist = preferredAllLocales;
    } else if (fallbackEnglish.isNotEmpty) {
      shortlist = fallbackEnglish;
    } else {
      shortlist = allAvailable;
    }

    shortlist.sort((a, b) {
      final aKey = '${a['locale'] ?? ''} ${a['name'] ?? ''}';
      final bKey = '${b['locale'] ?? ''} ${b['name'] ?? ''}';
      return aKey.compareTo(bKey);
    });

    systemVoices = shortlist;
    systemVoiceOptions = [
      {'id': 'default', 'label': 'Use Android default'},
      ...systemVoices.map(
        (v) => {
          'id': '${v['locale'] ?? ''}\u0001${v['name'] ?? ''}',
          'label':
              '${_isPreferredSystemVoice(v['name'] ?? '') ? '★ ' : ''}${_humanizeVoiceName(v['name'] ?? 'Unnamed', v['locale'] ?? '')}',
          'name': v['name'] ?? '',
        },
      ),
    ];

    final selectedStillPresent = systemVoices.any(
      (v) =>
          (v['name'] ?? '') == selectedSystemVoiceName &&
          (v['locale'] ?? '') == selectedSystemVoiceLocale,
    );
    if (!selectedStillPresent) {
      selectedSystemVoiceName = '';
      selectedSystemVoiceLocale = '';
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('systemVoiceName');
      await prefs.remove('systemVoiceLocale');
      await _system.setDefaultVoice();
    }

    if (selectedSystemVoiceName.isEmpty && systemVoices.isNotEmpty) {
      final best = systemVoices.first;
      selectedSystemVoiceName = best['name'] ?? '';
      selectedSystemVoiceLocale = best['locale'] ?? '';
      if (selectedSystemVoiceName.isNotEmpty) {
        await _system.setVoice(
          selectedSystemVoiceName,
          selectedSystemVoiceLocale,
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('systemVoiceName', selectedSystemVoiceName);
        await prefs.setString('systemVoiceLocale', selectedSystemVoiceLocale);
      }
    }

    notifyListeners();
  }

  /// Converts raw Android TTS voice names into human-readable labels.
  /// Examples:
  ///   en-US-Neural2-A        → "Neural2 A (en-US)"
  ///   en-us-x-iob-network    → "IOB (en-US) · Online"
  ///   en-us-x-sfg-local      → "SFG (en-US) · Offline"
  String _humanizeVoiceName(String name, String locale) {
    return _doHumanize(name, locale);
  }

  String _doHumanize(String name, String locale) {
    // Google Cloud TTS pattern: *-Neural2-A, *-WaveNet-A, *-Studio-M, etc.
    final cloudRe = RegExp(
      r'(neural2|wavenet|studio|journey|standard|news|casual)-([a-z0-9]+)$',
      caseSensitive: false,
    );
    final cloudMatch = cloudRe.firstMatch(name);
    if (cloudMatch != null) {
      final tier = _capitalizeTier(cloudMatch.group(1)!);
      final voiceId = cloudMatch.group(2)!.toUpperCase();
      return '$tier $voiceId (${_shortLocale(locale)})';
    }

    // Android opaque pattern: en-us-x-iob-network / en-us-x-sfg-local
    final opaqueRe = RegExp(
      r'x-([a-z0-9]{2,6})-(local|network)$',
      caseSensitive: false,
    );
    final opaqueMatch = opaqueRe.firstMatch(name.toLowerCase());
    if (opaqueMatch != null) {
      final code = opaqueMatch.group(1)!.toUpperCase();
      final online = opaqueMatch.group(2) == 'network';
      return '$code (${_shortLocale(locale)}) · ${online ? 'Online' : 'Offline'}';
    }

    // Fallback: just clean up with short locale prefix
    return '${_shortLocale(locale)} – $name';
  }

  String _capitalizeTier(String tier) {
    const map = {
      'neural2': 'Neural2',
      'wavenet': 'WaveNet',
      'studio': 'Studio',
      'journey': 'Journey',
      'standard': 'Standard',
      'news': 'News',
      'casual': 'Casual',
    };
    return map[tier.toLowerCase()] ??
        (tier[0].toUpperCase() + tier.substring(1));
  }

  String _shortLocale(String locale) {
    final parts = locale.replaceAll('_', '-').split('-');
    if (parts.length >= 2) {
      return '${parts[0].toLowerCase()}-${parts[1].toUpperCase()}';
    }
    return locale;
  }

  bool _isPreferredSystemVoice(String name) {
    final n = name.toLowerCase();
    return n.contains('neural') ||
        n.contains('wavenet') ||
        n.contains('studio') ||
        n.contains('journey') ||
        n.contains('premium') ||
        n.contains('high');
  }

  Future<void> setSystemVoice(String name, String locale) async {
    await _ensureReady();
    await _playback.stop();
    selectedSystemVoiceName = name;
    selectedSystemVoiceLocale = locale;
    final prefs = await SharedPreferences.getInstance();
    if (name.isEmpty) {
      await _system.setDefaultVoice();
      await prefs.remove('systemVoiceName');
      await prefs.remove('systemVoiceLocale');
    } else {
      await _system.setVoice(name, locale);
      await prefs.setString('systemVoiceName', name);
      await prefs.setString('systemVoiceLocale', locale);
    }
    notifyListeners();
  }

  Future<void> setEngine(TtsEngine engine) async {
    await _ensureReady();
    if (selectedEngine == engine) return;

    // Ensure we fully leave the previous engine before switching. Without this,
    // the old engine can keep speaking and make the toggle appear broken.
    await _playback.stop();
    selectedEngine = engine;
    piperModelDownloaded = _piper.isModelDownloaded(selectedVoice);
    _playback.setEngine(engine);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedEngine', engine.name);

    if (engine == TtsEngine.piper && !piperModelDownloaded) {
      downloadStatus =
          'Piper selected. Download the selected Piper voice to play.';
    } else if (engine == TtsEngine.system) {
      downloadStatus = selectedSystemVoiceName.isEmpty
          ? 'System TTS selected (Android default voice).'
          : 'System TTS selected (${selectedSystemVoiceLocale.isEmpty ? 'voice set' : selectedSystemVoiceLocale}).';
    } else {
      downloadStatus = 'Piper selected. Model ready.';
    }

    notifyListeners();
  }

  Future<void> setVoice(String voice) async {
    await _ensureReady();
    await _playback.stop();
    selectedVoice = voice;
    _piper.setVoice(voice);
    piperModelDownloaded = _piper.isModelDownloaded(voice);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedPiperVoice', voice);
    notifyListeners();
  }

  Future<void> setSpeed(double speed) async {
    await _ensureReady();
    playbackSpeed = speed;
    _playback.setSpeed(speed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('playbackSpeed', speed);
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

  // ── Bookmarks ─────────────────────────────────────────────────────────────

  List<Bookmark> get currentBookmarks {
    if (bookId.isEmpty) return [];
    final entry = library.firstWhere(
      (e) => e.id == bookId,
      orElse: () => LibraryEntry(
        id: '',
        title: '',
        filePath: '',
        sourceType: '',
        lastChunkIndex: 0,
        totalChunks: 0,
        lastOpenedMs: 0,
      ),
    );
    return entry.bookmarks;
  }

  Future<void> addBookmark(String label) async {
    if (bookId.isEmpty) return;
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
    final bm = Bookmark(
      chunkIndex: currentChunkIndex,
      label: label.isEmpty ? 'Chunk ${currentChunkIndex + 1}' : label,
      createdMs: DateTime.now().millisecondsSinceEpoch,
    );
    // Replace if bookmark at same chunk already exists
    final updated = [
      ...existing.bookmarks.where((b) => b.chunkIndex != currentChunkIndex),
      bm,
    ]..sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
    await _library.save(existing.copyWith(bookmarks: updated));
    await _loadLibrary();
  }

  Future<void> removeBookmark(int chunkIndex) async {
    if (bookId.isEmpty) return;
    final existing = library.firstWhere(
      (e) => e.id == bookId,
      orElse: () => LibraryEntry(
        id: '',
        title: '',
        filePath: '',
        sourceType: '',
        lastChunkIndex: 0,
        totalChunks: 0,
        lastOpenedMs: 0,
      ),
    );
    if (existing.id.isEmpty) return;
    final updated = existing.bookmarks
        .where((b) => b.chunkIndex != chunkIndex)
        .toList();
    await _library.save(existing.copyWith(bookmarks: updated));
    await _loadLibrary();
  }

  Future<void> jumpToBookmark(int chunkIndex) async {
    await seekAndPlay(chunkIndex);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusSub?.cancel();
    _chunkSub?.cancel();
    _errorSub?.cancel();
    if (_playbackReady) {
      _playback.dispose();
    }
    super.dispose();
  }
}
