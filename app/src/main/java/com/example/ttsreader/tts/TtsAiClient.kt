package com.example.ttsreader.tts

import com.example.ttsreader.BuildConfig
import com.example.ttsreader.core.Chunk
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Request
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory
import java.io.File
import java.io.IOException

class TtsAiClient(private val cacheManager: CacheManager) : TtsClient {
    private val service: TtsAiService
    private val client: OkHttpClient
    private val moshi: Moshi

    init {
        val authInterceptor = Interceptor { chain ->
            val reqBuilder = chain.request().newBuilder()
            if (BuildConfig.TTS_API_KEY.isNotBlank()) {
                reqBuilder.addHeader("Authorization", "Bearer ${BuildConfig.TTS_API_KEY}")
            }
            chain.proceed(reqBuilder.build())
        }

        client = OkHttpClient.Builder()
            .addInterceptor(authInterceptor)
            .build()

        moshi = Moshi.Builder()
            .add(KotlinJsonAdapterFactory())
            .build()

        val retrofit = Retrofit.Builder()
            .baseUrl(BuildConfig.TTS_API_BASE_URL)
            .client(client)
            .addConverterFactory(
                MoshiConverterFactory.create(
                    moshi
                )
            )
            .build()

        service = retrofit.create(TtsAiService::class.java)
    }

    override suspend fun synthesizeChunk(bookId: String, chunk: Chunk): File = withContext(Dispatchers.IO) {
        val output = cacheManager.pathFor(bookId, chunk.index, "mp3")
        if (output.exists() && output.length() > 0L) return@withContext output
        if (output.exists() && output.length() == 0L) {
            output.delete()
        }

        output.parentFile?.mkdirs()

        val requestInput = chunk.ttsText
            .replace(Regex("\\s+"), " ")
            .trim()

        try {
            val response = service.synthesize(
                TtsRequest(
                    // Send plain text to avoid malformed SSML/XML rejections.
                    text = requestInput,
                    model = "kokoro",
                    format = "mp3"
                )
            )

            if (!response.isSuccessful) {
                val bodyText = response.errorBody()?.string()?.take(400)?.replace("\n", " ") ?: ""
                val message = when (response.code()) {
                    401, 403 -> "TTS authentication failed (${response.code()}). Configure TTS_API_KEY in app/build.gradle.kts or gradle.properties."
                    405 -> "TTS request failed: 405 Method Not Allowed. Verify base URL and endpoint /v1/tts/. ${if (bodyText.isNotBlank()) "Details: $bodyText" else ""}".trim()
                    else -> "TTS request failed: ${response.code()} ${response.message()} ${if (bodyText.isNotBlank()) "- $bodyText" else ""}".trim()
                }
                error(message)
            }

            val body = response.body() ?: error("TTS response body was empty")
            val isJson = body.contentType()?.subtype?.contains("json", ignoreCase = true) == true

            if (isJson) {
                val queued = body.string()
                val queuedResponse = moshi.adapter(TtsQueuedResponse::class.java).fromJson(queued)
                    ?: error("TTS queued response was invalid JSON")
                val uuid = queuedResponse.uuid ?: error("TTS queued response missing uuid")
                val resultUrl = pollForResultUrl(uuid)
                downloadToFile(resultUrl, output)
            } else {
                output.outputStream().use { sink ->
                    body.byteStream().use { source ->
                        source.copyTo(sink)
                    }
                }
            }

            if (output.length() == 0L) {
                output.delete()
                error("TTS returned an empty audio file")
            }
            output
        } catch (io: IOException) {
            output.delete()
            error("Network error while requesting TTS audio: ${io.message}")
        }
    }

    private suspend fun pollForResultUrl(uuid: String): String {
        repeat(30) { attempt ->
            val response = service.pollResult(uuid)
            if (!response.isSuccessful) {
                error("TTS poll failed: ${response.code()} ${response.message()}")
            }

            val body = response.body() ?: error("TTS poll response body was empty")
            when (body.status.lowercase()) {
                "completed" -> {
                    return body.result_url ?: error("TTS result completed but missing result_url")
                }
                "failed" -> {
                    error("TTS generation failed${body.error?.let { ": $it" } ?: ""}")
                }
            }

            if (attempt < 29) delay(1200L)
        }
        error("TTS result polling timed out")
    }

    private fun downloadToFile(url: String, output: File) {
        val req = Request.Builder().url(url).build()
        client.newCall(req).execute().use { res ->
            if (!res.isSuccessful) {
                error("TTS download failed: ${res.code} ${res.message}")
            }
            val body = res.body ?: error("TTS download response body was empty")
            output.outputStream().use { sink ->
                body.byteStream().use { source -> source.copyTo(sink) }
            }
        }
    }
}
