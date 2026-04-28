package com.example.ttsreader.ingest

import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class DocumentExtractorSmokeTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val testContext = instrumentation.context

    @Test
    fun pdfExtractor_readsPages_andCleanerCanDropRepeatedHeaderFooter() {
        val source = copyAssetToCache("fixtures/sample-reader.pdf")
        val document = PdfExtractor(context).extract(context, Uri.fromFile(source), "sample-reader.pdf")

        assertEquals(2, document.pages.size)
        assertTrue(document.previewText.contains("Chapter One"))
        assertTrue(document.previewText.contains("Second page body text"))

        val cleanedPages = com.example.ttsreader.core.TextCleaner().removeHeadersAndFooters(document.pages)
        val cleanedText = cleanedPages.joinToString("\n") { it.lines.joinToString("\n") }
        assertFalse(cleanedText.contains("Story Header"))
        assertFalse(cleanedText.contains("Page 1"))
        assertTrue(cleanedText.contains("First page body text"))
    }

    @Test
    fun epubExtractor_readsChapters_inSpineOrder() {
        val source = copyAssetToCache("fixtures/sample-book.epub")
        val document = EpubExtractor().extract(context, Uri.fromFile(source), "sample-book.epub")

        assertEquals(2, document.pages.size)
        assertEquals("Chapter One", document.pages.first().chapterTitle)
        assertEquals("Chapter Two", document.pages.last().chapterTitle)
        assertTrue(document.previewText.contains("EPUB chapter one text"))
        assertTrue(document.previewText.contains("EPUB chapter two text"))
    }

    private fun copyAssetToCache(path: String): File {
        val file = File(context.cacheDir, path.substringAfterLast('/'))
        testContext.assets.open(path).use { input ->
            file.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        return file
    }
}
