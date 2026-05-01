package com.example.ttsreader.data

import android.content.Context
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AppDatabaseMigrationTest {

    private val context: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun migrate2To3_addsLibraryAndProgressColumnsWithDefaults() {
        val dbName = "migration-test-v2-v3.db"
        context.deleteDatabase(dbName)

        createVersion2Database(dbName)
        runMigrationToV3(dbName)

        verifyBooksColumnsAndDefaults(dbName)
        context.deleteDatabase(dbName)
    }

    private fun createVersion2Database(dbName: String) {
        val callback = object : android.database.sqlite.SQLiteOpenHelper(context, dbName, null, 2) {
            override fun onCreate(db: android.database.sqlite.SQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS books (
                        id TEXT NOT NULL PRIMARY KEY,
                        title TEXT NOT NULL,
                        sourceType TEXT NOT NULL,
                        cleanedText TEXT NOT NULL,
                        createdAt INTEGER NOT NULL
                    )
                    """.trimIndent()
                )
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS chunks (
                        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        bookId TEXT NOT NULL,
                        chunkIndex INTEGER NOT NULL,
                        displayText TEXT NOT NULL,
                        ttsText TEXT NOT NULL,
                        chapterTitle TEXT,
                        startOffset INTEGER NOT NULL,
                        endOffset INTEGER NOT NULL,
                        estimatedDurationMs INTEGER NOT NULL,
                        audioPath TEXT NOT NULL,
                        FOREIGN KEY(bookId) REFERENCES books(id) ON DELETE CASCADE
                    )
                    """.trimIndent()
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS index_chunks_bookId ON chunks(bookId)")
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS bookmarks (
                        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        bookId TEXT NOT NULL,
                        charOffset INTEGER NOT NULL,
                        createdAt INTEGER NOT NULL,
                        FOREIGN KEY(bookId) REFERENCES books(id) ON DELETE CASCADE
                    )
                    """.trimIndent()
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS index_bookmarks_bookId ON bookmarks(bookId)")
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS notes (
                        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        bookId TEXT NOT NULL,
                        startOffset INTEGER NOT NULL,
                        endOffset INTEGER NOT NULL,
                        text TEXT NOT NULL,
                        createdAt INTEGER NOT NULL,
                        FOREIGN KEY(bookId) REFERENCES books(id) ON DELETE CASCADE
                    )
                    """.trimIndent()
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS index_notes_bookId ON notes(bookId)")
                db.execSQL(
                    "INSERT INTO books(id, title, sourceType, cleanedText, createdAt) VALUES('book1', 'Title', 'PLAIN_TEXT', 'abc', 12345)"
                )
            }

            override fun onUpgrade(
                db: android.database.sqlite.SQLiteDatabase,
                oldVersion: Int,
                newVersion: Int
            ) = Unit
        }

        val db = callback.writableDatabase
        db.close()
        callback.close()
    }

    private fun runMigrationToV3(dbName: String) {
        val config = androidx.sqlite.db.SupportSQLiteOpenHelper.Configuration.builder(context)
            .name(dbName)
            .callback(object : androidx.sqlite.db.SupportSQLiteOpenHelper.Callback(3) {
                override fun onCreate(db: androidx.sqlite.db.SupportSQLiteDatabase) = Unit

                override fun onUpgrade(
                    db: androidx.sqlite.db.SupportSQLiteDatabase,
                    oldVersion: Int,
                    newVersion: Int
                ) {
                    AppDatabase.MIGRATION_2_3.migrate(db)
                }
            })
            .build()

        val helper = FrameworkSQLiteOpenHelperFactory().create(config)
        helper.writableDatabase.close()
        helper.close()
    }

    private fun verifyBooksColumnsAndDefaults(dbName: String) {
        val config = androidx.sqlite.db.SupportSQLiteOpenHelper.Configuration.builder(context)
            .name(dbName)
            .callback(object : androidx.sqlite.db.SupportSQLiteOpenHelper.Callback(3) {
                override fun onCreate(db: androidx.sqlite.db.SupportSQLiteDatabase) = Unit
                override fun onUpgrade(
                    db: androidx.sqlite.db.SupportSQLiteDatabase,
                    oldVersion: Int,
                    newVersion: Int
                ) = Unit
            })
            .build()

        val helper = FrameworkSQLiteOpenHelperFactory().create(config)
        val db = helper.readableDatabase

        val columns = mutableSetOf<String>()
        db.query("PRAGMA table_info(books)").use { cursor ->
            while (cursor.moveToNext()) {
                columns += cursor.getString(cursor.getColumnIndexOrThrow("name"))
            }
        }

        assertEquals(true, columns.contains("sourceUri"))
        assertEquals(true, columns.contains("sourceDisplayName"))
        assertEquals(true, columns.contains("lastCharOffset"))
        assertEquals(true, columns.contains("lastPageIndex"))
        assertEquals(true, columns.contains("lastPlayedAt"))
        assertEquals(true, columns.contains("lastOpenedAt"))

        db.query(
            "SELECT sourceUri, sourceDisplayName, lastCharOffset, lastPageIndex, lastPlayedAt, lastOpenedAt FROM books WHERE id = 'book1'"
        ).use { cursor ->
            assertEquals(true, cursor.moveToFirst())
            assertNull(cursor.getString(0))
            assertNull(cursor.getString(1))
            assertEquals(0, cursor.getInt(2))
            assertEquals(0, cursor.getInt(3))
            assertEquals(0L, cursor.getLong(4))
            assertEquals(0L, cursor.getLong(5))
        }

        db.close()
        helper.close()
    }
}
