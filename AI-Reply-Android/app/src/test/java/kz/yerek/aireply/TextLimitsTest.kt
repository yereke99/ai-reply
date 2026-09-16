package kz.yerek.aireply

import kz.yerek.aireply.core.text.clampToCodePoints
import kz.yerek.aireply.core.text.codePointLength
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Limits are counted the way iOS and the backend count them, so the same text is
 * accepted or refused identically on both platforms.
 */
class TextLimitsTest {

    @Test
    fun `ascii counts as expected`() {
        assertEquals(5, "hello".codePointLength())
    }

    @Test
    fun `cyrillic and kazakh count by character`() {
        assertEquals(6, "Привет".codePointLength())
        assertEquals(7, "Сәлем!!".codePointLength())
    }

    @Test
    fun `an emoji is one code point, not two`() {
        assertEquals(1, "🙂".codePointLength())
        assertEquals(2, "🙂".length)
    }

    @Test
    fun `clamping never splits a surrogate pair`() {
        val text = "ab🙂cd"
        val clamped = text.clampToCodePoints(3)
        assertEquals("ab🙂", clamped)
        assertEquals(3, clamped.codePointLength())
        // A naive substring(0, 3) would leave a lone high surrogate here.
        assertTrue(clamped.none { it.isHighSurrogate() && clamped.indexOf(it) == clamped.lastIndex })
    }

    @Test
    fun `clamping below the limit returns the original instance content`() {
        assertEquals("short", "short".clampToCodePoints(50))
    }

    @Test
    fun `clamping to zero gives an empty string`() {
        assertEquals("", "anything".clampToCodePoints(0))
    }
}
