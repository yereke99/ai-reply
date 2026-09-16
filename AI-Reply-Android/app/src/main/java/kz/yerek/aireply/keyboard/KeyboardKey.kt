package kz.yerek.aireply.keyboard

import kz.yerek.aireply.core.lang.KeyboardPlane

/** Everything a key can be. */
sealed interface KeyboardKey {

    data class Character(val value: String) : KeyboardKey
    data object Shift : KeyboardKey
    data object Backspace : KeyboardKey
    data class Plane(val target: KeyboardPlane) : KeyboardKey
    /** Switches to the next system input method. */
    data object Globe : KeyboardKey
    /** Cycles AI Reply's own three layouts. */
    data object Layout : KeyboardKey
    data object Space : KeyboardKey
    data object Return : KeyboardKey

    val isCharacter: Boolean get() = this is Character

    /**
     * Keys that fire on press, matching the system keyboard. Keys that rebuild
     * the whole grid fire on release instead, so the key is never torn out from
     * under the finger.
     */
    val firesOnPress: Boolean
        get() = when (this) {
            is Character, Backspace, Space, Return, Shift -> true
            is Plane, Globe, Layout -> false
        }
}

/** Which of the four visual treatments a key wears. */
enum class KeyVisualStyle { LETTER, SPECIAL, ENGAGED, PROMINENT }

val KeyboardPlane.title: String
    get() = when (this) {
        KeyboardPlane.LETTERS -> "ABC"
        KeyboardPlane.NUMBERS -> "123"
        KeyboardPlane.SYMBOLS -> "#+="
    }
