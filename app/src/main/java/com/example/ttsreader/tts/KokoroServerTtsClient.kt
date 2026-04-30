package com.example.ttsreader.tts

import android.util.Log
import com.example.ttsreader.BuildConfig
import com.example.ttsreader.core.Chunk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * Calls kokoro-web's OpenAI-compatible /v1/audio/speech endpoint directly.
 * Returns a streamed MP3 file with no polling or intermediate queue.
 */
class KokoroServerTtsClient(
    private val cacheManager: CacheManager,
    private val getVoice: () -> String = { "af_bella" }
) : TtsClient {

    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(120, TimeUnit.SECONDS)
        .build()

    override suspend fun synthesizeChunk(bookId: String, chunk: Chunk): File = withContext(Dispatchers.IO) {
        val output = cacheManager.pathFor(bookId, chunk.index, "mp3")
        if (output.exists() && output.length() > 0L) return@withContext output
        if (output.exists()) output.delete()
        output.parentFile?.mkdirs()

        val text = sanitizeText(chunk.ttsText.replace(Regex("\\s+"), " ").trim())
        val body = JSONObject().apply {
            put("model", "kokoro")
            put("input", text)
            put("voice", getVoice())
            put("response_format", "mp3")
        }.toString().toRequestBody("application/json".toMediaType())

        val url = BuildConfig.KOKORO_API_BASE_URL.trimEnd('/') + "/v1/audio/speech"
        val reqBuilder = Request.Builder().url(url).post(body)
        if (BuildConfig.KOKORO_API_KEY.isNotBlank()) {
            reqBuilder.addHeader("Authorization", "Bearer ${BuildConfig.KOKORO_API_KEY}")
        }

        Log.d(TAG, "POST $url voice=${getVoice()} chars=${text.length}")

        try {
            client.newCall(reqBuilder.build()).execute().use { response ->
                if (!response.isSuccessful) {
                    val detail = response.body?.string()?.take(300)?.replace("\n", " ") ?: ""
                    val msg = when (response.code) {
                        401, 403 -> "Kokoro auth failed (${response.code}). Check KOKORO_API_KEY."
                        else -> "Kokoro error ${response.code}: $detail"
                    }
                    error(msg)
                }
                val responseBody = response.body ?: error("Kokoro returned empty response body")
                output.outputStream().use { sink ->
                    responseBody.byteStream().use { source -> source.copyTo(sink) }
                }
            }
            if (output.length() == 0L) {
                output.delete()
                error("Kokoro returned empty audio")
            }
            output
        } catch (io: IOException) {
            output.delete()
            error("Network error contacting Kokoro: ${io.message}")
        }
    }

    private fun sanitizeText(input: String): String =
        input
            .replace(Regex("<[^>]+>"), " ")
            .replace(Regex("(\\d+) point (\\d+)", RegexOption.IGNORE_CASE), "$1.$2")
            .trim()

    companion object {
        private const val TAG = "KokoroServerTtsClient"
    }
}