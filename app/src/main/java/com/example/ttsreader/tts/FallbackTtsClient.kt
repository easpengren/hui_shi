package com.example.ttsreader.tts

import com.example.ttsreader.core.Chunk
import java.io.File

class FallbackTtsClient(
    private val primary: TtsClient,
    private val fallback: TtsClient,
    private val onPrimaryFailure: ((Throwable) -> Unit)? = null
) : TtsClient {
    override suspend fun synthesizeChunk(bookId: String, chunk: Chunk): File {
        return runCatching {
            primary.synthesizeChunk(bookId, chunk)
        }.getOrElse {
            onPrimaryFailure?.invoke(it)
            fallback.synthesizeChunk(bookId, chunk)
        }
    }

    override fun release() {
        primary.release()
        fallback.release()
    }
}
