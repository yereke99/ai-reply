package kz.yerek.aireply.keyboard.input

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * A text field the KEYBOARD edits, rather than one the system edits.
 *
 * WHY THIS EXISTS. An input method cannot host a normally focused text field:
 * there is no second keyboard to type into it, and asking the system for focus
 * from inside an IME window is the sort of thing that works on one OEM's build
 * and not the next. So the instruction box and the reply draft keep their text
 * here and are edited by the same key presses that would otherwise go to the
 * host app — the key grid simply routes elsewhere.
 *
 * The iOS project arrives at the same design from the other direction: it asks
 * for first responder, and then implements a complete storage-based editing path
 * anyway "so editing behaves identically whether or not the system granted it".
 * On Android that fallback is the only path, which removes the whole class of
 * bugs where the two disagree.
 */
class KeyboardTextFieldState(initial: String = "") {

    var text: String by mutableStateOf(initial)
        private set

    /** Caret position, as a UTF-16 offset into [text]. */
    var cursor: Int by mutableStateOf(initial.length)
        private set

    val isBlank: Boolean get() = text.isBlank()

    fun set(value: String, moveCursorToEnd: Boolean = true) {
        text = value
        cursor = if (moveCursorToEnd) value.length else cursor.coerceIn(0, value.length)
    }

    fun clear() {
        text = ""
        cursor = 0
    }

    fun moveCursor(to: Int) {
        cursor = to.coerceIn(0, text.length)
    }

    fun insert(value: String) {
        val at = cursor.coerceIn(0, text.length)
        text = text.substring(0, at) + value + text.substring(at)
        cursor = at + value.length
    }

    /**
     * Composed-character aware, so an emoji or a combining mark deletes whole
     * rather than leaving a broken half behind.
     */
    fun deleteBackward() {
        val at = cursor.coerceIn(0, text.length)
        if (at == 0) return
        val start = if (at >= 2 && Character.isSurrogatePair(text[at - 2], text[at - 1])) at - 2 else at - 1
        text = text.substring(0, start) + text.substring(at)
        cursor = start
    }

    fun textBeforeCursor(): String = text.substring(0, cursor.coerceIn(0, text.length))
}
