package com.example.ttsreader.tts

import android.content.Context
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import com.example.ttsreader.core.Chunk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Locale
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class SystemTtsClient(
    context: Context,
    private val cacheManager: CacheManager,
    private val getSpeed: () -> Float = { 1.0f }
) : TtsClient {

    private val appContext = context.applicationContext
    private val initLock = Mutex()
    private var tts: TextToSpeech? = null

    private suspend fun ensureTts(): TextToSpeech = initLock.withLock {
        tts?.let { return@withLock it }
        val engine = withContext(Dispatchers.Main) {
            suspendCancellableCoroutine { cont ->
                lateinit var instance: TextToSpeech
                instance = TextToSpeech(appContext) { status ->
                    if (status == TextToSpeech.SUCCESS) {
                        cont.resume(instance)
                    } else {
                        cont.resumeWithException(
                            IllegalStateException("System TTS init failed (status=$status)")
                        )
                    }
                }
                cont.invokeOnCancellation { instance.shutdown() }
            }
        }
        val localeResult = engine.setLanguage(Locale.getDefault())
        if (localeResult == TextToSpeech.LANG_MISSING_DATA || localeResult == TextToSpeech.LANG_NOT_SUPPORTED) {
            Log.w(TAG, "Default locale not supported by system TTS, using US English")
            engine.setLanguage(Locale.US)
        }
        tts = engine
        engine
    }

    override suspend fun synthesizeChunk(bookId: String, chunk: Chunk): File =
        withContext(Dispatchers.IO) {
            val output = cacheManager.pathFor(bookId, chunk.index, "wav")
            if (output.exists() && output.length() > 0L) {
                Log.i(TAG, "Using cached system TTS chunk ${chunk.index}")
                return@withContext output
            }
            if (output.exists()) output.delete()
            output.parentFile?.mkdirs()

            val engine = ensureTts()
            engine.setSpeechRate(getSpeed())

            val utteranceId = "chunk_${bookId}_${chunk.index}"
            val params = Bundle().apply {
                putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
            }

            Log.i(TAG, "Synthesizing system TTS chunk ${chunk.index}")
            try {
                suspendCancellableCoroutine<Unit> { cont ->
                    engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                        override fun onStart(id: String?) {}

                        override fun onDone(id: String?) {
                            if (id == utteranceId) {
                                cont.resume(Unit)
                            }
                        }

                        @Deprecated("Deprecated in API 21, still required as abstract until API 23")
                        override fun onError(id: String?) {
                            if (id == utteranceId) {
                                cont.resumeWithException(
                                    IllegalStateException("System TTS synthesis failed for chunk ${chunk.index}")
                                )
                            }
                        }

                        override fun onError(id: String?, errorCode: Int) {
                            if (id == utteranceId) {
                                cont.resumeWithException(
                                    IllegalStateException(
                                        "System TTS synthesis failed for chunk ${chunk.index} (error=$errorCode)"
                                    )
                                )
                            }
                        }
                    })

                    val result = engine.synthesizeToFile(
                        sanitizeTtsText(chunk.ttsText),
                        params,
                        output,
                        utteranceId
                    )
                    if (result != TextToSpeech.SUCCESS) {
                        cont.resumeWithException(
                            IllegalStateException("System TTS queue failed for chunk ${chunk.index}")
                        )
                    }
                    cont.invokeOnCancellation { engine.stop() }
                }
            } catch (e: Exception) {
                output.delete()
                throw e
            }
            output
        }

    override fun release() {
        tts?.shutdown()
        tts = null
    }

    companion object {
        private const val TAG = "SystemTtsClient"
    }
}
