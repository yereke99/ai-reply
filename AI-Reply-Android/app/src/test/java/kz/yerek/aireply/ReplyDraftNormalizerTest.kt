package kz.yerek.aireply

import kz.yerek.aireply.ai.ReplyDraftNormalizer
import org.junit.Assert.assertEquals
import org.junit.Test

class ReplyDraftNormalizerTest {

    private val normalizer = ReplyDraftNormalizer()

    @Test
    fun `blank draft normalizes to empty`() {
        assertEquals("", normalizer.normalize("   \n\n  "))
    }

    @Test
    fun `repeated spaces collapse`() {
        assertEquals("Hello there", normalizer.normalize("Hello    there"))
    }

    @Test
    fun `space before punctuation is removed`() {
        assertEquals("Готово, спасибо!", normalizer.normalize("Готово , спасибо !"))
    }

    @Test
    fun `excess blank lines collapse to one`() {
        assertEquals("a\n\nb", normalizer.normalize("a\n\n\n\n\nb"))
    }

    @Test
    fun `a single newline survives`() {
        assertEquals("a\nb", normalizer.normalize("a\nb"))
    }

    /** The whole reason this is not one chain of replaces. */
    @Test
    fun `urls are copied through untouched`() {
        val draft = "See  https://example.com/a  b?x=1 , thanks"
        assertEquals("See https://example.com/a b?x=1, thanks", normalizer.normalize(draft))
    }

    @Test
    fun `a www url is preserved too`() {
        assertEquals("go to www.example.kz now", normalizer.normalize("go to  www.example.kz  now"))
    }
}
