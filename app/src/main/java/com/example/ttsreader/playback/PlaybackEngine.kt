package com.example.ttsreader.playback

import com.example.ttsreader.data.ChunkEntity

enum class PlaybackStartResult {
    GRANTED,
    DELAYED,
    FAILED
}

interface PlaybackEngine {
    var onFocusLost: (() -> Unit)?
    var onFocusGained: (() -> Unit)?

    fun load(chunks: List<ChunkEntity>, onChunkChanged: (ChunkEntity) -> Unit)
    fun play(): PlaybackStartResult
    fun appendChunk(chunk: ChunkEntity) {}
    fun pause()
    fun seekToChunk(index: Int)
    fun setSpeed(speed: Float)
    fun currentChunkIndex(): Int
    fun currentPositionMs(): Long
    fun durationMs(): Long
    fun isPlaying(): Boolean
    fun release()
}
