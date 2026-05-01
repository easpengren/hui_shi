package com.example.ttsreader.playback

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import com.example.ttsreader.data.ChunkEntity
import com.example.ttsreader.tts.sanitizeTtsText
import java.util.Locale

/**
 * Plays chunks using Android [TextToSpeech.speak] directly — no file I/O, no ExoPlayer.
 * Gives near-zero time-to-first-audio on all devices that have a system TTS engine installed.
 */
class SystemTtsPlayer(context: Context) : PlaybackEngine {

    private val appContext = context.applicationContext
    private val audioManager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    override var onFocusLost: (() -> Unit)? = null
    override var onFocusGained: (() -> Unit)? = null

    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var pendingPlay = false
    private var pendingSpeedRate = 1.0f

    private var loadedChunks: List<ChunkEntity> = emptyList()
    private var onChunkChangedCallback: ((ChunkEntity) -> Unit)? = null

    // List index (not chunkIndex) of the currently speaking chunk
    private var _currentListIndex = 0
    private var _isPlaying = false
    private var wasPlayingBeforeLoss = false
    private var chunkStartTimeMs = 0L
    private val focusRequest: AudioFocusRequest =
        AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAcceptsDelayedFocusGain(true)
            .setOnAudioFocusChangeListener { change ->
                when (change) {
                    AudioManager.AUDIOFOCUS_LOSS -> {
                        wasPlayingBeforeLoss = false
                        if (_isPlaying) {
                            tts?.stop()
                            _isPlaying = false
                            onFocusLost?.invoke()
                        }
                    }
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                        wasPlayingBeforeLoss = _isPlaying
                        if (_isPlaying) {
                            tts?.stop()
                            _isPlaying = false
                            onFocusLost?.invoke()
                        }
                    }
                    AudioManager.AUDIOFOCUS_GAIN -> {
                        if (wasPlayingBeforeLoss) {
                            speakFrom(_currentListIndex)
                            onFocusGained?.invoke()
                        }
                        wasPlayingBeforeLoss = false
                    }
                }
            }
            .build()

    private val utteranceListener = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String?) {
            val chunkIdx = parseChunkIndex(utteranceId) ?: return
            val listIndex = loadedChunks.indexOfFirst { it.chunkIndex == chunkIdx }
            if (listIndex < 0) return
            _currentListIndex = listIndex
            chunkStartTimeMs = System.currentTimeMillis()
            onChunkChangedCallback?.invoke(loadedChunks[listIndex])
        }

        override fun onDone(utteranceId: String?) {
            val chunkIdx = parseChunkIndex(utteranceId) ?: return
            val listIndex = loadedChunks.indexOfFirst { it.chunkIndex == chunkIdx }
            if (listIndex == loadedChunks.lastIndex) {
                _isPlaying = false
                audioManager.abandonAudioFocusRequest(focusRequest)
            }
        }

        @Deprecated("Required abstract until API 23")
        override fun onError(utteranceId: String?) {
            Log.w(TAG, "TTS error for utterance $utteranceId")
        }

        override fun onError(utteranceId: String?, errorCode: Int) {
            Log.w(TAG, "TTS error $errorCode for utterance $utteranceId")
        }
    }

    init {
        tts = TextToSpeech(appContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                val localeResult = tts?.setLanguage(Locale.getDefault()) ?: TextToSpeech.LANG_NOT_SUPPORTED
                if (localeResult == TextToSpeech.LANG_MISSING_DATA || localeResult == TextToSpeech.LANG_NOT_SUPPORTED) {
                    tts?.setLanguage(Locale.US)
                }
                tts?.setOnUtteranceProgressListener(utteranceListener)
                ttsReady = true
                if (pendingPlay) {
                    pendingPlay = false
                    tts?.setSpeechRate(pendingSpeedRate)
                    speakFrom(_currentListIndex)
                }
            } else {
                Log.e(TAG, "System TTS init failed (status=$status)")
            }
        }
    }

    override fun load(chunks: List<ChunkEntity>, onChunkChanged: (ChunkEntity) -> Unit) {
        tts?.stop()
        _isPlaying = false
        loadedChunks = chunks
        onChunkChangedCallback = onChunkChanged
        _currentListIndex = 0
    }

    override fun play(): PlaybackStartResult {
        if (!ttsReady) {
            pendingPlay = true
            wasPlayingBeforeLoss = true
            return PlaybackStartResult.DELAYED
        }
        val result = audioManager.requestAudioFocus(focusRequest)
        return when (result) {
            AudioManager.AUDIOFOCUS_REQUEST_GRANTED -> {
                wasPlayingBeforeLoss = false
                speakFrom(_currentListIndex)
                PlaybackStartResult.GRANTED
            }
            AudioManager.AUDIOFOCUS_REQUEST_DELAYED -> {
                wasPlayingBeforeLoss = true
                PlaybackStartResult.DELAYED
            }
            else -> {
                wasPlayingBeforeLoss = false
                PlaybackStartResult.FAILED
            }
        }
    }

    override fun pause() {
        wasPlayingBeforeLoss = false
        tts?.stop()
        _isPlaying = false
        audioManager.abandonAudioFocusRequest(focusRequest)
    }

    override fun seekToChunk(index: Int) {
        val wasPlaying = _isPlaying
        tts?.stop()
        _isPlaying = false
        _currentListIndex = index.coerceIn(0, loadedChunks.lastIndex.coerceAtLeast(0))
        if (wasPlaying) speakFrom(_currentListIndex)
    }

    override fun setSpeed(speed: Float) {
        pendingSpeedRate = speed
        tts?.setSpeechRate(speed)
    }

    // appendChunk: System TTS loads all chunks upfront; no-op here.
    override fun appendChunk(chunk: ChunkEntity) {}

    override fun currentChunkIndex(): Int = _currentListIndex

    override fun currentPositionMs(): Long {
        if (!_isPlaying) return 0L
        return (System.currentTimeMillis() - chunkStartTimeMs).coerceAtLeast(0L)
    }

    override fun durationMs(): Long =
        loadedChunks.getOrNull(_currentListIndex)?.estimatedDurationMs ?: 0L

    override fun isPlaying(): Boolean = _isPlaying

    override fun release() {
        wasPlayingBeforeLoss = false
        tts?.stop()
        tts?.shutdown()
        tts = null
        ttsReady = false
        audioManager.abandonAudioFocusRequest(focusRequest)
    }

    private fun speakFrom(startIndex: Int) {
        if (!ttsReady || loadedChunks.isEmpty()) return
        tts?.stop()
        _isPlaying = true
        val safeStart = startIndex.coerceIn(0, loadedChunks.lastIndex)
        loadedChunks.drop(safeStart).forEachIndexed { offset, chunk ->
            val queueMode = if (offset == 0) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD
            val utteranceId = "chunk_${chunk.chunkIndex}"
            val spokenText = sanitizeTtsText(chunk.ttsText)
            tts?.speak(spokenText, queueMode, null, utteranceId)
        }
    }

    private fun parseChunkIndex(utteranceId: String?): Int? =
        utteranceId?.removePrefix("chunk_")?.toIntOrNull()

    companion object {
        private const val TAG = "SystemTtsPlayer"
    }
}
