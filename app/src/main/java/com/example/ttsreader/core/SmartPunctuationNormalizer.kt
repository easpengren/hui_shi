package com.example.ttsreader.core

class SmartPunctuationNormalizer {
    private val urlRegex = Regex("(https?://\\S+|www\\.\\S+)")
    private val decimalRegex = Regex("(\\d+)\\.(\\d+)")
    private val abbreviationRegex = Regex("\\b(Mr|Mrs|Dr|St|Mt|etc|i\\.e|e\\.g|vs)\\.")

    fun normalize(text: String): String {
        var updated = text

        updated = updated.replace(urlRegex) { match ->
            match.value.replace(".", " dot ")
        }

        updated = updated.replace(decimalRegex, "$1 point $2")

        updated = updated.replace(abbreviationRegex) { match ->
            match.value.dropLast(1)
        }

        return updated
    }
}
