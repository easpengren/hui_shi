package com.example.ttsreader.tts

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class TtsTextSanitizerTest {

    @Test
    fun sanitizeTtsText_stripsMarkdownAndTags() {
        val input = "# Title\n> `quoted` [link](https://example.com) <break time=\"300ms\"/>"
        val result = sanitizeTtsText(input)

        assertEquals("Title quoted link", result)
        assertFalse(result.contains("`"))
        assertFalse(result.contains("<break"))
        assertFalse(result.contains(">"))
    }
}