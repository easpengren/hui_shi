package com.example.ttsreader.ingest

import android.content.Context
import android.net.Uri
import com.example.ttsreader.core.Page
import com.example.ttsreader.core.PositionedLine
import com.example.ttsreader.core.SourceType
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.text.PDFTextStripper
import com.tom_roush.pdfbox.text.TextPosition
import kotlin.math.abs

class PdfExtractor(context: Context) {
    init {
        PDFBoxResourceLoader.init(context.applicationContext)
    }

    fun extract(context: Context, uri: Uri, displayName: String): ImportedDocument {
        val input = context.contentResolver.openInputStream(uri) ?: error("Could not open PDF")
        input.use { stream ->
            PDDocument.load(stream).use { document ->
                val stripper = PositionedPdfStripper()
                stripper.getText(document)
                val pages = stripper.buildPages()
                return ImportedDocument(
                    title = displayName.substringBeforeLast('.'),
                    sourceType = SourceType.PDF,
                    pages = pages,
                    previewText = pages.joinToString("\n\n") { it.lines.joinToString("\n") }
                )
            }
        }
    }

    private class PositionedPdfStripper : PDFTextStripper() {
        private val pageRuns = mutableMapOf<Int, MutableList<PositionedLine>>()
        private val pageHeights = mutableMapOf<Int, Float>()

        init {
            sortByPosition = true
        }

        override fun startPage(page: PDPage?) {
            super.startPage(page)
            val pageIndex = currentPageNo - 1
            pageHeights[pageIndex] = page?.mediaBox?.height ?: 0f
            pageRuns.getOrPut(pageIndex) { mutableListOf() }
        }

        override fun writeString(text: String?, textPositions: MutableList<TextPosition>?) {
            if (text.isNullOrBlank() || textPositions.isNullOrEmpty()) return
            val cleaned = text.trim()
            if (cleaned.isBlank()) return

            val pageIndex = currentPageNo - 1
            val x = textPositions.minOf { it.xDirAdj }
            val y = textPositions.map { it.yDirAdj }.average().toFloat()
            val width = textPositions.sumOf { it.widthDirAdj.toDouble() }.toFloat()
            val height = textPositions.maxOf { it.heightDir }
            pageRuns.getOrPut(pageIndex) { mutableListOf() }.add(
                PositionedLine(
                    text = cleaned,
                    x = x,
                    y = y,
                    width = width,
                    height = height
                )
            )
        }

        fun buildPages(): List<Page> {
            return pageRuns.keys.sorted().map { pageIndex ->
                val merged = mergeRuns(pageRuns[pageIndex].orEmpty())
                Page(
                    index = pageIndex,
                    lines = merged.map { it.text },
                    positionedLines = merged,
                    pageHeight = pageHeights[pageIndex]
                )
            }
        }

        private fun mergeRuns(runs: List<PositionedLine>): List<PositionedLine> {
            if (runs.isEmpty()) return emptyList()
            val sorted = runs.sortedWith(compareBy<PositionedLine> { it.y }.thenBy { it.x })
            val groups = mutableListOf<MutableList<PositionedLine>>()
            sorted.forEach { run ->
                val bucket = groups.lastOrNull()
                if (bucket == null || abs(bucket.first().y - run.y) > 5.5f) {
                    groups += mutableListOf(run)
                } else {
                    bucket += run
                }
            }

            return groups.map { group ->
                val ordered = group.sortedBy { it.x }
                val mergedText = buildString {
                    ordered.forEachIndexed { index, line ->
                        if (index > 0) {
                            val previous = ordered[index - 1]
                            val gap = line.x - (previous.x + previous.width)
                            append(if (gap > 14f) "  " else " ")
                        }
                        append(line.text)
                    }
                }.replace(Regex("\\s+"), " ").trim()
                PositionedLine(
                    text = mergedText,
                    x = ordered.minOf { it.x },
                    y = ordered.map { it.y }.average().toFloat(),
                    width = ordered.sumOf { it.width.toDouble() }.toFloat(),
                    height = ordered.maxOf { it.height }
                )
            }
        }
    }
}
