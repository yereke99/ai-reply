package kz.yerek.aireply.voice

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kz.yerek.aireply.platform.ReplyLog

/**
 * Dictation through Android's own recogniser.
 *
 * ON-DEVICE FIRST. From API 33 the platform exposes an on-device recogniser
 * directly, which is faster, works offline and never sends audio anywhere. It
 * is tried first and the networked one is the fallback, so a user dictating an
 * instruction about a client's order is not shipping that audio to a server
 * whenever the device could have handled it locally.
 *
 * LIFECYCLE. [SpeechRecognizer] must be created, used and destroyed on the main
 * thread, and it holds the microphone until it is destroyed. Inside an input
 * method — which can stay alive for hours — leaking one would mean holding the
 * mic open across every app the user visits. [release] is therefore called from
 * `onFinishInputView`, not only from `onDestroy`.
 */
class AndroidSpeechRecognitionClient(context: Context) : SpeechRecognitionClient {

    private val appContext = context.applicationContext
    private val handler = Handler(Looper.getMainLooper())

    private val _state = MutableStateFlow<VoiceState>(VoiceState.Idle)
    override val state: StateFlow<VoiceState> = _state.asStateFlow()

    private var recognizer: SpeechRecognizer? = null
    private var partial: String = ""
    private var isStopping = false

    private val timeout = Runnable {
        ReplyLog.event { "voice: hit the 60s cap" }
        stop()
    }

    override fun start(languageTag: String) {
        if (_state.value.isActive) return

        if (!MicPermission.isGranted(appContext)) {
            _state.value = VoiceState.PermissionRequired
            return
        }

        val client = createRecognizer()
        if (client == null) {
            _state.value = VoiceState.Failed(VoiceFailure.UNAVAILABLE)
            return
        }

        partial = ""
        isStopping = false
        _state.value = VoiceState.Starting

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, languageTag)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, languageTag)
            putExtra(RecognizerIntent.EXTRA_ONLY_RETURN_LANGUAGE_PREFERENCE, true)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            // Never let the recogniser announce itself over the user's music or
            // over the conversation they are replying to.
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, appContext.packageName)
        }

        runCatching { client.startListening(intent) }
            .onFailure {
                ReplyLog.warn(it) { "voice: startListening refused" }
                _state.value = VoiceState.Failed(VoiceFailure.UNAVAILABLE)
                return
            }

        handler.postDelayed(timeout, SpeechRecognitionClient.MAX_DURATION_MS)
    }

    override fun stop() {
        handler.removeCallbacks(timeout)
        val client = recognizer ?: return
        if (!_state.value.isActive) return
        isStopping = true
        _state.value = VoiceState.Processing
        runCatching { client.stopListening() }
    }

    override fun cancel() {
        handler.removeCallbacks(timeout)
        isStopping = false
        partial = ""
        runCatching { recognizer?.cancel() }
        _state.value = VoiceState.Idle
    }

    override fun reset() {
        if (_state.value is VoiceState.Done || _state.value is VoiceState.Failed) {
            _state.value = VoiceState.Idle
        }
    }

    override fun release() {
        handler.removeCallbacks(timeout)
        runCatching {
            recognizer?.cancel()
            recognizer?.destroy()
        }
        recognizer = null
        partial = ""
        isStopping = false
        _state.value = VoiceState.Idle
    }

    // ------------------------------------------------------------ recogniser

    private fun createRecognizer(): SpeechRecognizer? {
        recognizer?.let { return it }

        val created = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                SpeechRecognizer.isOnDeviceRecognitionAvailable(appContext)
            ) {
                SpeechRecognizer.createOnDeviceSpeechRecognizer(appContext)
            } else if (SpeechRecognizer.isRecognitionAvailable(appContext)) {
                SpeechRecognizer.createSpeechRecognizer(appContext)
            } else {
                null
            }
        }.getOrNull() ?: return null

        created.setRecognitionListener(listener)
        recognizer = created
        return created
    }

    private val listener = object : RecognitionListener {

        override fun onReadyForSpeech(params: Bundle?) {
            _state.value = VoiceState.Listening(partial)
        }

        override fun onBeginningOfSpeech() {
            _state.value = VoiceState.Listening(partial)
        }

        override fun onRmsChanged(rmsdB: Float) = Unit

        override fun onBufferReceived(buffer: ByteArray?) = Unit

        override fun onEndOfSpeech() {
            handler.removeCallbacks(timeout)
            if (_state.value.isActive) _state.value = VoiceState.Processing
        }

        override fun onPartialResults(partialResults: Bundle?) {
            val text = firstResult(partialResults) ?: return
            partial = text
            if (_state.value is VoiceState.Listening) _state.value = VoiceState.Listening(text)
        }

        override fun onResults(results: Bundle?) {
            handler.removeCallbacks(timeout)
            val text = firstResult(results)?.trim().orEmpty().ifEmpty { partial.trim() }
            _state.value = if (text.isEmpty()) {
                VoiceState.Failed(VoiceFailure.NO_SPEECH)
            } else {
                VoiceState.Done(text)
            }
            partial = ""
            isStopping = false
        }

        override fun onEvent(eventType: Int, params: Bundle?) = Unit

        override fun onError(error: Int) {
            handler.removeCallbacks(timeout)

            // Stopping normally can surface as NO_MATCH after a valid partial
            // result. Keeping what was heard is better than discarding it and
            // telling the user nothing was said when they watched it appear.
            if (isStopping && partial.isNotBlank()) {
                _state.value = VoiceState.Done(partial.trim())
                partial = ""
                isStopping = false
                return
            }

            ReplyLog.event { "voice: error $error" }
            _state.value = when (error) {
                SpeechRecognizer.ERROR_NO_MATCH,
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> VoiceState.Failed(VoiceFailure.NO_SPEECH)

                SpeechRecognizer.ERROR_NETWORK,
                SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> VoiceState.Failed(VoiceFailure.NETWORK)

                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> VoiceState.PermissionDenied

                // Added in API 33. Referenced as literals so this file compiles
                // and behaves identically whatever the compileSdk is, and so a
                // pre-33 recogniser that happens to report them is handled too.
                ERROR_LANGUAGE_NOT_SUPPORTED,
                ERROR_LANGUAGE_UNAVAILABLE -> VoiceState.Failed(VoiceFailure.LANGUAGE_UNAVAILABLE)

                SpeechRecognizer.ERROR_CLIENT,
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> VoiceState.Failed(VoiceFailure.GENERIC)

                else -> VoiceState.Failed(VoiceFailure.GENERIC)
            }
            partial = ""
            isStopping = false
        }

        private fun firstResult(bundle: Bundle?): String? =
            bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()
                ?.takeIf { it.isNotBlank() }
    }

    private companion object {
        const val ERROR_LANGUAGE_NOT_SUPPORTED = 12
        const val ERROR_LANGUAGE_UNAVAILABLE = 13
    }
}
