package com.example.ttsreader.tts

import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import com.example.ttsreader.core.Chunk
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.io.File
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

class AndroidTtsClient(
    context: Context,
    private val cacheManager: CacheManager
) : TtsClient {
    private val synthesisTimeoutMs = 30_000L
    private val linkRegex = Regex("\\[([^\\]]+)]\\(([^)]+)\\)")
    private val headingRegex = Regex("(?m)^\\s{0,3}#{1,6}\\s*")
    private val codeFenceRegex = Regex("```[\\s\\S]*?```")
    private val htmlTagRegex = Regex("<[^>]+>")
    private val appContext = context.applicationContext
    private val initStatus = CompletableDeferred<Int>()
    private val pendingUtterances = ConcurrentHashMap<String, CompletableDeferred<Unit>>()

    @Volatile
    private var engine: TextToSpeech? = null

    init {
        Handler(Looper.getMainLooper()).post {
            val tts = TextToSpeech(appContext) { status ->
                initStatus.complete(status)
            }
            tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) = Unit

                override fun onDone(utteranceId: String?) {
                    utteranceId ?: return
                    pendingUtterances.remove(utteranceId)?.complete(Unit)
                }

                override fun onError(utteranceId: String?) {
                    utteranceId ?: return
                    pendingUtterances.remove(utteranceId)
                        ?.completeExceptionally(IllegalStateException("Local TTS failed for utterance $utteranceId"))
                }

                override fun onError(utteranceId: String?, errorCode: Int) {
                    utteranceId ?: return
                    pendingUtterances.remove(utteranceId)
                        ?.completeExceptionally(IllegalStateException("Local TTS failed for utterance $utteranceId (code=$errorCode)"))
                }
            })
            engine = tts
        }
    }

    override suspend fun synthesizeChunk(bookId: String, chunk: Chunk): File = withContext(Dispatchers.IO) {
        val output = cacheManager.pathFor(bookId, chunk.index, "wav")
        if (output.exists() && output.length() > 0L) return@withContext output
        if (output.exists()) output.delete()
        output.parentFile?.mkdirs()

        val status = initStatus.await()
        if (status != TextToSpeech.SUCCESS) {
            error("Local TextToSpeech initialization failed (status=$status)")
        }

        val tts = engine ?: error("Local TextToSpeech engine is unavailable")
        if (tts.language == null) {
            tts.language = Locale.US
        }

        val normalizedText = sanitizeForLocalTts(chunk.displayText)
        if (normalizedText.isBlank()) {
            error("Chunk ${chunk.index} has no speakable text")
        }

        val maxLen = TextToSpeech.getMaxSpeechInputLength()
        if (normalizedText.length > maxLen) {
            error("Local TextToSpeech input exceeds max length for chunk ${chunk.index} (${normalizedText.length}/$maxLen)")
        }

        val utteranceId = "${bookId}_${chunk.index}_${System.nanoTime()}"
        val completion = CompletableDeferred<Unit>()
        pendingUtterances[utteranceId] = completion

        val params = Bundle().apply {
            putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
        }

        val result = tts.synthesizeToFile(normalizedText, params, output, utteranceId)
        if (result != TextToSpeech.SUCCESS) {
            pendingUtterances.remove(utteranceId)
            output.delete()
            error("Local TextToSpeech synthesis start failed (code=$result)")
        }

        try {
            withTimeout(synthesisTimeoutMs) {
                completion.await()
            }
        } catch (_: TimeoutCancellationException) {
            pendingUtterances.remove(utteranceId)
            output.delete()
            error("Local TextToSpeech timed out while generating chunk ${chunk.index}")
        }
        if (!output.exists() || output.length() == 0L) {
            output.delete()
            error("Local TextToSpeech produced empty audio output")
        }
        output
    }

    override fun release() {
        pendingUtterances.values.forEach {
            it.completeExceptionally(IllegalStateException("Local TTS client released before synthesis completed"))
        }
        pendingUtterances.clear()
        engine?.stop()
        engine?.shutdown()
        engine = null
    }

    private fun sanitizeForLocalTts(input: String): String {
        return input
            .replace(codeFenceRegex, " ")
            .replace(linkRegex, "$1")
            .replace(headingRegex, "")
            .replace(htmlTagRegex, " ")
            .replace(Regex("[`*_~]"), "")
            .replace(Regex("\\s+"), " ")
            .trim()
    }
}
