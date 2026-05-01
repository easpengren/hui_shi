package com.example.ttsreader.ui

import android.app.Application
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.ttsreader.core.BookPreparer
import com.example.ttsreader.core.PreparedBook
import com.example.ttsreader.core.WordRange
import com.example.ttsreader.data.AppDatabase
import com.example.ttsreader.data.BookmarkEntity
import com.example.ttsreader.data.ChunkEntity
import com.example.ttsreader.data.NoteEntity
import com.example.ttsreader.ingest.ImportedDocument
import com.example.ttsreader.playback.AudioPlaybackEngine
import com.example.ttsreader.playback.PlaybackEngine
import com.example.ttsreader.playback.PlaybackStartResult
import com.example.ttsreader.playback.SystemTtsPlayer
import com.example.ttsreader.repo.ReaderRepository
import com.example.ttsreader.tts.CacheManager
import com.example.ttsreader.tts.FallbackTtsClient
import com.example.ttsreader.tts.PiperTtsClient
import com.example.ttsreader.tts.SystemTtsClient
import com.example.ttsreader.tts.TtsClient
import com.example.ttsreader.tts.TtsEngine
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

data class LibraryBookItem(
    val id: String,
    val title: String,
    val sourceDisplayName: String?,
    val sourceUri: String?,
    val sourceAvailable: Boolean,
    val lastCharOffset: Int,
    val lastPageIndex: Int,
    val chunkCount: Int
)

data class ReaderUiState(
    val title: String = "",
    val sourceText: String = "",
    val cleanedText: String = "",
    val bookId: String? = null,
    val chapters: List<String> = emptyList(),
    val chunks: List<ChunkEntity> = emptyList(),
    val currentChunkIndex: Int = 0,
    val activeWordRange: WordRange? = null,
    val playbackSpeed: Float = 1.0f,
    val isLoading: Boolean = false,
    val isFocusPaused: Boolean = false,
    val isBuildingAudio: Boolean = false,
    val buildProgressCurrent: Int = 0,
    val buildProgressTotal: Int = 0,
    val status: String = "Paste, share, or upload text to begin.",
    val bookmarks: List<BookmarkEntity> = emptyList(),
    val notes: List<NoteEntity> = emptyList(),
    val availableVoices: List<String> = PiperTtsClient.AVAILABLE_VOICES,
    val selectedVoice: String = PiperTtsClient.DEFAULT_VOICE,
    val selectedEngine: TtsEngine = TtsEngine.SYSTEM,
    val selectedChapter: String? = null,
    val pageTexts: List<String> = emptyList(),
    val pageStartOffsets: List<Int> = emptyList(),
    val selectedPageIndex: Int = 0,
    val lastSavedCharOffset: Int = 0,
    val autoPlayOnPageChange: Boolean = false,
    val readerFontSizeSp: Float = 19f,
    val readerLineHeightMultiplier: Float = 1.65f,
    val readerPreset: String = "Comfortable",
    val libraryBooks: List<LibraryBookItem> = emptyList()
)

class ReaderViewModel(application: Application) : AndroidViewModel(application) {
    private val _uiState = MutableStateFlow(ReaderUiState())
    val uiState: StateFlow<ReaderUiState> = _uiState.asStateFlow()

    private val db = AppDatabase.get(application)
    private val bookPreparer = BookPreparer(maxChunkLength = 250)
    private val piperTtsClient = PiperTtsClient(
        context = application,
        cacheManager = CacheManager(application),
        getVoice = { _uiState.value.selectedVoice },
        getSpeed = { _uiState.value.playbackSpeed }
    )
    private val systemTtsClient = SystemTtsClient(
        context = application,
        cacheManager = CacheManager(application),
        getSpeed = { _uiState.value.playbackSpeed }
    )

    private fun activeTtsClient(): TtsClient = when (_uiState.value.selectedEngine) {
        TtsEngine.SYSTEM -> FallbackTtsClient(systemTtsClient, piperTtsClient)
        TtsEngine.PIPER  -> FallbackTtsClient(piperTtsClient, systemTtsClient)
    }

    fun updateSelectedVoice(voice: String) {
        val safeVoice = voice.ifBlank { PiperTtsClient.DEFAULT_VOICE }
        _uiState.value = _uiState.value.copy(selectedVoice = safeVoice)
    }

    fun updateSelectedEngine(engine: TtsEngine) {
        audioPlaybackEngine.pause()
        systemTtsPlayer.pause()
        progressJob?.cancel()

        val updatedState = _uiState.value.copy(
            selectedEngine = engine,
            isFocusPaused = false
        )
        _uiState.value = updatedState

        if (updatedState.chunks.isEmpty()) return

        if (engine == TtsEngine.PIPER && updatedState.chunks.any { it.audioPath.isBlank() }) {
            _uiState.value = updatedState.copy(
                status = "Tap Build Audio to create Piper audio for this book."
            )
            return
        }

        loadSelectedPlayer(updatedState)
        _uiState.value = _uiState.value.copy(
            status = "Switched to ${engine.displayName}."
        )
    }

    private fun repository(): ReaderRepository = ReaderRepository(
        dao = db.readerDao(),
        preparer = bookPreparer,
        ttsClient = activeTtsClient()
    )

    private val audioPlaybackEngine = AudioPlaybackEngine(application)
    private val systemTtsPlayer = SystemTtsPlayer(application)

    private val activePlayer: PlaybackEngine
        get() = when (_uiState.value.selectedEngine) {
            TtsEngine.SYSTEM -> systemTtsPlayer
            TtsEngine.PIPER  -> audioPlaybackEngine
        }

    init {
        listOf(audioPlaybackEngine, systemTtsPlayer).forEach { player ->
            player.onFocusLost = {
                progressJob?.cancel()
                persistCurrentProgressNow()
                _uiState.value = _uiState.value.copy(isFocusPaused = true)
            }
            player.onFocusGained = {
                startProgressLoop()
                _uiState.value = _uiState.value.copy(isFocusPaused = false)
            }
        }
        observeLibraryBooks()
    }
    private val minPlayableChunks = 1
    private val followAlongLeadMs = 220L
    private var progressJob: Job? = null
    private var synthesisJob: Job? = null
    private var pagePlaybackEndOffset: Int? = null
    private var annotationsObservedForBookId: String? = null
    private var pendingPreparedBook: PreparedBook? = null
    private var lastProgressPersistMs: Long = 0L

    companion object {
        private const val PRESET_COMPACT = "Compact"
        private const val PRESET_COMFORTABLE = "Comfortable"
        private const val PRESET_LARGE = "Large"
        private const val PROGRESS_PERSIST_DEBOUNCE_MS = 1500L
    }

    private fun toPageTextsFromDocument(document: ImportedDocument): List<String> {
        val pages = document.pages.map { it.lines.joinToString("\n").trim() }.filter { it.isNotBlank() }
        return pages.ifEmpty { paginateText(document.previewText) }
    }

    private fun observeLibraryBooks() {
        viewModelScope.launch {
            repository().observeLibraryBooks().collectLatest { rows ->
                val mapped = rows.map { row ->
                    LibraryBookItem(
                        id = row.id,
                        title = row.title,
                        sourceDisplayName = row.sourceDisplayName,
                        sourceUri = row.sourceUri,
                        sourceAvailable = isSourceAvailable(row.sourceUri),
                        lastCharOffset = row.lastCharOffset,
                        lastPageIndex = row.lastPageIndex,
                        chunkCount = row.chunkCount
                    )
                }
                _uiState.value = _uiState.value.copy(libraryBooks = mapped)
            }
        }
    }

    private fun isSourceAvailable(sourceUri: String?): Boolean {
        if (sourceUri.isNullOrBlank()) return false
        return runCatching {
            val uri = Uri.parse(sourceUri)
            getApplication<Application>().contentResolver.openInputStream(uri)?.use { _ -> true } ?: false
        }.getOrDefault(false)
    }

    private fun paginateText(text: String): List<String> {
        val cleaned = text.trim()
        if (cleaned.isBlank()) return emptyList()
        val maxChars = 1800
        val out = mutableListOf<String>()
        var start = 0
        while (start < cleaned.length) {
            val end = (start + maxChars).coerceAtMost(cleaned.length)
            out += cleaned.substring(start, end).trim()
            start = end
        }
        return out
    }

    private fun collapseWhitespaceWithIndexMap(value: String): Pair<String, List<Int>> {
        val collapsed = StringBuilder(value.length)
        val indexMap = mutableListOf<Int>()
        var previousWasSpace = false
        value.forEachIndexed { index, ch ->
            val isSpace = ch.isWhitespace()
            if (isSpace) {
                if (!previousWasSpace) {
                    collapsed.append(' ')
                    indexMap += index
                }
            } else {
                collapsed.append(ch.lowercaseChar())
                indexMap += index
            }
            previousWasSpace = isSpace
        }
        val text = collapsed.toString()
        val startTrim = text.indexOfFirst { !it.isWhitespace() }.let { if (it < 0) 0 else it }
        val endTrim = text.indexOfLast { !it.isWhitespace() }.let { if (it < 0) -1 else it }
        if (endTrim < startTrim) return "" to emptyList()
        return text.substring(startTrim, endTrim + 1) to indexMap.subList(startTrim, endTrim + 1)
    }

    private fun buildPageStartOffsets(cleanedText: String, pageTexts: List<String>): List<Int> {
        if (pageTexts.isEmpty()) return emptyList()

        val (collapsedCleaned, collapsedToOriginal) = collapseWhitespaceWithIndexMap(cleanedText)
        if (collapsedCleaned.isBlank()) {
            return List(pageTexts.size) { index ->
                ((index.toLong() * cleanedText.length.toLong()) / pageTexts.size.toLong()).toInt()
            }
        }

        val offsets = mutableListOf<Int>()
        var searchFrom = 0
        pageTexts.forEachIndexed { index, pageText ->
            val collapsedPage = collapseWhitespaceWithIndexMap(pageText).first
            if (collapsedPage.isBlank()) {
                val fallback = ((index.toLong() * cleanedText.length.toLong()) / pageTexts.size.toLong()).toInt()
                offsets += fallback
                return@forEachIndexed
            }

            val found = collapsedCleaned.indexOf(collapsedPage, startIndex = searchFrom)
            if (found >= 0 && found < collapsedToOriginal.size) {
                offsets += collapsedToOriginal[found]
                searchFrom = found + collapsedPage.length
            } else {
                // Fallback to a deterministic proportional offset when exact text matching fails.
                val fallback = ((index.toLong() * cleanedText.length.toLong()) / pageTexts.size.toLong()).toInt()
                offsets += fallback
            }
        }
        return offsets
            .map { it.coerceIn(0, cleanedText.length.coerceAtLeast(0)) }
            .sorted()
    }

    private fun chunkIndexForPage(state: ReaderUiState, pageIndex: Int): Int {
        if (state.chunks.isEmpty()) return -1
        val safePage = pageIndex.coerceIn(0, state.pageTexts.lastIndex.coerceAtLeast(0))
        val targetOffset = state.pageStartOffsets.getOrNull(safePage)
            ?: ((safePage.toLong() * state.cleanedText.length.toLong()) / state.pageTexts.size.coerceAtLeast(1).toLong()).toInt()

        val containing = state.chunks.indexOfFirst { targetOffset in it.startOffset until it.endOffset }
        if (containing >= 0) return containing

        val found = state.chunks.indexOfFirst { it.startOffset >= targetOffset }
        return if (found >= 0) found else state.chunks.lastIndex
    }

    private fun findPageIndexForChunk(state: ReaderUiState, chunk: ChunkEntity): Int {
        val starts = state.pageStartOffsets
        if (starts.isEmpty()) return 0

        val target = chunk.startOffset
        var low = 0
        var high = starts.lastIndex
        var answer = 0
        while (low <= high) {
            val mid = (low + high) ushr 1
            if (starts[mid] <= target) {
                answer = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return answer.coerceIn(0, starts.lastIndex)
    }


    fun setStatus(message: String) {
        _uiState.value = _uiState.value.copy(status = message, isLoading = false)
    }

    fun updateTitle(value: String) {
        _uiState.value = _uiState.value.copy(title = value)
    }

    fun updateSourceText(value: String) {
        _uiState.value = _uiState.value.copy(sourceText = value)
        pendingPreparedBook = null
    }

    fun importSharedText(value: String) {
        _uiState.value = _uiState.value.copy(sourceText = value)
        pendingPreparedBook = null
    }

    fun importDocument(document: ImportedDocument) {
        viewModelScope.launch {
            val repo = repository()
            _uiState.value = _uiState.value.copy(
                isLoading = true,
                isBuildingAudio = false,
                buildProgressCurrent = 0,
                buildProgressTotal = 0,
                status = "Importing ${document.sourceType.name.lowercase()}..."
            )

            runCatching {
                val prepared = bookPreparer.prepare(document.title, document.sourceType, document.pages)
                repo.savePreparedDocument(
                    prepared,
                    sourceUri = document.sourceUri,
                    sourceDisplayName = document.sourceDisplayName
                )
                pendingPreparedBook = prepared
                val pageTexts = toPageTextsFromDocument(document)
                val pageStartOffsets = buildPageStartOffsets(prepared.cleanedText, pageTexts)
                _uiState.value = _uiState.value.copy(
                    title = prepared.title,
                    sourceText = document.previewText,
                    cleanedText = prepared.cleanedText,
                    bookId = prepared.id,
                    chapters = prepared.chapters,
                    selectedChapter = prepared.chapters.firstOrNull(),
                    pageTexts = pageTexts,
                    pageStartOffsets = pageStartOffsets,
                    selectedPageIndex = 0,
                    status = "Imported. Starting audio build...",
                    isBuildingAudio = false,
                    isLoading = false
                )
                prepareAndSynthesize()
            }.onFailure { err ->
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    isBuildingAudio = false,
                    buildProgressCurrent = 0,
                    buildProgressTotal = 0,
                    status = "Import failed: ${err.message}"
                )
            }
        }
    }

    fun prepareAndSynthesize() {
        val state = _uiState.value
        if (state.sourceText.isBlank()) {
            _uiState.value = state.copy(status = "Source text is empty.")
            return
        }

        viewModelScope.launch {
            val repo = repository()
            synthesisJob?.cancel()
            _uiState.value = _uiState.value.copy(
                isLoading = true,
                isBuildingAudio = true,
                buildProgressCurrent = 0,
                buildProgressTotal = 0,
                status = "Preparing text..."
            )

            runCatching {
                val prepared = pendingPreparedBook?.takeIf {
                    it.title == state.title || state.title.isBlank()
                } ?: repo.importAndPrepare(
                    title = state.title.ifBlank { "Untitled" },
                    text = state.sourceText
                )

                pendingPreparedBook = prepared

                // Clear stale cached audio from any previous build attempt
                CacheManager(getApplication()).clearBook(prepared.id)

                val effectivePageTexts = if (state.pageTexts.isNotEmpty()) {
                    state.pageTexts
                } else {
                    paginateText(prepared.cleanedText)
                }
                val effectivePageStartOffsets = buildPageStartOffsets(prepared.cleanedText, effectivePageTexts)

                _uiState.value = _uiState.value.copy(
                    bookId = prepared.id,
                    chunks = emptyList(),
                    cleanedText = prepared.cleanedText,
                    chapters = prepared.chapters,
                    selectedChapter = prepared.chapters.firstOrNull(),
                    pageTexts = effectivePageTexts,
                    pageStartOffsets = effectivePageStartOffsets,
                    selectedPageIndex = state.selectedPageIndex.coerceIn(0, effectivePageTexts.lastIndex.coerceAtLeast(0)),
                    buildProgressCurrent = 0,
                    buildProgressTotal = prepared.chunks.size,
                    status = "Generating fresh audio (${_uiState.value.selectedEngine.displayName}, cache cleared)..."
                )

                if (_uiState.value.selectedEngine == TtsEngine.SYSTEM) {
                    // ── System TTS path: no file synthesis, speak() directly ──────
                    synthesisJob = viewModelScope.launch {
                        runCatching {
                            val entities = repo.buildSystemChunks(prepared)
                            systemTtsPlayer.load(entities) { current ->
                                val mediaIndex = systemTtsPlayer.currentChunkIndex()
                                val pageIndex = findPageIndexForChunk(_uiState.value, current)
                                _uiState.value = _uiState.value.copy(
                                    currentChunkIndex = mediaIndex,
                                    activeWordRange = current.displayText.firstWordRange(current.startOffset),
                                    selectedPageIndex = pageIndex
                                )
                            }
                            if (annotationsObservedForBookId != prepared.id) {
                                observeAnnotations(prepared.id)
                                annotationsObservedForBookId = prepared.id
                            }
                            _uiState.value = _uiState.value.copy(
                                chunks = entities,
                                buildProgressCurrent = 0,
                                buildProgressTotal = 0,
                                isLoading = false,
                                isBuildingAudio = false,
                                status = "Ready. Press Play."
                            )
                        }.onFailure { err ->
                            _uiState.value = _uiState.value.copy(
                                isLoading = false,
                                isBuildingAudio = false,
                                buildProgressCurrent = 0,
                                buildProgressTotal = 0,
                                status = "Failed: ${err.message}"
                            )
                        }
                    }
                } else {
                // ── Piper path: parallel file synthesis ──────────────────────────
                val totalChunks = prepared.chunks.size.coerceAtLeast(1)
                var readyChunks = 0
                var playbackLoaded = false
                val readyThreshold = minOf(minPlayableChunks, totalChunks)
                val progressiveChunks = mutableListOf<ChunkEntity>()

                synthesisJob = viewModelScope.launch {
                    runCatching {
                        repo.synthesizeAllChunks(
                            book = prepared,
                            // Piper engine is not thread-safe for parallel generate() calls.
                            concurrency = 1,
                            onChunkStarted = { current, total ->
                                _uiState.value = _uiState.value.copy(
                                    buildProgressCurrent = (current - 1).coerceAtLeast(0),
                                    buildProgressTotal = total,
                                    status = "Building audio: ${current - 1}/$total (working on $current/$total)"
                                )
                            }
                        ) { entity ->
                            readyChunks += 1
                            progressiveChunks += entity

                            if (!playbackLoaded && readyChunks >= readyThreshold) {
                                audioPlaybackEngine.load(progressiveChunks.toList()) { current ->
                                    val mediaIndex = audioPlaybackEngine.currentChunkIndex()
                                    val pageIndex = findPageIndexForChunk(_uiState.value, current)
                                    _uiState.value = _uiState.value.copy(
                                        currentChunkIndex = mediaIndex,
                                        activeWordRange = current.displayText.firstWordRange(current.startOffset),
                                        selectedPageIndex = pageIndex
                                    )
                                }
                                playbackLoaded = true
                                if (annotationsObservedForBookId != prepared.id) {
                                    observeAnnotations(prepared.id)
                                    annotationsObservedForBookId = prepared.id
                                }
                            } else if (playbackLoaded) {
                                audioPlaybackEngine.appendChunk(entity)
                            }

                            _uiState.value = _uiState.value.copy(
                                chunks = progressiveChunks.toList(),
                                buildProgressCurrent = readyChunks,
                                buildProgressTotal = totalChunks,
                                status = if (readyChunks >= readyThreshold && readyChunks < totalChunks) {
                                    "Ready to play. Building audio in background: $readyChunks/$totalChunks"
                                } else {
                                    "Building audio: $readyChunks/$totalChunks chunks"
                                },
                                isLoading = readyChunks < readyThreshold,
                                isBuildingAudio = readyChunks < totalChunks
                            )
                        }

                        _uiState.value = _uiState.value.copy(
                            buildProgressCurrent = 0,
                            buildProgressTotal = 0,
                            status = "Ready. Press Play.",
                            isLoading = false,
                            isBuildingAudio = false
                        )
                    }.onFailure { err ->
                        _uiState.value = _uiState.value.copy(
                            isLoading = false,
                            isBuildingAudio = false,
                            buildProgressCurrent = 0,
                            buildProgressTotal = 0,
                            status = "Failed: ${err.message}"
                        )
                    }
                }
                } // end Piper path
            }.onFailure { err ->
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    isBuildingAudio = false,
                    buildProgressCurrent = 0,
                    buildProgressTotal = 0,
                    status = "Failed: ${err.message}"
                )
            }
        }
    }

    fun cancelBuild() {
        synthesisJob?.cancel()
        synthesisJob = null
        _uiState.value = _uiState.value.copy(
            isLoading = false,
            isBuildingAudio = false,
            buildProgressCurrent = 0,
            buildProgressTotal = 0,
            status = "Build cancelled."
        )
    }

    fun play() {
        if (_uiState.value.chunks.isEmpty()) {
            _uiState.value = _uiState.value.copy(status = "Audio is still building. Please wait for initial chunks.")
            return
        }
        pagePlaybackEndOffset = null
        when (activePlayer.play()) {
            PlaybackStartResult.GRANTED -> {
                _uiState.value = _uiState.value.copy(isFocusPaused = false)
                startProgressLoop()
            }
            PlaybackStartResult.DELAYED -> {
                _uiState.value = _uiState.value.copy(
                    isFocusPaused = true,
                    status = "Waiting for audio focus. Close assistant audio and playback will resume automatically."
                )
            }
            PlaybackStartResult.FAILED -> {
                _uiState.value = _uiState.value.copy(
                    isFocusPaused = true,
                    status = "Could not get audio focus. Pause other audio apps and try Play again."
                )
            }
        }
    }

    fun pause() {
        pagePlaybackEndOffset = null
        persistCurrentProgressNow()
        activePlayer.pause()
        progressJob?.cancel()
        _uiState.value = _uiState.value.copy(isFocusPaused = false)
    }

    fun setSpeed(speed: Float) {
        activePlayer.setSpeed(speed)
        _uiState.value = _uiState.value.copy(playbackSpeed = speed)
    }

    fun setAutoPlayOnPageChange(enabled: Boolean) {
        _uiState.value = _uiState.value.copy(
            autoPlayOnPageChange = enabled,
            status = if (enabled) {
                "Page buttons set to Auto-play"
            } else {
                "Page buttons set to Browse only"
            }
        )
    }

    fun setReaderFontSize(sizeSp: Float) {
        _uiState.value = _uiState.value.copy(
            readerFontSizeSp = sizeSp,
            readerPreset = "Custom"
        )
    }

    fun setReaderLineHeight(multiplier: Float) {
        _uiState.value = _uiState.value.copy(
            readerLineHeightMultiplier = multiplier,
            readerPreset = "Custom"
        )
    }

    fun setReaderPreset(preset: String) {
        val (fontSize, lineHeight) = when (preset) {
            PRESET_COMPACT -> 16f to 1.35f
            PRESET_LARGE -> 22f to 1.8f
            else -> 19f to 1.65f
        }
        _uiState.value = _uiState.value.copy(
            readerPreset = when (preset) {
                PRESET_COMPACT -> PRESET_COMPACT
                PRESET_LARGE -> PRESET_LARGE
                else -> PRESET_COMFORTABLE
            },
            readerFontSizeSp = fontSize,
            readerLineHeightMultiplier = lineHeight
        )
    }

    fun openLibraryBook(bookId: String) {
        viewModelScope.launch {
            val repo = repository()
            val book = repo.getBook(bookId)
            val chunks = repo.getChunksForBook(bookId)
            if (book == null) {
                _uiState.value = _uiState.value.copy(status = "Could not open saved book.")
                return@launch
            }

            val pageTexts = paginateText(book.cleanedText)
            val pageStarts = buildPageStartOffsets(book.cleanedText, pageTexts)
            val resumePage = book.lastPageIndex.coerceIn(0, pageTexts.lastIndex.coerceAtLeast(0))
            val resumeChunkIndex = chunks.indexOfLast { it.startOffset <= book.lastCharOffset }
                .let { if (it >= 0) it else 0 }

            if (chunks.isNotEmpty()) {
                val hasAudio = chunks.all { it.audioPath.isNotEmpty() }
                if (_uiState.value.selectedEngine == TtsEngine.PIPER && !hasAudio) {
                    _uiState.value = _uiState.value.copy(
                        title = book.title,
                        sourceText = book.cleanedText,
                        cleanedText = book.cleanedText,
                        bookId = book.id,
                        chapters = chunks.mapNotNull { it.chapterTitle }.distinct(),
                        chunks = chunks,
                        pageTexts = pageTexts,
                        pageStartOffsets = pageStarts,
                        selectedPageIndex = resumePage,
                        status = "Switch to System engine or tap Generate to build Piper audio."
                    )
                    return@launch
                }
            }

            val openedState = _uiState.value.copy(
                title = book.title,
                sourceText = book.cleanedText,
                cleanedText = book.cleanedText,
                bookId = book.id,
                chapters = chunks.mapNotNull { it.chapterTitle }.distinct(),
                selectedChapter = chunks.getOrNull(resumeChunkIndex)?.chapterTitle,
                chunks = chunks,
                currentChunkIndex = resumeChunkIndex,
                activeWordRange = chunks.getOrNull(resumeChunkIndex)?.displayText?.wordRangeNearOffset(
                    globalStart = chunks.getOrNull(resumeChunkIndex)?.startOffset ?: 0,
                    targetOffset = book.lastCharOffset
                ),
                pageTexts = pageTexts,
                pageStartOffsets = pageStarts,
                selectedPageIndex = resumePage,
                lastSavedCharOffset = book.lastCharOffset,
                status = "Opened from library: ${book.title} (using saved audio chunks)"
            )
            _uiState.value = openedState

            if (chunks.isNotEmpty()) {
                loadSelectedPlayer(openedState)
            }

            if (annotationsObservedForBookId != book.id) {
                observeAnnotations(book.id)
                annotationsObservedForBookId = book.id
            }
        }
    }

    private fun persistReadingProgress(state: ReaderUiState, chunk: ChunkEntity) {
        val bookId = state.bookId ?: return
        val now = System.currentTimeMillis()
        if (now - lastProgressPersistMs < PROGRESS_PERSIST_DEBOUNCE_MS) return
        lastProgressPersistMs = now
        val charOffset = state.activeWordRange?.startOffset ?: chunk.startOffset

        _uiState.value = _uiState.value.copy(lastSavedCharOffset = charOffset)

        viewModelScope.launch {
            repository().updateBookProgress(
                bookId = bookId,
                charOffset = charOffset,
                pageIndex = state.selectedPageIndex,
                playedAt = now,
                openedAt = now
            )
        }
    }

    private fun persistCurrentProgressNow() {
        val state = _uiState.value
        val bookId = state.bookId ?: return
        val chunk = state.chunks.getOrNull(activePlayer.currentChunkIndex()) ?: return
        val charOffset = state.activeWordRange?.startOffset ?: chunk.startOffset
        val now = System.currentTimeMillis()

        _uiState.value = _uiState.value.copy(lastSavedCharOffset = charOffset)

        viewModelScope.launch {
            repository().updateBookProgress(
                bookId = bookId,
                charOffset = charOffset,
                pageIndex = state.selectedPageIndex,
                playedAt = now,
                openedAt = now
            )
        }
    }

    fun selectPage(index: Int) {
        val state = _uiState.value
        if (state.pageTexts.isEmpty()) return
        val safeIndex = index.coerceIn(0, state.pageTexts.lastIndex)
        if (activePlayer.isPlaying()) {
            pagePlaybackEndOffset = null
            activePlayer.pause()
            progressJob?.cancel()
        }
        _uiState.value = state.copy(
            selectedPageIndex = safeIndex,
            status = "Selected page ${safeIndex + 1}/${state.pageTexts.size}. Press Play Page to start."
        )
    }

    fun nextPage() {
        val state = _uiState.value
        if (state.pageTexts.isEmpty()) return
        val nextIndex = (state.selectedPageIndex + 1).coerceAtMost(state.pageTexts.lastIndex)
        selectPage(nextIndex)
        if (state.autoPlayOnPageChange) {
            playSelectedPage()
        }
    }

    fun previousPage() {
        val state = _uiState.value
        if (state.pageTexts.isEmpty()) return
        val previousIndex = (state.selectedPageIndex - 1).coerceAtLeast(0)
        selectPage(previousIndex)
        if (state.autoPlayOnPageChange) {
            playSelectedPage()
        }
    }

    fun playSelectedPage() {
        val state = _uiState.value
        if (state.pageTexts.isEmpty()) return
        if (state.chunks.isEmpty()) {
            _uiState.value = state.copy(status = "Audio is still building. Please wait for initial chunks.")
            return
        }

        val pageIndex = state.selectedPageIndex.coerceIn(0, state.pageTexts.lastIndex)
        val pageStart = state.pageStartOffsets.getOrNull(pageIndex)
            ?: ((pageIndex.toLong() * state.cleanedText.length.toLong()) / state.pageTexts.size.coerceAtLeast(1).toLong()).toInt()
        val nextPageStart = state.pageStartOffsets.getOrNull(pageIndex + 1)
            ?: Int.MAX_VALUE
        val maxBuiltEnd = state.chunks.maxOfOrNull { it.endOffset } ?: 0

        if (pageStart >= maxBuiltEnd) {
            _uiState.value = state.copy(
                status = "Page ${pageIndex + 1} is not synthesized yet. Keep building, then try again."
            )
            return
        }

        val targetChunkIndex = chunkIndexForPage(state, pageIndex)

        if (targetChunkIndex < 0) return

        pagePlaybackEndOffset = nextPageStart
        activePlayer.seekToChunk(targetChunkIndex)
        when (activePlayer.play()) {
            PlaybackStartResult.GRANTED -> {
                startProgressLoop()
                _uiState.value = state.copy(
                    isFocusPaused = false,
                    currentChunkIndex = targetChunkIndex,
                    status = "Playing page ${pageIndex + 1}/${state.pageTexts.size}"
                )
            }
            PlaybackStartResult.DELAYED -> {
                _uiState.value = state.copy(
                    isFocusPaused = true,
                    currentChunkIndex = targetChunkIndex,
                    status = "Waiting for audio focus to play page ${pageIndex + 1}."
                )
            }
            PlaybackStartResult.FAILED -> {
                _uiState.value = state.copy(
                    isFocusPaused = true,
                    status = "Could not get audio focus. Pause other audio apps and try Play Page again."
                )
            }
        }
    }

    fun markLastReadAtPageOffset(pageLocalOffset: Int) {
        val state = _uiState.value
        val bookId = state.bookId ?: return
        if (state.pageTexts.isEmpty()) return

        val pageIndex = state.selectedPageIndex.coerceIn(0, state.pageTexts.lastIndex)
        val pageText = state.pageTexts[pageIndex]
        if (pageText.isBlank()) return

        val safeLocal = pageLocalOffset.coerceIn(0, pageText.lastIndex.coerceAtLeast(0))
        val localWord = pageText.wordRangeNearLocalOffset(safeLocal)
        val pageStart = state.pageStartOffsets.getOrNull(pageIndex)
            ?: ((pageIndex.toLong() * state.cleanedText.length.toLong()) / state.pageTexts.size.coerceAtLeast(1).toLong()).toInt()

        val targetOffset = (pageStart + localWord.first)
            .coerceIn(0, state.cleanedText.length.coerceAtLeast(0))
        val chunkIndex = state.chunks.indexOfLast { it.startOffset <= targetOffset }
            .let { if (it >= 0) it else 0 }
        val targetChunk = state.chunks.getOrNull(chunkIndex)
        val targetWord = targetChunk?.displayText?.wordRangeNearOffset(targetChunk.startOffset, targetOffset)

        _uiState.value = state.copy(
            currentChunkIndex = chunkIndex,
            activeWordRange = targetWord,
            lastSavedCharOffset = targetOffset,
            status = "Marked page ${pageIndex + 1} word as last read."
        )

        activePlayer.seekToChunk(chunkIndex)

        viewModelScope.launch {
            repository().updateBookProgress(
                bookId = bookId,
                charOffset = targetOffset,
                pageIndex = pageIndex,
                playedAt = System.currentTimeMillis(),
                openedAt = System.currentTimeMillis()
            )
        }
    }

    fun jumpToChapter(chapterTitle: String) {
        val state = _uiState.value
        val chapterStart = state.cleanedText.indexOf(chapterTitle, ignoreCase = true)
        if (chapterStart < 0) {
            _uiState.value = state.copy(status = "Couldn't find that chapter in text.")
            return
        }

        val targetChunk = state.chunks
            .sortedBy { it.chunkIndex }
            .firstOrNull { it.startOffset >= chapterStart }
            ?: state.chunks.lastOrNull()

        if (targetChunk == null) {
            _uiState.value = state.copy(
                selectedChapter = chapterTitle,
                status = "Chapter selected. Waiting for chunks to build..."
            )
            return
        }

        val mediaIndex = state.chunks.indexOfFirst { it.chunkIndex == targetChunk.chunkIndex }
        if (mediaIndex < 0) {
            _uiState.value = state.copy(
                selectedChapter = chapterTitle,
                status = "Chapter selected. Waiting for chunks to build..."
            )
            return
        }

        activePlayer.seekToChunk(mediaIndex)
        val pageIndex = findPageIndexForChunk(state, targetChunk)
        _uiState.value = state.copy(
            selectedChapter = chapterTitle,
            currentChunkIndex = mediaIndex,
            activeWordRange = targetChunk.displayText.firstWordRange(targetChunk.startOffset),
            selectedPageIndex = pageIndex,
            status = "Jumped to: $chapterTitle"
        )
    }

    fun addBookmarkAtCurrentChunk() {
        val state = _uiState.value
        val bookId = state.bookId ?: return
        val chunk = state.chunks.getOrNull(state.currentChunkIndex) ?: return

        viewModelScope.launch {
            repository().addBookmark(bookId, chunk.startOffset)
        }
    }

    fun addNoteAtCurrentChunk(noteText: String) {
        if (noteText.isBlank()) return

        val state = _uiState.value
        val bookId = state.bookId ?: return
        val chunk = state.chunks.getOrNull(state.currentChunkIndex) ?: return

        viewModelScope.launch {
            repository().addNote(bookId, chunk.startOffset, chunk.endOffset, noteText)
        }
    }

    private fun observeAnnotations(bookId: String) {
        viewModelScope.launch {
            repository().observeBookmarks(bookId).collectLatest { bookmarks ->
                _uiState.value = _uiState.value.copy(bookmarks = bookmarks)
            }
        }

        viewModelScope.launch {
            repository().observeNotes(bookId).collectLatest { notes ->
                _uiState.value = _uiState.value.copy(notes = notes)
            }
        }
    }

    private fun startProgressLoop() {
        progressJob?.cancel()
        progressJob = viewModelScope.launch {
            while (activePlayer.isPlaying()) {
                updateActiveWord()
                delay(80L)
            }
        }
    }

    private fun updateActiveWord() {
        val state = _uiState.value
        val chunk = state.chunks.getOrNull(activePlayer.currentChunkIndex()) ?: return
        val wordRanges = buildWordRanges(chunk.displayText, chunk.startOffset)
        if (wordRanges.isEmpty()) return

        val duration = activePlayer.durationMs().takeIf { it > 0 } ?: chunk.estimatedDurationMs
        val progress = if (duration > 0) {
            val alignedPosition = (activePlayer.currentPositionMs() + followAlongLeadMs)
                .coerceIn(0L, duration - 1L)
            alignedPosition.toFloat() / duration.toFloat()
        } else {
            0f
        }.coerceIn(0f, 0.999f)

        val wordIndex = (progress * wordRanges.size).toInt().coerceIn(0, wordRanges.lastIndex)
        val mediaIndex = activePlayer.currentChunkIndex()
        val pageIndex = findPageIndexForChunk(state, chunk)

        pagePlaybackEndOffset?.let { endOffset ->
            if (chunk.startOffset >= endOffset) {
                pagePlaybackEndOffset = null
                activePlayer.pause()
                progressJob?.cancel()
                _uiState.value = state.copy(
                    status = "Reached end of page ${state.selectedPageIndex + 1}"
                )
                return
            }
        }

        _uiState.value = state.copy(
            currentChunkIndex = mediaIndex,
            activeWordRange = wordRanges[wordIndex],
            selectedPageIndex = if (pagePlaybackEndOffset != null) state.selectedPageIndex else pageIndex
        )

        persistReadingProgress(_uiState.value, chunk)
    }

    private fun loadSelectedPlayer(state: ReaderUiState) {
        if (state.chunks.isEmpty()) return

        val player = activePlayer
        val resumeChunkIndex = state.chunks.indexOfLast { it.startOffset <= state.lastSavedCharOffset }
            .let { if (it >= 0) it else state.currentChunkIndex.coerceIn(0, state.chunks.lastIndex) }

        player.load(state.chunks) { current ->
            val mediaIndex = player.currentChunkIndex()
            val pageIndex = findPageIndexForChunk(_uiState.value, current)
            _uiState.value = _uiState.value.copy(
                currentChunkIndex = mediaIndex,
                activeWordRange = current.displayText.firstWordRange(current.startOffset),
                selectedPageIndex = pageIndex
            )
        }
        player.seekToChunk(resumeChunkIndex)
    }

    private fun buildWordRanges(text: String, globalStart: Int): List<WordRange> {
        return Regex("\\S+").findAll(text).map { match ->
            WordRange(globalStart + match.range.first, globalStart + match.range.last + 1)
        }.toList()
    }

    private fun String.firstWordRange(globalStart: Int): WordRange? {
        val match = Regex("\\S+").find(this) ?: return null
        return WordRange(globalStart + match.range.first, globalStart + match.range.last + 1)
    }

    private fun String.wordRangeNearOffset(globalStart: Int, targetOffset: Int): WordRange? {
        val targetLocal = (targetOffset - globalStart).coerceAtLeast(0)
        val words = Regex("\\S+").findAll(this).toList()
        if (words.isEmpty()) return null

        val containing = words.firstOrNull { targetLocal in it.range.first..it.range.last }
        val chosen = containing ?: words.lastOrNull { it.range.first <= targetLocal } ?: words.first()
        return WordRange(globalStart + chosen.range.first, globalStart + chosen.range.last + 1)
    }

    private fun String.wordRangeNearLocalOffset(targetLocalOffset: Int): IntRange {
        val words = Regex("\\S+").findAll(this).toList()
        if (words.isEmpty()) return targetLocalOffset..targetLocalOffset
        val containing = words.firstOrNull { targetLocalOffset in it.range.first..it.range.last }
        val chosen = containing ?: words.lastOrNull { it.range.first <= targetLocalOffset } ?: words.first()
        return chosen.range
    }

    override fun onCleared() {
        progressJob?.cancel()
        synthesisJob?.cancel()
        systemTtsClient.release()
        piperTtsClient.release()
        audioPlaybackEngine.release()
        systemTtsPlayer.release()
        super.onCleared()
    }
}
