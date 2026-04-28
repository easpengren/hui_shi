package com.example.ttsreader.core

class Chunker {
    fun chunk(chapters: List<Pair<String?, String>>, normalizer: SmartPunctuationNormalizer, maxLen: Int = 2500): List<Chunk> {
        val chunks = mutableListOf<Chunk>()
        var globalOffset = 0

        chapters.forEach { (chapterTitle, chapterText) ->
            if (chapterText.isBlank()) return@forEach

            var cursor = 0
            while (cursor < chapterText.length) {
                val targetEnd = (cursor + maxLen).coerceAtMost(chapterText.length)
                val splitEnd = chooseBoundary(chapterText, cursor, targetEnd)
                val displayText = chapterText.substring(cursor, splitEnd).trim()
                if (displayText.isNotEmpty()) {
                    val start = globalOffset + cursor
                    val end = start + displayText.length
                    chunks += Chunk(
                        index = chunks.size,
                        displayText = displayText,
                        ttsText = normalizer.normalize(displayText),
                        startOffset = start,
                        endOffset = end,
                        chapterTitle = chapterTitle,
                        wordRanges = buildWordRanges(displayText, start),
                        estimatedDurationMs = estimateDurationMs(displayText)
                    )
                }
                cursor = splitEnd
            }

            globalOffset += chapterText.length + 2
        }

        return chunks
    }

    private fun chooseBoundary(text: String, start: Int, end: Int): Int {
        if (end == text.length) return end
        val sentenceBoundary = text.lastIndexOfAny(charArrayOf('.', '!', '?', '\n'), end, ignoreCase = false)
        if (sentenceBoundary in (start + 200) until end) return sentenceBoundary + 1

        val wordBoundary = text.lastIndexOf(' ', end)
        if (wordBoundary in (start + 200) until end) return wordBoundary + 1

        return end
    }

    private fun buildWordRanges(text: String, globalStart: Int): List<WordRange> {
        val regex = Regex("\\S+")
        return regex.findAll(text).map { match ->
            WordRange(
                startOffset = globalStart + match.range.first,
                endOffset = globalStart + match.range.last + 1
            )
        }.toList()
    }

    private fun estimateDurationMs(text: String): Long {
        val wordCount = Regex("\\S+").findAll(text).count().coerceAtLeast(1)
        val wordsPerMinute = 165.0
        return ((wordCount / wordsPerMinute) * 60_000).toLong().coerceAtLeast(1200L)
    }
}
