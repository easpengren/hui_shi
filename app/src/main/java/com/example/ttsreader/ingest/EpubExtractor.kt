package com.example.ttsreader.ingest

import android.content.Context
import android.net.Uri
import androidx.core.text.HtmlCompat
import com.example.ttsreader.core.Page
import com.example.ttsreader.core.SourceType
import nl.siegmann.epublib.domain.TOCReference
import nl.siegmann.epublib.epub.EpubReader

class EpubExtractor {
    fun extract(context: Context, uri: Uri, displayName: String): ImportedDocument {
        val input = context.contentResolver.openInputStream(uri) ?: error("Could not open EPUB")
        input.use { stream ->
            val book = EpubReader().readEpub(stream)
            val tocTitles = mutableMapOf<String, String>()
            flattenToc(book.tableOfContents.tocReferences, tocTitles)

            val pages = book.spine.spineReferences.mapIndexedNotNull { index, spineReference ->
                val resource = spineReference.resource ?: return@mapIndexedNotNull null
                val href = resource.href.orEmpty()
                val title = tocTitles[href] ?: resource.title ?: href.substringAfterLast('/').substringBeforeLast('.')
                val html = runCatching { String(resource.data ?: ByteArray(0)) }.getOrDefault("")
                val text = HtmlCompat.fromHtml(html, HtmlCompat.FROM_HTML_MODE_LEGACY)
                    .toString()
                    .replace('\u00A0', ' ')
                    .lines()
                    .map { it.trim() }
                    .filter { it.isNotBlank() }
                if (text.isEmpty()) return@mapIndexedNotNull null

                Page(
                    index = index,
                    lines = text,
                    chapterTitle = title
                )
            }

            val preview = pages.joinToString("\n\n") { page ->
                listOfNotNull(page.chapterTitle, page.lines.joinToString("\n")).joinToString("\n")
            }

            return ImportedDocument(
                title = book.title ?: displayName.substringBeforeLast('.'),
                sourceType = SourceType.EPUB,
                pages = pages,
                previewText = preview
            )
        }
    }

    private fun flattenToc(nodes: List<TOCReference>, map: MutableMap<String, String>) {
        nodes.forEach { node ->
            node.resource?.href?.let { href ->
                map[href] = node.title
            }
            flattenToc(node.children, map)
        }
    }
}
