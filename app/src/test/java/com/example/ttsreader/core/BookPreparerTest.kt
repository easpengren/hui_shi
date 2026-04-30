package com.example.ttsreader.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BookPreparerTest {

    private val preparer = BookPreparer()

    // Genuinely distinct prose lines with NO digits so normalizeLine() maps each to a unique key.
    // normalizeLine replaces all digits with '#' so "Line 1..." and "Line 2..." become the same.
    private val distinctLines = listOf(
        "The fox jumped over the fence quickly.",
        "A cat sat on the warm mat nearby.",
        "Birds flew through the cloudy morning sky.",
        "The river flowed south toward the distant sea.",
        "Leaves fell gently in the cold autumn wind.",
        "Stars appeared one by one across the night.",
        "An old ship rocked slowly in the harbour."
    )

    private fun safeText(n: Int = 6): String = distinctLines.take(n).joinToString("\n")

    // 43-line prose passage with genuinely distinct sentences.
    // Safe through removeHeadersAndFooters because no normalized form repeats.
    private val longProse = listOf(
        "The morning sun rose slowly over the distant mountains.",
        "A gentle breeze stirred the tall oak trees along the path.",
        "Children laughed and chased butterflies through the meadow.",
        "The baker opened his shop and arranged fresh loaves in the window.",
        "Fog rolled in from the harbour swallowing the fishing boats.",
        "An astronomer peered through the telescope at the ringed planet.",
        "The pianist played a slow waltz as guests drifted onto the balcony.",
        "Rain began to fall softly on the cobblestones of the old square.",
        "A wolf howled somewhere deep in the forest beyond the ridge.",
        "The scholar turned the yellowed page and read aloud from the manuscript.",
        "Sparrows nested beneath the eaves of the ancient stone cathedral.",
        "The merchant unpacked silk and spices from the hold of the trading vessel.",
        "Lightning flickered over the lake and thunder rolled through the valley.",
        "A mother tucked her child into bed and sang a quiet lullaby.",
        "The soldier polished his boots and stared at the flickering campfire.",
        "Seagulls circled the lighthouse and cried out over the breaking waves.",
        "The chef tasted the broth and reached for the rosemary on the shelf.",
        "Evening settled across the rooftops and candles began to glow in windows.",
        "The sculptor chipped away at the marble and a face began to emerge.",
        "Wildflowers bloomed on the hillside where the old mill once stood.",
        "The letter arrived at dawn and changed everything for the quiet family.",
        "An eagle soared above the canyon walls scanning the desert below.",
        "The navigator checked the compass and adjusted the course northward.",
        "Frost crept across the windowpane during the long silent night.",
        "The gardener planted seeds in neat rows and watered them carefully.",
        "Smoke drifted from the chimney of the remote mountain cabin.",
        "The journalist filed her report and caught the last train home.",
        "A lantern swayed on the dock as fishermen returned with their catch.",
        "The carpenter measured twice and cut the beam with a single stroke.",
        "Bells rang from the church tower and echoed across the village green.",
        "The physician examined the patient and spoke quietly to the family.",
        "Snow began to fall and covered the market stalls in white.",
        "The teacher wrote a question on the board and waited for hands to rise.",
        "An old photograph slipped from the book and floated to the floor.",
        "The traveller rested under a chestnut tree and ate bread and cheese.",
        "Dawn broke over the ocean and the tide began to go out.",
        "The engineer reviewed the blueprints spread across the long oak table.",
        "Candles were lit along the aisle as the ceremony was about to begin.",
        "The shepherd counted the flock and found one lamb was missing.",
        "A kite rose high above the park on the last warm day of autumn.",
        "The diver pushed back her mask and gasped for air at the surface.",
        "Curtains billowed in the open window as the afternoon storm arrived.",
        "The poet crossed out three lines and rewrote them from memory."
    ).joinToString("\n")

    // ── prepareFromPlainText ─────────────────────────────────────────────────

    @Test
    fun plainText_producesPreparedBook() {
        val book = preparer.prepareFromPlainText("Test", safeText())
        assertEquals("Test", book.title)
        assertEquals(SourceType.PLAIN_TEXT, book.sourceType)
        assertTrue("chunks should be non-empty", book.chunks.isNotEmpty())
    }

    @Test
    fun plainText_idIsStableForSameInput() {
        val text = safeText()
        val a = preparer.prepareFromPlainText("T", text)
        val b = preparer.prepareFromPlainText("T", text)
        assertEquals(a.id, b.id)
    }

    @Test
    fun plainText_idDiffersForDifferentInput() {
        val a = preparer.prepareFromPlainText("T", safeText(6))
        val b = preparer.prepareFromPlainText("T", safeText(7))
        assertNotEquals(a.id, b.id)
    }

    @Test
    fun plainText_idIs16HexChars() {
        val book = preparer.prepareFromPlainText("T", safeText())
        assertTrue("id should be 16 hex chars", book.id.matches(Regex("[0-9a-f]{16}")))
    }

    @Test
    fun plainText_cleanedTextNotBlank() {
        val book = preparer.prepareFromPlainText("T", safeText())
        assertTrue(book.cleanedText.isNotBlank())
    }

    @Test
    fun plainText_rawTextNotBlank() {
        val book = preparer.prepareFromPlainText("T", safeText())
        assertTrue(book.rawText.isNotBlank())
    }

    // ── prepare from pages ───────────────────────────────────────────────────

    @Test
    fun prepare_singlePage_producesChunks() {
        // 4 lines: take(2) and takeLast(2) don't overlap -> nothing stripped
        val lines = listOf("Alpha text here.", "Beta text here.", "Gamma text here.", "Delta text here.")
        val pages = listOf(Page(0, lines))
        val book = preparer.prepare("Title", SourceType.PLAIN_TEXT, pages)
        assertTrue("chunks should be non-empty", book.chunks.isNotEmpty())
        assertEquals("Title", book.title)
    }

    @Test
    fun prepare_pagesWithChapterTitles_groupedCorrectly() {
        fun chapterLines(name: String) = listOf(
            "$name opening line alpha.", "$name second line beta.",
            "$name third line gamma.", "$name closing line delta."
        )
        val pages = listOf(
            Page(0, chapterLines("ChOne"), chapterTitle = "Ch1"),
            Page(1, chapterLines("ChTwo"), chapterTitle = "Ch2")
        )
        val book = preparer.prepare("Book", SourceType.EPUB, pages)
        assertTrue(book.chapters.containsAll(listOf("Ch1", "Ch2")))
        assertTrue(book.chunks.any { it.chapterTitle == "Ch1" })
        assertTrue(book.chunks.any { it.chapterTitle == "Ch2" })
    }

    @Test
    fun prepare_emptyPages_producesEmptyChunks() {
        val book = preparer.prepare("Empty", SourceType.PLAIN_TEXT, emptyList())
        assertTrue(book.chunks.isEmpty())
    }

    @Test
    fun prepare_headersStripped_beforeChunking() {
        // 4-line pages: "Running Header" and "Chapter Line" at take(2) on all 5 pages -> stripped.
        // Lines from longProse at positions 2 and 3 are unique per page -> survive.
        val proseSentences = longProse.split("\n")
        val pages = (0..4).map { i ->
            Page(
                i, listOf(
                    "Running Header",
                    "Chapter Line.",
                    proseSentences[i * 2],
                    proseSentences[i * 2 + 1]
                )
            )
        }
        val book = preparer.prepare("Book", SourceType.PDF, pages)
        val allText = book.chunks.joinToString(" ") { it.displayText }
        assertFalse("Running Header should be stripped", allText.contains("Running Header"))
        assertTrue("Unique body text should survive", book.chunks.isNotEmpty())
    }

    @Test
    fun prepare_chunkIndexesAreContiguous() {
        val book = preparer.prepareFromPlainText("Long", longProse)
        assertTrue("need chunks to verify indexes", book.chunks.isNotEmpty())
        book.chunks.forEachIndexed { i, chunk ->
            assertEquals(i, chunk.index)
        }
    }

    @Test
    fun prepare_sourceTypePreserved() {
        val pages = listOf(Page(0, listOf("Alpha here.", "Beta here.", "Gamma here.", "Delta here.")))
        val book = preparer.prepare("T", SourceType.EPUB, pages)
        assertEquals(SourceType.EPUB, book.sourceType)
    }

    // ── chunk sizing ─────────────────────────────────────────────────────────

    @Test
    fun smallMaxChunkLength_producesMoreChunks() {
        val big = BookPreparer(maxChunkLength = 5000).prepareFromPlainText("T", longProse)
        val small = BookPreparer(maxChunkLength = 150).prepareFromPlainText("T", longProse)
        assertTrue("smaller max should produce more chunks", small.chunks.size > big.chunks.size)
    }

    @Test
    fun notNull_bookId() {
        val book = preparer.prepareFromPlainText("T", safeText())
        assertNotNull(book.id)
    }
}
