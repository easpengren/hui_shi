package com.example.ttsreader.playback

import android.content.Context
import android.net.Uri
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import com.example.ttsreader.data.ChunkEntity
import java.io.File

class AudioPlaybackEngine(context: Context) {
    private val player = ExoPlayer.Builder(context).build()
    private var chunkListenerAttached = false
    private var loadedChunks: MutableList<ChunkEntity> = mutableListOf()
    private var onChunkChangedCallback: ((ChunkEntity) -> Unit)? = null

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

    fun play() = player.play()

    fun appendChunk(chunk: ChunkEntity) {
        if (loadedChunks.any { it.chunkIndex == chunk.chunkIndex }) return
        loadedChunks.add(chunk)
        loadedChunks.sortBy { it.chunkIndex }
        player.addMediaItem(MediaItem.fromUri(Uri.fromFile(File(chunk.audioPath))))
    }

    fun pause() = player.pause()

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
        player.release()
    }
}
