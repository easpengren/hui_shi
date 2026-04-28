package com.example.ttsreader.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.ttsreader.BuildConfig
import com.example.ttsreader.core.BookPreparer
import com.example.ttsreader.core.PreparedBook
import com.example.ttsreader.core.WordRange
import com.example.ttsreader.data.AppDatabase
import com.example.ttsreader.data.BookmarkEntity
import com.example.ttsreader.data.ChunkEntity
import com.example.ttsreader.data.NoteEntity
import com.example.ttsreader.ingest.ImportedDocument
import com.example.ttsreader.playback.AudioPlaybackEngine
import com.example.ttsreader.repo.ReaderRepository
import com.example.ttsreader.tts.AndroidTtsClient
import com.example.ttsreader.tts.CacheManager
import com.example.ttsreader.tts.FallbackTtsClient
import com.example.ttsreader.tts.TtsAiClient
import com.example.ttsreader.tts.TtsClient
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

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
    val isBuildingAudio: Boolean = false,
    val buildProgressCurrent: Int = 0,
    val buildProgressTotal: Int = 0,
    val cloudFallbackMessage: String? = null,
    val status: String = "Paste, share, or upload text to begin.",
    val bookmarks: List<BookmarkEntity> = emptyList(),
    val notes: List<NoteEntity> = emptyList()
)

class ReaderViewModel(application: Application) : AndroidViewModel(application) {
    private val db = AppDatabase.get(application)
    private val hasApiKey = BuildConfig.TTS_API_KEY.isNotBlank()
    private val isLocalTtsMode = !hasApiKey
    private val bookPreparer = BookPreparer(maxChunkLength = if (isLocalTtsMode) 900 else 2500)
    private val localTtsClient = AndroidTtsClient(application, CacheManager(application))
    @Volatile
    private var lastCloudFailure: String? = null
    @Volatile
    private var fallbackUsedThisBuild: Boolean = false
    private val ttsClient: TtsClient = if (hasApiKey) {
        FallbackTtsClient(
            primary = TtsAiClient(CacheManager(application)),
            fallback = localTtsClient,
            onPrimaryFailure = { throwable ->
                fallbackUsedThisBuild = true
                lastCloudFailure = throwable.message?.take(180) ?: throwable::class.java.simpleName
            }
        )
    } else {
        localTtsClient
    }

    private val repository = ReaderRepository(
        dao = db.readerDao(),
        preparer = bookPreparer,
        ttsClient = ttsClient
    )

    val playbackEngine = AudioPlaybackEngine(application)
    private val minPlayableChunks = 2
    private val followAlongLeadMs = 220L
    private var progressJob: Job? = null
    private var synthesisJob: Job? = null
    private var annotationsObservedForBookId: String? = null
    private var pendingPreparedBook: PreparedBook? = null

    private val _uiState = MutableStateFlow(ReaderUiState())
    val uiState: StateFlow<ReaderUiState> = _uiState.asStateFlow()

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
            _uiState.value = _uiState.value.copy(
                isLoading = true,
                isBuildingAudio = false,
                buildProgressCurrent = 0,
                buildProgressTotal = 0,
                status = "Importing ${document.sourceType.name.lowercase()}..."
            )

            runCatching {
                val prepared = bookPreparer.prepare(document.title, document.sourceType, document.pages)
                repository.savePreparedDocument(prepared)
                pendingPreparedBook = prepared
                _uiState.value = _uiState.value.copy(
                    title = prepared.title,
                    sourceText = document.previewText,
                    cleanedText = prepared.cleanedText,
                    bookId = prepared.id,
                    chapters = prepared.chapters,
                    status = "Imported. Build audio to continue.",
                    isBuildingAudio = false,
                    isLoading = false
                )
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
            synthesisJob?.cancel()
            _uiState.value = _uiState.value.copy(
                isLoading = true,
                isBuildingAudio = true,
                buildProgressCurrent = 0,
                buildProgressTotal = 0,
                cloudFallbackMessage = null,
                status = "Preparing text..."
            )

            runCatching {
                val prepared = pendingPreparedBook?.takeIf {
                    it.title == state.title || state.title.isBlank()
                } ?: repository.importAndPrepare(
                    title = state.title.ifBlank { "Untitled" },
                    text = state.sourceText
                )

                pendingPreparedBook = prepared
                lastCloudFailure = null
                fallbackUsedThisBuild = false

                _uiState.value = _uiState.value.copy(
                    bookId = prepared.id,
                    chunks = emptyList(),
                    cleanedText = prepared.cleanedText,
                    chapters = prepared.chapters,
                    buildProgressCurrent = 0,
                    buildProgressTotal = prepared.chunks.size,
                    cloudFallbackMessage = null,
                    status = if (isLocalTtsMode) {
                        "Generating audio chunks with device voice..."
                    } else {
                        "Generating audio chunks..."
                    }
                )

                val totalChunks = prepared.chunks.size.coerceAtLeast(1)
                var readyChunks = 0
                var playbackLoaded = false
                val readyThreshold = minOf(minPlayableChunks, totalChunks)
                val progressiveChunks = mutableListOf<ChunkEntity>()

                synthesisJob = viewModelScope.launch {
                    runCatching {
                        repository.synthesizeAllChunks(
                            book = prepared,
                            onChunkStarted = { current, total ->
                                val mode = if (isLocalTtsMode) "device voice" else "cloud voice"
                                _uiState.value = _uiState.value.copy(
                                    buildProgressCurrent = (current - 1).coerceAtLeast(0),
                                    buildProgressTotal = total,
                                    status = "Building $mode: ${current - 1}/$total (working on $current/$total)"
                                )
                            }
                        ) { entity ->
                            readyChunks += 1
                            progressiveChunks += entity
                            val mode = if (isLocalTtsMode) "device voice" else "cloud voice"
                            val effectiveMode = when {
                                isLocalTtsMode -> "device voice"
                                fallbackUsedThisBuild -> "cloud + local fallback"
                                else -> mode
                            }

                            if (!playbackLoaded && readyChunks >= readyThreshold) {
                                playbackEngine.load(progressiveChunks.toList()) { current ->
                                    _uiState.value = _uiState.value.copy(
                                        currentChunkIndex = current.chunkIndex,
                                        activeWordRange = current.displayText.firstWordRange(current.startOffset)
                                    )
                                }
                                playbackLoaded = true
                                if (annotationsObservedForBookId != prepared.id) {
                                    observeAnnotations(prepared.id)
                                    annotationsObservedForBookId = prepared.id
                                }
                            } else if (playbackLoaded) {
                                playbackEngine.appendChunk(entity)
                            }

                            _uiState.value = _uiState.value.copy(
                                chunks = progressiveChunks.toList(),
                                buildProgressCurrent = readyChunks,
                                buildProgressTotal = totalChunks,
                                cloudFallbackMessage = if (fallbackUsedThisBuild) {
                                    lastCloudFailure?.let { "Cloud unavailable: $it. Using local voice fallback." }
                                } else {
                                    null
                                },
                                status = if (readyChunks >= readyThreshold && readyChunks < totalChunks) {
                                    "Ready to play. Building $effectiveMode in background: $readyChunks/$totalChunks"
                                } else {
                                    "Building $effectiveMode: $readyChunks/$totalChunks chunks"
                                },
                                isLoading = readyChunks < readyThreshold,
                                isBuildingAudio = readyChunks < totalChunks
                            )
                        }

                        _uiState.value = _uiState.value.copy(
                            buildProgressCurrent = 0,
                            buildProgressTotal = 0,
                            cloudFallbackMessage = if (fallbackUsedThisBuild) {
                                lastCloudFailure?.let { "Cloud unavailable: $it. Using local voice fallback." }
                            } else {
                                null
                            },
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
                            cloudFallbackMessage = if (fallbackUsedThisBuild) {
                                lastCloudFailure?.let { "Cloud unavailable: $it. Using local voice fallback." }
                            } else {
                                null
                            },
                            status = "Failed: ${err.message}"
                        )
                    }
                }
            }.onFailure { err ->
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    isBuildingAudio = false,
                    buildProgressCurrent = 0,
                    buildProgressTotal = 0,
                    cloudFallbackMessage = if (fallbackUsedThisBuild) {
                        lastCloudFailure?.let { "Cloud unavailable: $it. Using local voice fallback." }
                    } else {
                        null
                    },
                    status = "Failed: ${err.message}"
                )
            }
        }
    }

    fun play() {
        if (_uiState.value.chunks.isEmpty()) {
            _uiState.value = _uiState.value.copy(status = "Audio is still building. Please wait for initial chunks.")
            return
        }
        playbackEngine.play()
        startProgressLoop()
    }

    fun pause() {
        playbackEngine.pause()
        progressJob?.cancel()
    }

    fun setSpeed(speed: Float) {
        playbackEngine.setSpeed(speed)
        _uiState.value = _uiState.value.copy(playbackSpeed = speed)
    }

    fun addBookmarkAtCurrentChunk() {
        val state = _uiState.value
        val bookId = state.bookId ?: return
        val chunk = state.chunks.getOrNull(state.currentChunkIndex) ?: return

        viewModelScope.launch {
            repository.addBookmark(bookId, chunk.startOffset)
        }
    }

    fun addNoteAtCurrentChunk(noteText: String) {
        if (noteText.isBlank()) return

        val state = _uiState.value
        val bookId = state.bookId ?: return
        val chunk = state.chunks.getOrNull(state.currentChunkIndex) ?: return

        viewModelScope.launch {
            repository.addNote(bookId, chunk.startOffset, chunk.endOffset, noteText)
        }
    }

    private fun observeAnnotations(bookId: String) {
        viewModelScope.launch {
            repository.observeBookmarks(bookId).collectLatest { bookmarks ->
                _uiState.value = _uiState.value.copy(bookmarks = bookmarks)
            }
        }

        viewModelScope.launch {
            repository.observeNotes(bookId).collectLatest { notes ->
                _uiState.value = _uiState.value.copy(notes = notes)
            }
        }
    }

    private fun startProgressLoop() {
        progressJob?.cancel()
        progressJob = viewModelScope.launch {
            while (playbackEngine.isPlaying()) {
                updateActiveWord()
                delay(80L)
            }
        }
    }

    private fun updateActiveWord() {
        val state = _uiState.value
        val chunk = state.chunks.getOrNull(playbackEngine.currentChunkIndex()) ?: return
        val wordRanges = buildWordRanges(chunk.displayText, chunk.startOffset)
        if (wordRanges.isEmpty()) return

        val duration = playbackEngine.durationMs().takeIf { it > 0 } ?: chunk.estimatedDurationMs
        val progress = if (duration > 0) {
            val alignedPosition = (playbackEngine.currentPositionMs() + followAlongLeadMs)
                .coerceIn(0L, duration - 1L)
            alignedPosition.toFloat() / duration.toFloat()
        } else {
            0f
        }.coerceIn(0f, 0.999f)

        val wordIndex = (progress * wordRanges.size).toInt().coerceIn(0, wordRanges.lastIndex)
        _uiState.value = state.copy(
            currentChunkIndex = chunk.chunkIndex,
            activeWordRange = wordRanges[wordIndex]
        )
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

    override fun onCleared() {
        progressJob?.cancel()
        synthesisJob?.cancel()
        ttsClient.release()
        playbackEngine.release()
        super.onCleared()
    }
}
