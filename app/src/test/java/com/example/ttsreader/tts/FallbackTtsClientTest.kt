package com.example.ttsreader.tts

import com.example.ttsreader.core.Chunk
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class FallbackTtsClientTest {

    private fun chunk(index: Int = 0) = Chunk(
        index = index,
        displayText = "Hello",
        ttsText = "Hello",
        startOffset = 0,
        endOffset = 5
    )

    @Test
    fun primarySuccess_returnsPrimaryFile() = runBlocking {
        val primaryFile = File.createTempFile("primary", ".wav").also { it.deleteOnExit() }
        val primary = object : TtsClient {
            override suspend fun synthesizeChunk(bookId: String, chunk: Chunk): File = primaryFile
        }
        val secondary = object : TtsClient {
            override suspend fun synthesizeChunk(bookId: String, chunk: Chunk): File =
                error("secondary should not be called")
        }

        val client = FallbackTtsClient(primary = primary, secondary = secondary)
        val result = client.synthesizeChunk("book", chunk())
        assertSame(primaryFile, result)
    }

    @Test
    fun primaryFailure_usesSecondary() = runBlocking {
        val secondaryFile = File.createTempFile("secondary", ".wav").also { it.deleteOnExit() }
        val primary = object : TtsClient {
            override suspend fun synthesizeChunk(bookId: String, chunk: Chunk): File =
                throw IllegalStateException("boom")
        }
        val secondary = object : TtsClient {
            override suspend fun synthesizeChunk(bookId: String, chunk: Chunk): File = secondaryFile
        }

        val client = FallbackTtsClient(primary = primary, secondary = secondary)
        val result = client.synthesizeChunk("book", chunk())
        assertSame(secondaryFile, result)
    }

    @Test
    fun bothFail_rethrowsSecondaryFailure() = runBlocking {
        val primary = object : TtsClient {
            override suspend fun synthesizeChunk(bookId: String, chunk: Chunk): File =
                throw IllegalStateException("primary failed")
        }
        val secondary = object : TtsClient {
            override suspend fun synthesizeChunk(bookId: String, chunk: Chunk): File =
                throw IllegalStateException("secondary failed")
        }

        val client = FallbackTtsClient(primary = primary, secondary = secondary)
        var threw = false
        try {
            client.synthesizeChunk("book", chunk())
        } catch (e: IllegalStateException) {
            threw = true
            assertTrue(e.message?.contains("secondary failed") == true)
        }
        assertTrue(threw)
    }

    @Test
    fun release_noopDoesNotReleaseChildren() {
        var primaryReleased = false
        var secondaryReleased = false

        val primary = object : TtsClient {
            override suspend fun synthesizeChunk(bookId: String, chunk: Chunk): File =
                File.createTempFile("p", ".wav")

            override fun release() {
                primaryReleased = true
            }
        }
        val secondary = object : TtsClient {
            override suspend fun synthesizeChunk(bookId: String, chunk: Chunk): File =
                File.createTempFile("s", ".wav")

            override fun release() {
                secondaryReleased = true
            }
        }

        FallbackTtsClient(primary = primary, secondary = secondary).release()
        assertFalse(primaryReleased)
        assertFalse(secondaryReleased)
    }
}
