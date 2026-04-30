package com.example.ttsreader.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TextCleanerTest {

    private val cleaner = TextCleaner()

    // ── cleanInline ──────────────────────────────────────────────────────────

    @Test
    fun cleanInline_removesSuperscipts() {
        // Superscripts are removed entirely, not converted to ASCII digits
        val result = cleaner.cleanInline("CO\u00B2 emissions")
        assertFalse("superscript should be removed", result.contains("\u00B2"))
        assertTrue(result.contains("CO"))
    }

    @Test
    fun cleanInline_removesInlineFootnoteNumbers() {
        // Regex requires (?<=\w) — footnote marker must immediately follow a word character
        assertEquals("word", cleaner.cleanInline("word[1]"))
        assertEquals("word", cleaner.cleanInline("word(2)"))
        assertEquals("word", cleaner.cleanInline("word*"))
        assertEquals("word", cleaner.cleanInline("word†"))
        // After a non-word char (period) the marker is NOT stripped
        assertTrue(cleaner.cleanInline("end.[1]").contains("[1]"))
    }

    @Test
    fun cleanInline_collapsesWhitespace() {
        assertEquals("hello world", cleaner.cleanInline("hello   world"))
    }

    @Test
    fun cleanInline_trimsResult() {
        assertEquals("hello", cleaner.cleanInline("  hello  "))
    }

    @Test
    fun cleanInline_emptyInput_returnsEmpty() {
        assertEquals("", cleaner.cleanInline(""))
    }

    // ── removeHeadersAndFooters ──────────────────────────────────────────────

    @Test
    fun removeHeadersAndFooters_emptyPages_returnsEmpty() {
        assertEquals(emptyList<Page>(), cleaner.removeHeadersAndFooters(emptyList()))
    }

    @Test
    fun removeHeadersAndFooters_singlePage_nothingRemoved() {
        // A page with enough lines so take(2) and takeLast(2) don't overlap,
        // and no line appears in both candidate sets.
        val lines = listOf("Alpha line", "Beta line", "Gamma line", "Delta line")
        val pages = listOf(Page(0, lines))
        val result = cleaner.removeHeadersAndFooters(pages)
        assertEquals(lines, result[0].lines)
    }

    @Test
    fun removeHeadersAndFooters_repeatedHeaderStripped() {
        // Use body text without digits so normalization doesn't collapse page-unique text
        // into the same key as the header.
        val pages = listOf(
            Page(0, listOf("Story Header", "First body line", "More first body", "End first")),
            Page(1, listOf("Story Header", "Second body line", "More second body", "End second")),
            Page(2, listOf("Story Header", "Third body line", "More third body", "End third"))
        )
        val result = cleaner.removeHeadersAndFooters(pages)
        result.forEach { page ->
            assertFalse("Header should be stripped", page.lines.any { it == "Story Header" })
        }
    }

    @Test
    fun removeHeadersAndFooters_repeatedFooterStripped() {
        val pages = (1..3).map { i ->
            Page(i, listOf("Body text $i", "Page $i"))
        }
        val result = cleaner.removeHeadersAndFooters(pages)
        // Normalised "Page #" appears 3 times, threshold=2 → should be stripped
        result.forEach { page ->
            assertFalse("Footer should be stripped", page.lines.any { it.startsWith("Page ") })
        }
    }

    @Test
    fun removeHeadersAndFooters_uniqueLines_notStripped() {
        // Body lines use distinct non-digit words per page so normalization keeps them unique.
        val pages = listOf(
            Page(0, listOf("Story Header", "Alpha fox jumps quickly", "More alpha text here", "End alpha")),
            Page(1, listOf("Story Header", "Beta wolf runs swiftly", "More beta text here", "End beta")),
            Page(2, listOf("Story Header", "Gamma bear walks slowly", "More gamma text here", "End gamma"))
        )
        val result = cleaner.removeHeadersAndFooters(pages)
        assertTrue(result[0].lines.any { it.contains("Alpha fox") })
        assertTrue(result[1].lines.any { it.contains("Beta wolf") })
        assertTrue(result[2].lines.any { it.contains("Gamma bear") })
    }

    @Test
    fun removeHeadersAndFooters_positionedLines_headerRegionStripped() {
        val pageHeight = 800f
        // y=20 is in header region (< 14% of 800 = 112)
        val header = PositionedLine("Running Header", x = 10f, y = 20f, width = 200f, height = 12f)
        val body = PositionedLine("Body text here", x = 10f, y = 400f, width = 200f, height = 12f)

        val pages = (1..3).map {
            Page(it, emptyList(), positionedLines = listOf(header, body), pageHeight = pageHeight)
        }
        val result = cleaner.removeHeadersAndFooters(pages)
        result.forEach { page ->
            assertFalse(page.positionedLines.any { it.text == "Running Header" })
            assertTrue(page.positionedLines.any { it.text == "Body text here" })
        }
    }
}
