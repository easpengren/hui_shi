package com.example.ttsreader.core

class TextCleaner {
    private val superscriptRegex = Regex("[⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾]+")
    private val inlineFootnoteRegex = Regex("(?<=\\w)(\\[\\d+\\]|\\(\\d+\\)|\\*+|†+)")
    private val footnoteLineRegex = Regex("^\\s*\\d+\\s+.+$", RegexOption.MULTILINE)

    fun removeHeadersAndFooters(pages: List<Page>): List<Page> {
        if (pages.isEmpty()) return pages

        val repeatedLines = repeatedRegionLines(pages)

        return pages.map { page ->
            if (page.positionedLines.isEmpty()) {
                val filteredLines = page.lines.filter { normalizeLine(it) !in repeatedLines }
                page.copy(lines = filteredLines)
            } else {
                val filteredPositioned = page.positionedLines.filter { line ->
                    normalizeLine(line.text) !in repeatedLines
                }
                page.copy(
                    lines = filteredPositioned.map { it.text },
                    positionedLines = filteredPositioned
                )
            }
        }
    }

    fun cleanInline(text: String): String {
        return text
            .replace(superscriptRegex, "")
            .replace(inlineFootnoteRegex, "")
            .replace(footnoteLineRegex, "")
            .replace(Regex("\\s+"), " ")
            .trim()
    }

    private fun normalizeLine(line: String): String {
        return line.trim().lowercase().replace(Regex("\\d+"), "#")
    }

    private fun repeatedRegionLines(pages: List<Page>): Set<String> {
        val normalizedFrequency = mutableMapOf<String, Int>()
        pages.forEach { page ->
            if (page.positionedLines.isNotEmpty() && page.pageHeight != null && page.pageHeight > 0f) {
                val headerCutoff = page.pageHeight * 0.14f
                val footerCutoff = page.pageHeight * 0.86f
                page.positionedLines
                    .filter { line ->
                        val normalized = normalizeLine(line.text)
                        normalized.length in 4..120 && (line.y <= headerCutoff || line.y >= footerCutoff)
                    }
                    .forEach { line ->
                        val normalized = normalizeLine(line.text)
                        if (normalized.isNotBlank()) {
                            normalizedFrequency[normalized] = (normalizedFrequency[normalized] ?: 0) + 1
                        }
                    }
            } else {
                val candidateLines = buildList {
                    addAll(page.lines.take(2))
                    addAll(page.lines.takeLast(2))
                }
                candidateLines.forEach { line ->
                    val normalized = normalizeLine(line)
                    if (normalized.length in 4..120) {
                        normalizedFrequency[normalized] = (normalizedFrequency[normalized] ?: 0) + 1
                    }
                }
            }
        }

        val threshold = (pages.size * 0.3f).toInt().coerceAtLeast(2)
        return normalizedFrequency.filterValues { it >= threshold }.keys
    }
}
