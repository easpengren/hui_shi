package com.example.ttsreader.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChunkerTest {

    private val normalizer = SmartPunctuationNormalizer()
    private val chunker = Chunker()

    private fun chapters(vararg texts: String): List<Pair<String?, String>> =
        texts.mapIndexed { i, t -> "Chapter ${i + 1}" to t }

    // ── basic splitting ──────────────────────────────────────────────────────

    @Test
    fun shortText_producesOneChunk() {
        val input = chapters("Hello world. This is a short text.")
        val chunks = chunker.chunk(input, normalizer, maxLen = 2500)
        assertEquals(1, chunks.size)
    }

    @Test
    fun emptyChapter_producesNoChunks() {
        val input = chapters("   ")
        val chunks = chunker.chunk(input, normalizer, maxLen = 2500)
        assertEquals(0, chunks.size)
    }

    @Test
    fun longText_splitsIntoMultipleChunks() {
        val sentence = "This is a sentence. "
        val longText = sentence.repeat(200)   // ~3800 chars
        val input = chapters(longText)
        val chunks = chunker.chunk(input, normalizer, maxLen = 1000)
        assertTrue("expected multiple chunks", chunks.size > 1)
    }

    @Test
    fun noChunk_exceedsMaxLen() {
        val sentence = "Short sentence here. "
        val longText = sentence.repeat(200)
        val input = chapters(longText)
        val chunks = chunker.chunk(input, normalizer, maxLen = 1000)
        chunks.forEach { chunk ->
            assertTrue(
                "chunk ${chunk.index} display text length ${chunk.displayText.length} > 1200",
                chunk.displayText.length <= 1200  // allow overshoot at split point
            )
        }
    }

    @Test
    fun chunkIndexesAreSequential() {
        val sentence = "Word. "
        val input = chapters(sentence.repeat(500))
        val chunks = chunker.chunk(input, normalizer, maxLen = 500)
        chunks.forEachIndexed { i, chunk -> assertEquals(i, chunk.index) }
    }

    // ── offsets ──────────────────────────────────────────────────────────────

    @Test
    fun singleChunk_startOffsetIsZero() {
        val input = chapters("Hello world.")
        val chunks = chunker.chunk(input, normalizer, maxLen = 2500)
        assertEquals(0, chunks.first().startOffset)
    }

    @Test
    fun offsets_doNotOverlap() {
        val sentence = "Sentence here. "
        val input = chapters(sentence.repeat(100))
        val chunks = chunker.chunk(input, normalizer, maxLen = 400)
        for (i in 1 until chunks.size) {
            assertTrue(
                "chunk $i start ${chunks[i].startOffset} < prev end ${chunks[i - 1].endOffset}",
                chunks[i].startOffset >= chunks[i - 1].endOffset
            )
        }
    }

    @Test
    fun wordRanges_countMatchesWordCount() {
        val text = "one two three four five"
        val input = chapters(text)
        val chunks = chunker.chunk(input, normalizer, maxLen = 2500)
        assertEquals(5, chunks.first().wordRanges.size)
    }

    // ── chapter metadata ─────────────────────────────────────────────────────

    @Test
    fun chapterTitle_propagatesToChunks() {
        val input = listOf("Intro" to "Short intro text.")
        val chunks = chunker.chunk(input, normalizer)
        assertEquals("Intro", chunks.first().chapterTitle)
    }

    @Test
    fun nullChapterTitle_propagatedAsNull() {
        val input = listOf(null to "Some text here.")
        val chunks = chunker.chunk(input, normalizer)
        assertEquals(null, chunks.first().chapterTitle)
    }

    @Test
    fun multipleChapters_produceSeparateChunkGroups() {
        val input = listOf(
            "Chapter One" to "First chapter content.",
            "Chapter Two" to "Second chapter content."
        )
        val chunks = chunker.chunk(input, normalizer)
        assertEquals(2, chunks.size)
        assertEquals("Chapter One", chunks[0].chapterTitle)
        assertEquals("Chapter Two", chunks[1].chapterTitle)
    }

    // ── duration estimate ────────────────────────────────────────────────────

    @Test
    fun estimatedDuration_isPositive() {
        val input = chapters("Hello world.")
        val chunk = chunker.chunk(input, normalizer).first()
        assertTrue(chunk.estimatedDurationMs > 0L)
    }

    @Test
    fun longerText_hasLongerEstimatedDuration() {
        val short = chapters("Hi.")
        val long = chapters("This is a much longer text with many more words and sentences that should take longer to speak.")
        val shortDuration = chunker.chunk(short, normalizer).first().estimatedDurationMs
        val longDuration = chunker.chunk(long, normalizer).first().estimatedDurationMs
        assertTrue(longDuration > shortDuration)
    }

    // ── ttsText ──────────────────────────────────────────────────────────────

    @Test
    fun ttsText_differFromDisplayTextAfterNormalization() {
        val input = chapters("version 3.14 is here.")
        val chunk = chunker.chunk(input, normalizer).first()
        assertTrue("ttsText should contain 'point'", chunk.ttsText.contains("point"))
        assertFalse("displayText should not contain 'point'", chunk.displayText.contains("point"))
    }
}
