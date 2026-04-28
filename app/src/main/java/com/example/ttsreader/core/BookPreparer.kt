package com.example.ttsreader.core

import java.security.MessageDigest

class BookPreparer(
    private val cleaner: TextCleaner = TextCleaner(),
    private val normalizer: SmartPunctuationNormalizer = SmartPunctuationNormalizer(),
    private val chunker: Chunker = Chunker(),
    private val maxChunkLength: Int = 2500
) {
    fun prepare(title: String, sourceType: SourceType, pages: List<Page>): PreparedBook {
        val withoutHeaders = cleaner.removeHeadersAndFooters(pages)
        val chapters = buildChapters(withoutHeaders)
        val joined = chapters.joinToString("\n\n") { (_, text) -> text }
        val cleaned = cleaner.cleanInline(joined)
        val cleanedChapters = chapters.map { (chapterTitle, text) ->
            chapterTitle to cleaner.cleanInline(text)
        }.filter { it.second.isNotBlank() }
        val chunks = chunker.chunk(cleanedChapters, normalizer, maxChunkLength)
        return PreparedBook(
            id = hash(cleaned),
            title = title,
            sourceType = sourceType,
            rawText = joined,
            cleanedText = cleaned,
            chapters = cleanedChapters.mapNotNull { it.first }.distinct(),
            chunks = chunks
        )
    }

    fun prepareFromPlainText(title: String, text: String): PreparedBook {
        val pages = text.lines().chunked(40).mapIndexed { index, lines ->
            Page(index = index, lines = lines)
        }
        return prepare(title, SourceType.PLAIN_TEXT, pages)
    }

    private fun buildChapters(pages: List<Page>): List<Pair<String?, String>> {
        if (pages.isEmpty()) return emptyList()

        val grouped = linkedMapOf<String?, MutableList<String>>()
        pages.forEach { page ->
            val key = page.chapterTitle
            grouped.getOrPut(key) { mutableListOf() }.add(page.lines.joinToString("\n"))
        }

        return grouped.map { (title, pageTexts) ->
            title to pageTexts.joinToString("\n\n").trim()
        }
    }

    private fun hash(text: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(text.toByteArray())
        return bytes.joinToString("") { "%02x".format(it) }.take(16)
    }
}
