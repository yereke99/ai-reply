package kz.yerek.aireply

import kz.yerek.aireply.core.lang.KeyboardLanguage
import kz.yerek.aireply.core.lang.KeyboardPlane
import kz.yerek.aireply.keyboard.AutoShift
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class KeyboardLayoutTest {

    @Test
    fun `english is standard 10-9-7 qwerty`() {
        val rows = KeyboardLanguage.ENGLISH.letterRows
        assertEquals(listOf(10, 9, 7), rows.map { it.size })
        assertEquals(10, KeyboardLanguage.ENGLISH.gridColumns)
    }

    /**
     * The product decision this protects: nothing is hidden behind a long press,
     * so every Cyrillic letter has to be on a key — `ё` included.
     */
    @Test
    fun `russian shows every cyrillic letter including yo`() {
        val letters = KeyboardLanguage.RUSSIAN.letterRows.flatten()
        assertEquals(33, letters.size)
        assertTrue(letters.contains("ё"))
        assertTrue(letters.contains("ъ"))
        assertEquals(letters.distinct().size, letters.size)
    }

    @Test
    fun `russian keeps the third row short so shift and delete stay wide`() {
        assertEquals(listOf(12, 12, 9), KeyboardLanguage.RUSSIAN.letterRows.map { it.size })
    }

    @Test
    fun `kazakh adds all nine specific letters on their own row`() {
        val rows = KeyboardLanguage.KAZAKH.letterRows
        assertEquals(4, rows.size)
        assertEquals(listOf("ә", "ғ", "қ", "ң", "ө", "ұ", "ү", "һ", "і"), rows.first())
        assertTrue(KeyboardLanguage.KAZAKH.rowFillsWidth(0))
        assertFalse(KeyboardLanguage.KAZAKH.rowFillsWidth(1))
    }

    @Test
    fun `kazakh still carries the full cyrillic set underneath`() {
        val letters = KeyboardLanguage.KAZAKH.letterRows.drop(1).flatten()
        assertEquals(33, letters.size)
    }

    @Test
    fun `layout cycling visits all three and returns`() {
        var language = KeyboardLanguage.ENGLISH
        val seen = mutableListOf(language)
        repeat(3) {
            language = language.next
            seen.add(language)
        }
        assertEquals(
            listOf(
                KeyboardLanguage.ENGLISH,
                KeyboardLanguage.RUSSIAN,
                KeyboardLanguage.KAZAKH,
                KeyboardLanguage.ENGLISH
            ),
            seen
        )
    }

    @Test
    fun `the tenge sign is on the number plane`() {
        assertTrue(KeyboardPlane.NUMBERS.rows.flatten().contains("₸"))
    }

    // -------------------------------------------------------------- auto shift

    @Test
    fun `empty context is a sentence start`() {
        assertTrue(AutoShift.isAtSentenceStart(null))
        assertTrue(AutoShift.isAtSentenceStart(""))
    }

    @Test
    fun `mid-word is not a sentence start`() {
        assertFalse(AutoShift.isAtSentenceStart("hello"))
        assertFalse(AutoShift.isAtSentenceStart("hello "))
    }

    @Test
    fun `after terminal punctuation and a space is a sentence start`() {
        assertTrue(AutoShift.isAtSentenceStart("Done. "))
        assertTrue(AutoShift.isAtSentenceStart("Really? "))
        assertTrue(AutoShift.isAtSentenceStart("Wow!  "))
    }

    @Test
    fun `punctuation without a following space is not yet a sentence start`() {
        assertFalse(AutoShift.isAtSentenceStart("Done."))
    }

    @Test
    fun `a newline is a sentence start`() {
        assertTrue(AutoShift.isAtSentenceStart("first line\n"))
    }

    @Test
    fun `a comma is not a sentence end`() {
        assertFalse(AutoShift.isAtSentenceStart("Hello, "))
    }
}
