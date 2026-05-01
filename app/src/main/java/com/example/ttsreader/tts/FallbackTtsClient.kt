package com.example.ttsreader.tts

import android.util.Log
import com.example.ttsreader.core.Chunk
import java.io.File

/**
 * Tries [primary] first. On any failure, cleans up and delegates to [secondary].
 */
class FallbackTtsClient(
    private val primary: TtsClient,
    private val secondary: TtsClient
) : TtsClient {

    override suspend fun synthesizeChunk(bookId: String, chunk: Chunk): File {
        return try {
            primary.synthesizeChunk(bookId, chunk)
        } catch (e: Exception) {
            runCatching {
                Log.w(TAG, "Primary TTS failed for chunk ${chunk.index}, trying secondary: ${e.message}")
            }
            secondary.synthesizeChunk(bookId, chunk)
        }
    }

    // FallbackTtsClient does not own its children; caller releases them separately.
    override fun release() {}

    companion object {
        private const val TAG = "FallbackTtsClient"
    }
}
