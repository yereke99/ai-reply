package kz.yerek.aireply.core.lang

/**
 * The three layouts this keyboard ships. The selected value drives BOTH the
 * character layout and the key-cap captions, so the two can never drift apart.
 *
 * Layout tables are ported verbatim from the iOS `KeyboardLanguage`, including
 * the two deliberate decisions it documents:
 *
 *  * `ё` sits at the end of the Cyrillic second row instead of behind a long
 *    press on `е`, so every Cyrillic letter is visible;
 *  * the Cyrillic third row keeps only 9 letters so shift and delete stay wide
 *    rather than shrinking to letter width.
 */
enum class KeyboardLanguage(val code: String) {
    ENGLISH("en"),
    RUSSIAN("ru"),
    KAZAKH("kk");

    val next: KeyboardLanguage
        get() = when (this) {
            ENGLISH -> RUSSIAN
            RUSSIAN -> KAZAKH
            KAZAKH -> ENGLISH
        }

    /**
     * Number of slots the widest row of this layout uses. Every row is sized
     * against this so the rows line up on a single grid.
     */
    val gridColumns: Int
        get() = when (this) {
            ENGLISH -> 10
            RUSSIAN, KAZAKH -> 12
        }

    /**
     * Rows of letters, top to bottom. The last row is rendered with shift in
     * front of it and delete after it.
     */
    val letterRows: List<List<String>>
        get() = when (this) {
            ENGLISH -> ENGLISH_ROWS
            RUSSIAN -> CYRILLIC_ROWS
            KAZAKH -> listOf(KAZAKH_ROW) + CYRILLIC_ROWS
        }

    /**
     * Rows stretched edge to edge rather than centred on the grid. The Kazakh
     * letter row has only nine keys; spreading it across the full width gives
     * comfortably wide keys instead of a narrow centred block.
     */
    fun rowFillsWidth(index: Int): Boolean = this == KAZAKH && index == 0

    companion object {
        fun fromCode(code: String?): KeyboardLanguage? =
            entries.firstOrNull { it.code == code }

        private val ENGLISH_ROWS = listOf(
            listOf("q", "w", "e", "r", "t", "y", "u", "i", "o", "p"),
            listOf("a", "s", "d", "f", "g", "h", "j", "k", "l"),
            listOf("z", "x", "c", "v", "b", "n", "m")
        )

        private val CYRILLIC_ROWS = listOf(
            listOf("й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х", "ъ"),
            listOf("ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э", "ё"),
            listOf("я", "ч", "с", "м", "и", "т", "ь", "б", "ю")
        )

        private val KAZAKH_ROW = listOf("ә", "ғ", "қ", "ң", "ө", "ұ", "ү", "һ", "і")
    }
}

/** The non-letter planes, shared by every layout. */
enum class KeyboardPlane {
    LETTERS,
    NUMBERS,
    SYMBOLS;

    val rows: List<List<String>>
        get() = when (this) {
            LETTERS -> emptyList()
            NUMBERS -> listOf(
                listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "0"),
                listOf("-", "/", ":", ";", "(", ")", "₸", "&", "@", "\""),
                listOf(".", ",", "?", "!", "'")
            )
            SYMBOLS -> listOf(
                listOf("[", "]", "{", "}", "#", "%", "^", "*", "+", "="),
                listOf("_", "\\", "|", "~", "<", ">", "$", "€", "£", "¥"),
                listOf(".", ",", "?", "!", "'")
            )
        }

    val gridColumns: Int get() = 10
}
