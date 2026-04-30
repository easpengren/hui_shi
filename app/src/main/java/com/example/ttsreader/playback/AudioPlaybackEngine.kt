package com.example.ttsreader.playback

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import com.example.ttsreader.data.ChunkEntity
import java.io.File

class AudioPlaybackEngine(context: Context) {

    private val appContext = context.applicationContext
    private val audioManager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val player = ExoPlayer.Builder(appContext).build()

    private var chunkListenerAttached = false
    private var loadedChunks: MutableList<ChunkEntity> = mutableListOf()
    private var onChunkChangedCallback: ((ChunkEntity) -> Unit)? = null

    /** Called when another app steals audio focus (e.g. the assistant app). */
    var onFocusLost: (() -> Unit)? = null
    /** Called when focus is regained after a transient loss. */
    var onFocusGained: (() -> Unit)? = null

    private var wasPlayingBeforeLoss = false

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                // Permanent loss (another app took over) — pause and don't auto-resume.
                wasPlayingBeforeLoss = false
                if (player.isPlaying) player.pause()
                onFocusLost?.invoke()
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                // Transient loss (e.g. assistant speaks) — pause and remember to resume.
                wasPlayingBeforeLoss = player.isPlaying
                if (player.isPlaying) player.pause()
                onFocusLost?.invoke()
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                if (wasPlayingBeforeLoss) {
                    player.play()
                    onFocusGained?.invoke()
                }
                wasPlayingBeforeLoss = false
            }
        }
    }

    private val focusRequest: AudioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
        )
        .setAcceptsDelayedFocusGain(true)
        .setOnAudioFocusChangeListener(focusListener)
        .build()

    fun load(chunks: List<ChunkEntity>, onChunkChanged: (ChunkEntity) -> Unit) {
        loadedChunks = chunks.toMutableList()
        onChunkChangedCallback = onChunkChanged
        val items = loadedChunks.map { chunk ->
            MediaItem.fromUri(Uri.fromFile(File(chunk.audioPath)))
        }
        player.setMediaItems(items)
        player.prepare()

        if (!chunkListenerAttached) {
            player.addListener(object : Player.Listener {
                override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                    val idx = player.currentMediaItemIndex
                    if (idx in loadedChunks.indices) {
                        onChunkChangedCallback?.invoke(loadedChunks[idx])
                    }
                }
            })
            chunkListenerAttached = true
        }
    }

    fun play() {
        val result = audioManager.requestAudioFocus(focusRequest)
        if (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            player.play()
        }
        // AUDIOFOCUS_REQUEST_DELAYED: play() will be triggered via focusListener AUDIOFOCUS_GAIN
    }

    fun appendChunk(chunk: ChunkEntity) {
        if (loadedChunks.any { it.chunkIndex == chunk.chunkIndex }) return
        loadedChunks.add(chunk)
        loadedChunks.sortBy { it.chunkIndex }
        player.addMediaItem(MediaItem.fromUri(Uri.fromFile(File(chunk.audioPath))))
    }

    fun pause() {
        wasPlayingBeforeLoss = false
        player.pause()
        audioManager.abandonAudioFocusRequest(focusRequest)
    }

    fun seekToChunk(index: Int) {
        player.seekTo(index, 0L)
    }

    fun setSpeed(speed: Float) {
        player.setPlaybackSpeed(speed)
    }

    fun currentChunkIndex(): Int = player.currentMediaItemIndex.coerceAtLeast(0)

    fun currentPositionMs(): Long = player.currentPosition.coerceAtLeast(0L)

    fun durationMs(): Long = player.duration.takeIf { it > 0 } ?: 0L

    fun isPlaying(): Boolean = player.isPlaying

    fun release() {
        wasPlayingBeforeLoss = false
        audioManager.abandonAudioFocusRequest(focusRequest)
        player.release()
    }
}
