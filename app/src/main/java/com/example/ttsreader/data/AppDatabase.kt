package com.example.ttsreader.data

import android.content.Context
import androidx.room.TypeConverters
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(
    entities = [BookEntity::class, ChunkEntity::class, BookmarkEntity::class, NoteEntity::class],
    version = 2,
    exportSchema = false
)
@TypeConverters(RoomConverters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun readerDao(): ReaderDao

    companion object {
        @Volatile
        private var instance: AppDatabase? = null

        fun get(context: Context): AppDatabase {
            return instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "tts_reader.db"
                ).fallbackToDestructiveMigration().build().also { instance = it }
            }
        }
    }
}
