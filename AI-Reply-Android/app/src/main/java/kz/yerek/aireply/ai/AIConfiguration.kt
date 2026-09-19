package kz.yerek.aireply.ai

import kz.yerek.aireply.data.secure.SecureCredentialStore
import kz.yerek.aireply.data.settings.SettingsStore

/** Where reply generation happens. */
enum class AITransportMode(val raw: String) {
    /**
     * The app calls the provider itself, with a key the user entered on device.
     * Nothing is hardcoded and nothing ships in the APK.
     */
    DIRECT("direct"),

    /**
     * The app calls our own HTTPS service, which holds the credential. The right
     * answer for anything beyond a demo: the key never reaches a device at all,
     * and rate limits, abuse controls and cost accounting live somewhere the
     * user cannot edit.
     */
    BACKEND("backend");

    companion object {
        fun fromRaw(raw: String?): AITransportMode =
            entries.firstOrNull { it.raw == raw } ?: BACKEND
    }
}

/**
 * Non-secret AI settings.
 *
 * Only settings live here. The credential lives in [SecureCredentialStore] and
 * never touches these preferences.
 */
class AIConfiguration(
    private val settings: SettingsStore,
    private val credentials: SecureCredentialStore
) {

    val mode: AITransportMode get() = AITransportMode.fromRaw(settings.transportMode)

    fun setMode(mode: AITransportMode) {
        settings.transportMode = mode.raw
    }

    val model: String get() = settings.model ?: DEFAULT_MODEL

    fun setModel(value: String) {
        val trimmed = value.trim()
        settings.model = if (trimmed.isEmpty() || trimmed == DEFAULT_MODEL) null else trimmed
    }

    /**
     * Base URL of our own service, used only in [AITransportMode.BACKEND].
     *
     * HTTPS only in production. Plain http is tolerated for a local address so a
     * developer can point at a laptop, and nowhere else.
     */
    val backendBaseUrl: String?
        get() {
            val raw = settings.backendBaseUrl ?: DEFAULT_BACKEND_BASE_URL
            val lower = raw.lowercase()
            if (lower.startsWith("https://")) return raw
            if (lower.startsWith("http://")) {
                val host = lower.removePrefix("http://").substringBefore('/').substringBefore(':')
                val isLocal = host == "localhost" ||
                    host.startsWith("127.") ||
                    host.startsWith("192.168.") ||
                    host.startsWith("10.") ||
                    host == "10.0.2.2" // the Android emulator's view of the host machine
                if (isLocal) return raw
            }
            return null
        }

    val backendBaseUrlString: String get() = settings.backendBaseUrl ?: DEFAULT_BACKEND_BASE_URL

    fun setBackendBaseUrl(value: String) {
        settings.backendBaseUrl = value
    }

    val installIdentifier: String get() = settings.installIdentifier

    /**
     * Whether this configuration expects a signed-in account.
     *
     * Only true when the app is actually pointed at our service. The default
     * build is backend-first, so a clean install signs in before generation.
     */
    val requiresAccount: Boolean
        get() = mode == AITransportMode.BACKEND && backendBaseUrl != null

    /** Whether a generation attempt can even be made right now. */
    val isReady: Boolean
        get() = when (mode) {
            AITransportMode.DIRECT -> credentials.hasApiKey()
            AITransportMode.BACKEND -> backendBaseUrl != null
        }

    companion object {
        /**
         * THE single place a model name appears anywhere in this project. In
         * backend mode the server's own configuration wins and this is unused;
         * in direct mode it is the default the user can override in Settings.
         */
        const val DEFAULT_MODEL = "gpt-4o-mini"

        /**
         * Production AI Reply API endpoint. Mobile clients talk only to this
         * service in the default build; provider credentials stay on the server.
         */
        const val DEFAULT_BACKEND_BASE_URL = "https://api.meily.kz"

        /**
         * Output budget. Sized for 1-4 short sentences plus headroom, because
         * Cyrillic and Kazakh tokenize less efficiently than English and a
         * budget tuned on English alone truncates a Kazakh reply mid-sentence.
         */
        const val MAX_OUTPUT_TOKENS = 180

        /** Hard cap on the incoming message, in code points. */
        const val MAX_MESSAGE_CHARACTERS = 300

        /**
         * Cap on the user's own instruction. Generous enough for a dictated
         * sentence or two, small enough that it cannot quietly double the cost
         * of every request.
         */
        const val MAX_INSTRUCTION_CHARACTERS = 400

        /**
         * Wall-clock budget for one generation, in milliseconds. Long enough for
         * a cold model call, short enough that a stalled network does not leave
         * the keyboard spinning while the user waits to reply to someone.
         */
        const val REQUEST_TIMEOUT_MS = 25_000
    }
}
