package com.example.ttsreader.core

enum class SourceType {
    PLAIN_TEXT,
    PDF,
    EPUB
}

data class PositionedLine(
    val text: String,
    val x: Float,
    val y: Float,
    val width: Float,
    val height: Float
)

data class Page(
    val index: Int,
    val lines: List<String>,
    val positionedLines: List<PositionedLine> = emptyList(),
    val pageHeight: Float? = null,
    val chapterTitle: String? = null
)

data class WordRange(
    val startOffset: Int,
    val endOffset: Int
)

data class Chunk(
    val index: Int,
    val displayText: String,
    val ttsText: String,
    val startOffset: Int,
    val endOffset: Int,
    val chapterTitle: String? = null,
    val wordRanges: List<WordRange> = emptyList(),
    val estimatedDurationMs: Long = 0L
)

data class PreparedBook(
    val id: String,
    val title: String,
    val sourceType: SourceType,
    val rawText: String,
    val cleanedText: String,
    val chapters: List<String>,
    val chunks: List<Chunk>
)
