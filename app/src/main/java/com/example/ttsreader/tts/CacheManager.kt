package com.example.ttsreader.tts

import android.content.Context
import java.io.File

class CacheManager(context: Context) {
    private val root = File(context.cacheDir, "tts_audio").apply { mkdirs() }

    fun pathFor(bookId: String, chunkIndex: Int, extension: String = "mp3"): File {
        val bookDir = File(root, bookId).apply { mkdirs() }
        return File(bookDir, "chunk_${chunkIndex}.$extension")
    }

    fun clearBook(bookId: String) {
        File(root, bookId).deleteRecursively()
    }
}
