package com.example.ttsreader.tts

import android.content.Context
import com.example.ttsreader.core.Chunk
import java.io.File

class KokoroNativeTtsClient(
    context: Context,
    cacheManager: CacheManager,
    preferredEnginePackage: String? = null
) : TtsClient {
    private val delegate = AndroidTtsClient(
        context = context,
        cacheManager = cacheManager,
        preferredEnginePackage = preferredEnginePackage
    )

    override suspend fun synthesizeChunk(bookId: String, chunk: Chunk): File {
        return delegate.synthesizeChunk(bookId, chunk)
    }

    override fun release() {
        delegate.release()
    }
}
