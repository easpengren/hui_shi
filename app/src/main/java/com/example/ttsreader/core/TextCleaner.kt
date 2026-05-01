package com.example.ttsreader.core

class TextCleaner {
    private val superscriptRegex = Regex("[⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾]+")
    // Matches lines that are overwhelmingly non-word characters (PDF extraction noise)
    private val noisyLineRegex = Regex("^[^a-zA-Z]{0,6}$")
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
        val lines = text.split("\n")
        val filtered = lines.filter { line -> !isNoiseLine(line) }
        return filtered.joinToString("\n")
            .replace(superscriptRegex, "")
            .replace(inlineFootnoteRegex, "")
            .replace(footnoteLineRegex, "")
            .replace(Regex("\\s+"), " ")
            .trim()
    }

    /**
     * Returns true if the line is extraction noise: very short with no real words,
     * or has a word-character ratio below 40% (e.g. "percent rn at BW percent five").
     */
    private fun isNoiseLine(line: String): Boolean {
        val trimmed = line.trim()
        if (trimmed.isEmpty()) return false
        // Very short lines with no letters at all
        if (noisyLineRegex.matches(trimmed)) return true
        // Lines where fewer than 40% of characters are letters or spaces
        val wordChars = trimmed.count { it.isLetter() || it == ' ' }
        val ratio = wordChars.toFloat() / trimmed.length
        if (ratio < 0.40f && trimmed.length > 8) return true
        // Lines that are mostly isolated single-letter tokens with symbols between them
        val tokens = trimmed.split(Regex("\\s+"))
        if (tokens.size >= 4) {
            val shortNoisyTokens = tokens.count { tok ->
                tok.length <= 3 && tok.any { !it.isLetter() }
            }
            if (shortNoisyTokens.toFloat() / tokens.size > 0.60f) return true
        }
        return false
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
