package com.example.ttsreader.data

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import com.example.ttsreader.core.SourceType

@Entity(tableName = "books")
data class BookEntity(
    @PrimaryKey val id: String,
    val title: String,
    val sourceType: SourceType,
    val cleanedText: String,
    val createdAt: Long,
    val sourceUri: String? = null,
    val sourceDisplayName: String? = null,
    val lastCharOffset: Int = 0,
    val lastPageIndex: Int = 0,
    val lastPlayedAt: Long = 0L,
    val lastOpenedAt: Long = 0L
)

@Entity(
    tableName = "chunks",
    foreignKeys = [
        ForeignKey(
            entity = BookEntity::class,
            parentColumns = ["id"],
            childColumns = ["bookId"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index("bookId")]
)
data class ChunkEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val bookId: String,
    val chunkIndex: Int,
    val displayText: String,
    val ttsText: String,
    val chapterTitle: String?,
    val startOffset: Int,
    val endOffset: Int,
    val estimatedDurationMs: Long,
    val audioPath: String
)

@Entity(
    tableName = "bookmarks",
    foreignKeys = [
        ForeignKey(
            entity = BookEntity::class,
            parentColumns = ["id"],
            childColumns = ["bookId"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index("bookId")]
)
data class BookmarkEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val bookId: String,
    val charOffset: Int,
    val createdAt: Long
)

@Entity(
    tableName = "notes",
    foreignKeys = [
        ForeignKey(
            entity = BookEntity::class,
            parentColumns = ["id"],
            childColumns = ["bookId"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index("bookId")]
)
data class NoteEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val bookId: String,
    val startOffset: Int,
    val endOffset: Int,
    val text: String,
    val createdAt: Long
)
