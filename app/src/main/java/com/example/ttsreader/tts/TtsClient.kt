package com.example.ttsreader.tts

import com.example.ttsreader.core.Chunk
import java.io.File

interface TtsClient {
    suspend fun synthesizeChunk(bookId: String, chunk: Chunk): File
    fun release() {}
}
