package kz.yerek.aireply.voice

/** Why a recognition attempt ended without usable text. */
enum class VoiceFailure {
    /** The user spoke nothing, or nothing the recogniser could make out. */
    NO_SPEECH,

    /** The recogniser needed the network and did not have it. */
    NETWORK,

    /**
     * No recognition model for this language on this device. Kazakh coverage is
     * genuinely patchy, and saying so plainly is better than letting the user
     * hold a button that can never produce text.
     */
    LANGUAGE_UNAVAILABLE,

    /** No recognition service at all — some builds ship without one. */
    UNAVAILABLE,

    /** Anything else. */
    GENERIC
}

/**
 * Everything the microphone can be doing, as a value rather than a rendered
 * sentence.
 *
 * Keeping it a value is what lets the app change language and have the CURRENT
 * status re-render in the new one, instead of leaving a stale sentence on
 * screen in the previous language. The iOS `VoiceStatus` is the same idea.
 */
sealed interface VoiceState {

    data object Idle : VoiceState

    /** Permission has not been granted yet; tapping asks for it. */
    data object PermissionRequired : VoiceState

    /** Permission was refused for good; only Settings can undo it. */
    data object PermissionDenied : VoiceState

    /** Microphone opening. Brief, but visible enough to need its own state. */
    data object Starting : VoiceState

    /** Capturing. [partial] is the running transcript, which may be empty. */
    data class Listening(val partial: String = "") : VoiceState

    /** Audio finished, final text not yet delivered. */
    data object Processing : VoiceState

    /** Final text. The consumer takes it and returns the client to [Idle]. */
    data class Done(val text: String) : VoiceState

    data class Failed(val reason: VoiceFailure) : VoiceState

    val isActive: Boolean
        get() = this is Starting || this is Listening || this is Processing
}
