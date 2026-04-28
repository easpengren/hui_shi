package com.example.ttsreader.repo

import com.example.ttsreader.core.BookPreparer
import com.example.ttsreader.core.PreparedBook
import com.example.ttsreader.data.BookEntity
import com.example.ttsreader.data.BookmarkEntity
import com.example.ttsreader.data.ChunkEntity
import com.example.ttsreader.data.NoteEntity
import com.example.ttsreader.data.ReaderDao
import com.example.ttsreader.tts.TtsClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
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

    suspend fun savePreparedDocument(book: PreparedBook): PreparedBook = withContext(Dispatchers.Default) {
        persistPreparedBook(book)
        book
    }

    private suspend fun persistPreparedBook(prepared: PreparedBook) {
        dao.upsertBook(
            BookEntity(
                id = prepared.id,
                title = prepared.title,
                sourceType = prepared.sourceType,
                cleanedText = prepared.cleanedText,
                createdAt = System.currentTimeMillis()
            )
        )
    }

    suspend fun clearChunks(bookId: String) {
        dao.clearChunks(bookId)
    }

    suspend fun synthesizeAllChunks(
        book: PreparedBook,
        onChunkStarted: suspend (current: Int, total: Int) -> Unit = { _, _ -> },
        onChunkReady: suspend (ChunkEntity) -> Unit
    ) {
        dao.clearChunks(book.id)
        val total = book.chunks.size
        book.chunks.forEachIndexed { idx, chunk ->
            onChunkStarted(idx + 1, total)
            val audioFile = ttsClient.synthesizeChunk(book.id, chunk)
            val entity = ChunkEntity(
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
}
