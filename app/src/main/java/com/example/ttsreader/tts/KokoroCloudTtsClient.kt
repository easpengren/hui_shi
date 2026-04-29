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

class KokoroCloudTtsClient(
    private val cacheManager: CacheManager,
    private val getVoice: () -> String = { "af_bella" }
) : TtsClient {
    private val service: KokoroApiService
    private val client: OkHttpClient
    private val moshi: Moshi

    init {
        val authInterceptor = Interceptor { chain ->
            val reqBuilder = chain.request().newBuilder()
            if (BuildConfig.KOKORO_API_KEY.isNotBlank()) {
                reqBuilder.addHeader("Authorization", "Bearer ${BuildConfig.KOKORO_API_KEY}")
                android.util.Log.d("KokoroCloudTtsClient", "[DEBUG] OkHttp added Authorization header: Bearer ${BuildConfig.KOKORO_API_KEY}")
            } else {
                android.util.Log.d("KokoroCloudTtsClient", "[DEBUG] OkHttp did NOT add Authorization header (API key blank)")
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
            .baseUrl(BuildConfig.KOKORO_API_BASE_URL)
            .client(client)
            .addConverterFactory(MoshiConverterFactory.create(moshi))
            .build()

        service = retrofit.create(KokoroApiService::class.java)
    }

    override suspend fun synthesizeChunk(bookId: String, chunk: Chunk): File = withContext(Dispatchers.IO) {
        val output = cacheManager.pathFor(bookId, chunk.index, "mp3")
        if (output.exists() && output.length() > 0L) return@withContext output
        if (output.exists()) output.delete()
        output.parentFile?.mkdirs()

        val requestInput = sanitizeText(chunk.ttsText.replace(Regex("\\s+"), " ").trim())
        val kokoroReq = KokoroRequest(
            text = requestInput,
            voice = getVoice(),
            model = "kokoro",
            format = "mp3"
        )
        // Log full request body using the correct Moshi instance
        android.util.Log.d("KokoroCloudTtsClient", "[DEBUG] Full TTS request body: ${moshi.adapter(KokoroRequest::class.java).toJson(kokoroReq)}")
        // Log headers (Authorization)
        val authHeader = BuildConfig.KOKORO_API_KEY.takeIf { it.isNotBlank() }?.let { "Bearer $it" } ?: "<none>"
        android.util.Log.d("KokoroCloudTtsClient", "[DEBUG] Authorization header: $authHeader")
        try {
            val response = service.synthesize(kokoroReq)

            if (!response.isSuccessful) {
                val bodyText = response.errorBody()?.string()?.take(400)?.replace("\n", " ") ?: ""
                val message = when (response.code()) {
                    401, 403 -> "Kokoro authentication failed (${response.code()}). Configure KOKORO_API_KEY in app/build.gradle.kts or gradle.properties."
                    405 -> "Kokoro request failed: 405 Method Not Allowed. Verify base URL and endpoint /v1/tts/. ${if (bodyText.isNotBlank()) "Details: $bodyText" else ""}".trim()
                    else -> "Kokoro request failed: ${response.code()} ${response.message()} ${if (bodyText.isNotBlank()) "- $bodyText" else ""}".trim()
                }
                error(message)
            }

            val body = response.body() ?: error("Kokoro response body was empty")
            val isJson = body.contentType()?.subtype?.contains("json", ignoreCase = true) == true

            if (isJson) {
                val queued = body.string()
                val queuedResponse = moshi.adapter(KokoroQueuedResponse::class.java).fromJson(queued)
                    ?: error("Kokoro queued response was invalid JSON")
                val uuid = queuedResponse.uuid ?: error("Kokoro queued response missing uuid")
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
                error("Kokoro returned an empty audio file")
            }
            output
        } catch (io: IOException) {
            output.delete()
            error("Network error while requesting Kokoro audio: ${io.message}")
        }
    }

    private suspend fun pollForResultUrl(uuid: String): String {
        repeat(30) { attempt ->
            val response = service.pollResult(uuid)
            if (!response.isSuccessful) {
                error("Kokoro poll failed: ${response.code()} ${response.message()}")
            }

            val body = response.body() ?: error("Kokoro poll response body was empty")
            when (body.status.lowercase()) {
                "completed" -> return body.result_url ?: error("Kokoro result completed but missing result_url")
                "failed" -> error("Kokoro generation failed${body.error?.let { ": $it" } ?: ""}")
            }

            if (attempt < 29) delay(1200L)
        }
        error("Kokoro result polling timed out")
    }

    private fun downloadToFile(url: String, output: File) {
        val req = Request.Builder().url(url).build()
        client.newCall(req).execute().use { res ->
            if (!res.isSuccessful) {
                error("Kokoro download failed: ${res.code} ${res.message}")
            }
            val body = res.body ?: error("Kokoro download response body was empty")
            output.outputStream().use { sink ->
                body.byteStream().use { source -> source.copyTo(sink) }
            }
        }
    }

    private fun sanitizeText(input: String): String {
        // Remove SSML tags like <break .../>
        val noTags = input.replace(Regex("<[^>]+>"), " ")
        // Convert 'point' number phrases to decimals (e.g., '2 point 0' -> '2.0')
        val pointToDecimal = noTags.replace(Regex("(\\d+) point (\\d+)", RegexOption.IGNORE_CASE), "$1.$2")
        return pointToDecimal
    }
}