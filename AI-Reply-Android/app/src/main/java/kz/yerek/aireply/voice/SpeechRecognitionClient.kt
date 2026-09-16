package kz.yerek.aireply.voice

import kotlinx.coroutines.flow.StateFlow

/**
 * What a source of dictated text has to be able to do.
 *
 * WHY AN INTERFACE FOR ONE IMPLEMENTATION. The brief asks for the voice
 * architecture to be "abstracted enough that later we can switch to
 * server-side/OpenAI transcription without rewriting the keyboard", and this is
 * the whole of that abstraction: five methods and a state flow. On-device
 * recognition is fast, free and private, but its Kazakh coverage is unreliable,
 * so a server-side transcriber is a likely second implementation rather than a
 * hypothetical one. Nothing in the keyboard knows which one it is holding.
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
