package com.example.ttsreader.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SmartPunctuationNormalizerTest {

    private val normalizer = SmartPunctuationNormalizer()

    @Test
    fun normalize_addsPauseAfterPeriod() {
        val result = normalizer.normalize("Hello.")
        assertTrue(result.contains(".<break time=\"300ms\"/>"))
    }

    @Test
    fun normalize_addsPauseAfterComma() {
        val result = normalizer.normalize("One, two")
        assertTrue(result.contains(",<break time=\"150ms\"/>"))
    }

    @Test
    fun normalize_decimalNumberConvertedToSpokenForm() {
        val result = normalizer.normalize("version 3.14 is ready")
        assertTrue("decimal should become 'point'", result.contains("3 point 14"))
    }

    @Test
    fun normalize_urlDotsReplacedWithSpokenForm() {
        val result = normalizer.normalize("visit https://example.com for info")
        assertTrue(result.contains("example dot com"))
        assertFalse("URL dots should not trigger period pauses", result.contains("example.<break"))
    }

    @Test
    fun normalize_abbreviationDotNotTreatedAsSentenceEnd() {
        val result = normalizer.normalize("Dr. Smith arrived")
        // The abbreviation dot should be stripped, not turned into a pause
        assertFalse(result.startsWith("Dr.<break"))
    }

    @Test
    fun normalize_mrAbbreviation() {
        val result = normalizer.normalize("Mr. Jones")
        assertFalse(result.contains("Mr.<break"))
    }

    @Test
    fun normalize_emptyString_returnsEmpty() {
        assertEquals("", normalizer.normalize(""))
    }

    @Test
    fun normalize_noSpecialChars_returnsSameText() {
        val input = "Hello world"
        val result = normalizer.normalize(input)
        assertEquals(input, result)
    }

    @Test
    fun normalize_multipleDecimals() {
        val result = normalizer.normalize("1.5 and 2.75 are decimals")
        assertTrue(result.contains("1 point 5"))
        assertTrue(result.contains("2 point 75"))
    }
}
