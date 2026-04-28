package com.example.ttsreader.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

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
}
