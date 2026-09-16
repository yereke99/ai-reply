package kz.yerek.aireply.ai

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kz.yerek.aireply.data.secure.SecureCredentialStore

/**
 * Calls the OpenAI Responses API directly from the device.
 *
 * THE CREDENTIAL. The key is read from the encrypted store at call time and is
 * never held in a property, written to a log, encoded into anything we persist,
 * or included in any error surfaced to the UI. It is entered by the user on the
 * device; no build of this project contains one.
 *
 * The trade-off of this mode, stated plainly rather than buried: a key that
 * reaches a device is a key the device's owner can extract, and every request is
 * billed to it with no rate limit but the provider's own. That is acceptable for
 * a demo on the developer's own phone and is not acceptable for Google Play,
 * which is what [BackendTransport] exists for.
 */
class DirectOpenAITransport(
    private val model: String,
    private val credentials: SecureCredentialStore,
    private val maxOutputTokens: Int = AIConfiguration.MAX_OUTPUT_TOKENS,
    private val timeoutMs: Int = AIConfiguration.REQUEST_TIMEOUT_MS
) : ReplyTransport {

    override suspend fun generate(prompt: ReplyPromptBuilder.Prompt): GeneratedReply {
        val apiKey = credentials.apiKey() ?: AIReplyError.NotConfigured.raise()

        val body = json.encodeToString(
            RequestBody(
                model = model,
                input = listOf(
                    Message("developer", prompt.developer),
                    Message("user", prompt.user)
                ),
                maxOutputTokens = maxOutputTokens,
                temperature = 0.7,
                store = false
            )
        )

        val (status, payload) = try {
            ReplyNetworking.postJson(
                url = ENDPOINT,
                body = body,
                headers = mapOf("Authorization" to "Bearer $apiKey"),
                timeoutMs = timeoutMs
            )
        } catch (throwable: Throwable) {
            throw AIReplyException(ReplyNetworking.mapError(throwable))
        }

        if (status !in 200..299) ReplyNetworking.mapStatus(status).raise()

        val decoded = runCatching { json.decodeFromString<ResponseBody>(payload) }.getOrNull()
            ?: AIReplyError.ServiceUnavailable.raise()

        val text = ReplyNetworking.unwrapQuotes(decoded.text())
        if (text.isEmpty()) AIReplyError.EmptyResponse.raise()

        return GeneratedReply(text = text)
    }

    // ----------------------------------------------------------- wire format

    @Serializable
    private data class Message(val role: String, val content: String)

    @Serializable
    private data class RequestBody(
        val model: String,
        val input: List<Message>,
        @SerialName("max_output_tokens") val maxOutputTokens: Int,
        val temperature: Double,
        /**
         * Opts out of server-side conversation retention. Private messages
         * should not be sitting in anyone's dashboard.
         */
        val store: Boolean
    )

    @Serializable
    private data class ResponseBody(
        val output: List<Output>? = null,
        @SerialName("output_text") val outputText: String? = null
    ) {
        @Serializable
        data class Output(val type: String, val content: List<Content>? = null)

        @Serializable
        data class Content(val type: String, val text: String? = null)

        fun text(): String {
            output?.let { outputs ->
                val joined = outputs
                    .filter { it.type == "message" }
                    .flatMap { it.content.orEmpty() }
                    .filter { it.type == "output_text" }
                    .mapNotNull { it.text }
                    .joinToString("")
                    .trim()
                if (joined.isNotEmpty()) return joined
            }
            return outputText?.trim().orEmpty()
        }
    }

    private companion object {
        const val ENDPOINT = "https://api.openai.com/v1/responses"

        val json = Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
            explicitNulls = false
        }
    }
}
