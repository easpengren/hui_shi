package com.example.ttsreader.tts

import com.example.ttsreader.core.Chunk
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class FallbackTtsClientTest {

    private val dummyFile = File.createTempFile("tts_test", ".mp3").also { it.deleteOnExit() }

    private fun chunk(index: Int = 0) = Chunk(
        index = index,
        displayText = "Hello",
        ttsText = "Hello",
        startOffset = 0,
        endOffset = 5
    )

    private fun successClient(file: File = dummyFile): TtsClient = object : TtsClient {
        override suspend fun synthesizeChunk(bookId: String, chunk: Chunk): File = file
    }

    private fun failingClient(message: String = "boom"): TtsClient = object : TtsClient {
        override suspend fun synthesizeChunk(bookId: String, chunk: Chunk): File = error(message)
    }

    // ── primary success ──────────────────────────────────────────────────────

    @Test
    fun primarySuccess_returnsPrimaryFile() = runBlocking {
        val expected = dummyFile
        val client = FallbackTtsClient(primary = successClient(expected), fallback = failingClient())
        val result = client.synthesizeChunk("book", chunk())
        assertSame(expected, result)
    }

    @Test
    fun primarySuccess_doesNotInvokeFailureCallback() = runBlocking {
        var callbackInvoked = false
        val client = FallbackTtsClient(
            primary = successClient(),
            fallback = failingClient(),
            onPrimaryFailure = { callbackInvoked = true }
        )
        client.synthesizeChunk("book", chunk())
        assertTrue(!callbackInvoked)
    }

    // ── primary failure → fallback ───────────────────────────────────────────

    @Test
    fun primaryFails_fallbackResultReturned() = runBlocking {
        val fallbackFile = File.createTempFile("fallback", ".mp3").also { it.deleteOnExit() }
        val client = FallbackTtsClient(primary = failingClient(), fallback = successClient(fallbackFile))
        val result = client.synthesizeChunk("book", chunk())
        assertSame(fallbackFile, result)
    }

    @Test
    fun primaryFails_callbackInvokedWithThrowable() = runBlocking {
        var captured: Throwable? = null
        val client = FallbackTtsClient(
            primary = failingClient("server down"),
            fallback = successClient(),
            onPrimaryFailure = { captured = it }
        )
        client.synthesizeChunk("book", chunk())
        assertEquals("server down", captured?.message)
    }

    @Test
    fun noCallback_primaryFails_stillFallsBack() = runBlocking {
        val fallbackFile = File.createTempFile("fallback2", ".mp3").also { it.deleteOnExit() }
        val client = FallbackTtsClient(
            primary = failingClient(),
            fallback = successClient(fallbackFile),
            onPrimaryFailure = null
        )
        val result = client.synthesizeChunk("book", chunk())
        assertSame(fallbackFile, result)
    }

    // ── release ──────────────────────────────────────────────────────────────

    @Test
    fun release_callsBothClients() = runBlocking {
        var primaryReleased = false
        var fallbackReleased = false
        val primary = object : TtsClient {
            override suspend fun synthesizeChunk(bookId: String, chunk: Chunk): File = dummyFile
            override fun release() { primaryReleased = true }
        }
        val fallback = object : TtsClient {
            override suspend fun synthesizeChunk(bookId: String, chunk: Chunk): File = dummyFile
            override fun release() { fallbackReleased = true }
        }
        FallbackTtsClient(primary, fallback).release()
        assertTrue(primaryReleased)
        assertTrue(fallbackReleased)
    }

    // ── multiple chunks ──────────────────────────────────────────────────────

    @Test
    fun multipleChunks_eachReturnedCorrectly() = runBlocking {
        val files = (0..4).map { File.createTempFile("chunk$it", ".mp3").also { f -> f.deleteOnExit() } }
        var call = 0
        val primary = object : TtsClient {
            override suspend fun synthesizeChunk(bookId: String, chunk: Chunk): File = files[call++]
        }
        val client = FallbackTtsClient(primary = primary, fallback = failingClient())
        (0..4).forEach { i ->
            val result = client.synthesizeChunk("book", chunk(i))
            assertSame(files[i], result)
        }
    }
}
