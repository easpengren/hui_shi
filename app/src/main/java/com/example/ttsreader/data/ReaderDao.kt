package com.example.ttsreader.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

data class LibraryBookRow(
    val id: String,
    val title: String,
    val sourceType: com.example.ttsreader.core.SourceType,
    val sourceUri: String?,
    val sourceDisplayName: String?,
    val createdAt: Long,
    val lastCharOffset: Int,
    val lastPageIndex: Int,
    val lastPlayedAt: Long,
    val chunkCount: Int
)

@Dao
interface ReaderDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertBook(book: BookEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertChunks(chunks: List<ChunkEntity>)

    @Query("DELETE FROM chunks WHERE bookId = :bookId")
    suspend fun clearChunks(bookId: String)

    @Query("SELECT * FROM chunks WHERE bookId = :bookId ORDER BY chunkIndex")
    suspend fun getChunksForBook(bookId: String): List<ChunkEntity>

    @Insert
    suspend fun insertBookmark(bookmark: BookmarkEntity)

    @Insert
    suspend fun insertNote(note: NoteEntity)

    @Query("SELECT * FROM bookmarks WHERE bookId = :bookId ORDER BY createdAt DESC")
    fun observeBookmarks(bookId: String): Flow<List<BookmarkEntity>>

    @Query("SELECT * FROM notes WHERE bookId = :bookId ORDER BY createdAt DESC")
    fun observeNotes(bookId: String): Flow<List<NoteEntity>>

    @Query(
        """
        SELECT b.id, b.title, b.sourceType, b.sourceUri, b.sourceDisplayName, b.createdAt,
               b.lastCharOffset, b.lastPageIndex, b.lastPlayedAt,
               COUNT(c.id) AS chunkCount
        FROM books b
        LEFT JOIN chunks c ON c.bookId = b.id
        GROUP BY b.id
        ORDER BY b.lastPlayedAt DESC, b.createdAt DESC
        """
    )
    fun observeLibraryBooks(): Flow<List<LibraryBookRow>>

    @Query("SELECT * FROM books WHERE id = :bookId LIMIT 1")
    suspend fun getBook(bookId: String): BookEntity?

    @Query(
        """
        UPDATE books
        SET lastCharOffset = :charOffset,
            lastPageIndex = :pageIndex,
            lastPlayedAt = :playedAt,
            lastOpenedAt = :openedAt
        WHERE id = :bookId
        """
    )
    suspend fun updateBookProgress(
        bookId: String,
        charOffset: Int,
        pageIndex: Int,
        playedAt: Long,
        openedAt: Long
    )
}
