package com.example.ttsreader.repo

import com.example.ttsreader.core.BookPreparer
import com.example.ttsreader.core.PreparedBook
import com.example.ttsreader.data.BookEntity
import com.example.ttsreader.data.BookmarkEntity
import com.example.ttsreader.data.ChunkEntity
import com.example.ttsreader.data.LibraryBookRow
import com.example.ttsreader.data.NoteEntity
import com.example.ttsreader.data.ReaderDao
import com.example.ttsreader.tts.TtsClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext

class ReaderRepository(
    private val dao: ReaderDao,
    private val preparer: BookPreparer,
    private val ttsClient: TtsClient
) {
    suspend fun importAndPrepare(title: String, text: String): PreparedBook = withContext(Dispatchers.Default) {
        val prepared = preparer.prepareFromPlainText(title = title, text = text)
        persistPreparedBook(prepared)
        prepared
    }

    suspend fun savePreparedDocument(
        book: PreparedBook,
        sourceUri: String? = null,
        sourceDisplayName: String? = null
    ): PreparedBook = withContext(Dispatchers.Default) {
        persistPreparedBook(book, sourceUri, sourceDisplayName)
        book
    }

    private suspend fun persistPreparedBook(
        prepared: PreparedBook,
        sourceUri: String? = null,
        sourceDisplayName: String? = null
    ) {
        dao.upsertBook(
            BookEntity(
                id = prepared.id,
                title = prepared.title,
                sourceType = prepared.sourceType,
                cleanedText = prepared.cleanedText,
                createdAt = System.currentTimeMillis(),
                sourceUri = sourceUri,
                sourceDisplayName = sourceDisplayName,
                lastCharOffset = 0,
                lastPageIndex = 0,
                lastPlayedAt = 0L,
                lastOpenedAt = System.currentTimeMillis()
            )
        )
    }

    suspend fun clearChunks(bookId: String) {
        dao.clearChunks(bookId)
    }

    suspend fun getChunksForBook(bookId: String): List<ChunkEntity> = dao.getChunksForBook(bookId)

    /** Build [ChunkEntity] list for System TTS — no synthesis, audioPath is empty. */
    suspend fun buildSystemChunks(book: PreparedBook): List<ChunkEntity> {
        dao.clearChunks(book.id)
        val entities = book.chunks.map { chunk ->
            ChunkEntity(
                bookId = book.id,
                chunkIndex = chunk.index,
                displayText = chunk.displayText,
                ttsText = chunk.ttsText,
                chapterTitle = chunk.chapterTitle,
                startOffset = chunk.startOffset,
                endOffset = chunk.endOffset,
                estimatedDurationMs = chunk.estimatedDurationMs,
                audioPath = ""
            )
        }
        dao.insertChunks(entities)
        return entities
    }

    suspend fun synthesizeAllChunks(
        book: PreparedBook,
        concurrency: Int = 3,
        onChunkStarted: suspend (current: Int, total: Int) -> Unit = { _, _ -> },
        onChunkReady: suspend (ChunkEntity) -> Unit
    ) = coroutineScope {
        dao.clearChunks(book.id)
        val total = book.chunks.size
        val semaphore = Semaphore(concurrency)

        // Launch all synthesis tasks in parallel, bounded by semaphore
        val deferred = book.chunks.mapIndexed { idx, chunk ->
            async {
                semaphore.withPermit {
                    onChunkStarted(idx + 1, total)
                    val audioFile = ttsClient.synthesizeChunk(book.id, chunk)
                    ChunkEntity(
                        bookId = book.id,
                        chunkIndex = chunk.index,
                        displayText = chunk.displayText,
                        ttsText = chunk.ttsText,
                        chapterTitle = chunk.chapterTitle,
                        startOffset = chunk.startOffset,
                        endOffset = chunk.endOffset,
                        estimatedDurationMs = chunk.estimatedDurationMs,
                        audioPath = audioFile.absolutePath
                    )
                }
            }
        }

        // Deliver chunks in index order so playback appending stays sequential
        deferred.forEach { d ->
            val entity = d.await()
            dao.insertChunks(listOf(entity))
            onChunkReady(entity)
        }
    }

    suspend fun addBookmark(bookId: String, offset: Int) {
        dao.insertBookmark(
            BookmarkEntity(
                bookId = bookId,
                charOffset = offset,
                createdAt = System.currentTimeMillis()
            )
        )
    }

    suspend fun addNote(bookId: String, startOffset: Int, endOffset: Int, note: String) {
        dao.insertNote(
            NoteEntity(
                bookId = bookId,
                startOffset = startOffset,
                endOffset = endOffset,
                text = note,
                createdAt = System.currentTimeMillis()
            )
        )
    }

    fun observeBookmarks(bookId: String): Flow<List<BookmarkEntity>> = dao.observeBookmarks(bookId)

    fun observeNotes(bookId: String): Flow<List<NoteEntity>> = dao.observeNotes(bookId)

    fun observeLibraryBooks(): Flow<List<LibraryBookRow>> = dao.observeLibraryBooks()

    suspend fun getBook(bookId: String): BookEntity? = dao.getBook(bookId)

    suspend fun updateBookProgress(
        bookId: String,
        charOffset: Int,
        pageIndex: Int,
        playedAt: Long,
        openedAt: Long
    ) {
        dao.updateBookProgress(bookId, charOffset, pageIndex, playedAt, openedAt)
    }
}
