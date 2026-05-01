package com.example.ttsreader.tts

private val codeFenceRegex = Regex("```[\\s\\S]*?```")
private val markdownLinkRegex = Regex("\\[([^\\]]+)]\\(([^)]+)\\)")
private val headingRegex = Regex("(?m)^\\s{0,3}#{1,6}\\s*")
private val blockQuoteRegex = Regex("(?m)^\\s*>+\\s?")
private val xmlTagRegex = Regex("<[^>]+>")
private val markdownFormattingRegex = Regex("[`*_~]")
private val whitespaceRegex = Regex("\\s+")

internal fun sanitizeTtsText(input: String): String {
    return input
        .replace(codeFenceRegex, " ")
        .replace(markdownLinkRegex, "$1")
        .replace(headingRegex, "")
        .replace(blockQuoteRegex, "")
        .replace(xmlTagRegex, " ")
        .replace(markdownFormattingRegex, " ")
        .replace(whitespaceRegex, " ")
        .trim()
}