package kz.yerek.aireply.voice

import kotlinx.coroutines.flow.StateFlow

/**
 * What a source of dictated text has to be able to do.
 *
 * On-device recognition is fast and private. Keeping it behind this interface
 * lets the keyboard remain independent from the recognition implementation.
 *
 * Every implementation must be safe to call from the main thread and must
 * release its microphone in [release].
 */
interface SpeechRecognitionClient {

    val state: StateFlow<VoiceState>

    /** @param languageTag BCP-47, e.g. `kk-KZ`. */
    fun start(languageTag: String)

    /** Stop capturing and deliver whatever was heard. */
    fun stop()

    /** Stop capturing and discard. */
    fun cancel()

    /** Return to [VoiceState.Idle] after a terminal state has been consumed. */
    fun reset()

    /** Release the microphone and every listener. */
    fun release()

    companion object {
        /** Matches the iOS dictation cap. */
        const val MAX_DURATION_MS = 60_000L
    }
}
