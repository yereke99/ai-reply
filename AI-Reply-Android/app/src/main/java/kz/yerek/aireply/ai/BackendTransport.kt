package kz.yerek.aireply.ai

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kz.yerek.aireply.data.secure.SecureCredentialStore
import kz.yerek.aireply.domain.model.BusinessContext
import kz.yerek.aireply.domain.model.EmojiPolicy
import kz.yerek.aireply.domain.model.ReplyLength
import kz.yerek.aireply.domain.model.ReplyTone
import kz.yerek.aireply.domain.model.WorkingHours
import kz.yerek.aireply.domain.model.WorkingHoursBehaviour

/**
 * Calls our own HTTPS service, which holds the provider credential.
 *
 * This is the production shape: the key never reaches a device, the model is
 * configured once server-side, and rate limiting, abuse controls and cost
 * accounting live somewhere a user cannot edit.
 *
 * The device holds only a signed, expiring client token, obtained by exchanging
 * a random per-install identifier. That token is stored encrypted, not in
 * preferences.
 *
 * The wire format is byte-compatible with the iOS client, including the legacy
 * field name `keyboard_language`, so both platforms talk to one deployed
 * service without it having to branch on who is calling.
 */
class BackendTransport(
    private val baseUrl: String,
    private val context: RequestContext,
    private val credentials: SecureCredentialStore,
    private val installIdentifier: String,
    private val timeoutMs: Int = AIConfiguration.REQUEST_TIMEOUT_MS
) : ReplyTransport {

    /**
     * The structured fields the service needs alongside the prompt. The service
     * builds its own prompt from these; sending both keeps the two transports
     * interchangeable from the caller's point of view.
     */
    data class RequestContext(
        val message: String,
        val templateId: String,
        /**
         * The APP's language code. Named `keyboard_language` on the wire for
         * compatibility with the deployed service; it is used there for logging
         * and template naming only, never to choose the reply's language — that
         * follows the incoming message.
         */
        val appLanguage: String,
        val profileDescription: String,
        val profileRole: String,
        val preferredTone: ReplyTone,
        val profileBusiness: BusinessContext,
        val templateName: String,
        val templateRelationship: String,
        val templateTone: ReplyTone,
        val templateInstructions: String,
        val templateReplyLength: ReplyLength,
        val templateEmojiPolicy: EmojiPolicy,
        val templateBusiness: BusinessContext?,
        val templateWorkingHoursBehaviour: WorkingHoursBehaviour,
        val business: WorkingHours.Context?,
        /**
         * Android's instruction field. Absent from the iOS client, so the
         * service must treat it as optional; a server that ignores it degrades
         * to iOS behaviour rather than failing.
         */
        val userInstruction: String
    )

    override suspend fun generate(prompt: ReplyPromptBuilder.Prompt): GeneratedReply {
        val token = credentials.backendToken() ?: register()

        return try {
            post(token)
        } catch (exception: AIReplyException) {
            if (exception.error != AIReplyError.AuthenticationFailed) throw exception
            // The token expired or the server's signing secret rotated. One
            // silent re-registration, then give up rather than loop.
            post(register())
        }
    }

    private suspend fun register(): String {
        val (status, payload) = try {
            ReplyNetworking.postJson(
                url = endpoint("v1/auth/register"),
                body = json.encodeToString(RegisterRequest(installIdentifier)),
                headers = emptyMap(),
                timeoutMs = timeoutMs
            )
        } catch (throwable: Throwable) {
            throw AIReplyException(ReplyNetworking.mapError(throwable))
        }

        if (status !in 200..299) AIReplyError.ServiceUnavailable.raise()

        val decoded = runCatching { json.decodeFromString<RegisterResponse>(payload) }.getOrNull()
            ?: AIReplyError.ServiceUnavailable.raise()

        credentials.setBackendToken(decoded.token)
        return decoded.token
    }

    private suspend fun post(token: String): GeneratedReply {
        val body = json.encodeToString(
            GenerateRequest(
                message = context.message,
                templateId = context.templateId,
                keyboardLanguage = context.appLanguage,
                userInstruction = context.userInstruction.trim().ifEmpty { null },
                profile = Profile(
                    description = context.profileDescription,
                    role = context.profileRole.ifEmpty { null },
                    preferredTone = context.preferredTone.raw,
                    business = Business.of(context.profileBusiness)
                ),
                template = Template(
                    name = context.templateName,
                    relationship = context.templateRelationship,
                    tone = context.templateTone.raw,
                    instructions = context.templateInstructions,
                    replyLength = context.templateReplyLength.raw,
                    emojiPolicy = context.templateEmojiPolicy.raw,
                    workingHoursBehaviour = context.templateWorkingHoursBehaviour.raw,
                    business = Business.of(context.templateBusiness)
                ),
                businessContext = context.business?.let {
                    WorkingHoursBlock(
                        enabled = it.isEnabled,
                        isWithinWorkingHours = it.isWithinWorkingHours,
                        currentLocalTime = it.currentLocalTime,
                        nextWorkingPeriod = it.nextWorkingPeriod,
                        weeklySchedule = it.weeklySchedule
                    )
                }
            )
        )

        val (status, payload) = try {
            ReplyNetworking.postJson(
                url = endpoint("v1/reply/generate"),
                body = body,
                headers = mapOf("Authorization" to "Bearer $token"),
                timeoutMs = timeoutMs
            )
        } catch (throwable: Throwable) {
            throw AIReplyException(ReplyNetworking.mapError(throwable))
        }

        if (status !in 200..299) {
            when (status) {
                413 -> AIReplyError.MessageTooLong(AIConfiguration.MAX_MESSAGE_CHARACTERS).raise()
                else -> ReplyNetworking.mapStatus(status).raise()
            }
        }

        val decoded = runCatching { json.decodeFromString<GenerateResponse>(payload) }.getOrNull()
            ?: AIReplyError.ServiceUnavailable.raise()

        val text = ReplyNetworking.unwrapQuotes(decoded.reply.trim())
        if (text.isEmpty()) AIReplyError.EmptyResponse.raise()

        return GeneratedReply(text = text, detectedLanguage = decoded.detectedLanguage)
    }

    private fun endpoint(path: String): String = baseUrl.trimEnd('/') + "/" + path

    // ----------------------------------------------------------- wire format

    /**
     * Deliberately minimal. No device identifier, no phone number, no contacts,
     * no chat history, no location, no advertising id, no device model, no OS
     * version. Only what writing this one reply requires.
     */
    @Serializable
    private data class GenerateRequest(
        val message: String,
        @SerialName("template_id") val templateId: String,
        @SerialName("keyboard_language") val keyboardLanguage: String,
        @SerialName("user_instruction") val userInstruction: String? = null,
        val profile: Profile,
        val template: Template,
        @SerialName("business_context") val businessContext: WorkingHoursBlock? = null
    )

    /**
     * Fields the user left blank are omitted rather than sent as empty strings,
     * so the server never has to distinguish "not answered" from "answered with
     * nothing".
     */
    @Serializable
    private data class Business(
        val offering: String? = null,
        val summary: String? = null,
        val rules: List<String>? = null
    ) {
        companion object {
            fun of(source: BusinessContext?): Business? {
                if (source == null || source.isEmpty) return null
                return Business(
                    offering = source.offering.trim().ifEmpty { null },
                    summary = source.summary.trim().ifEmpty { null },
                    rules = source.cleanRules.ifEmpty { null }
                )
            }
        }
    }

    @Serializable
    private data class Profile(
        val description: String,
        val role: String? = null,
        @SerialName("preferred_tone") val preferredTone: String,
        val business: Business? = null
    )

    @Serializable
    private data class Template(
        val name: String,
        val relationship: String,
        val tone: String,
        val instructions: String,
        @SerialName("reply_length") val replyLength: String,
        @SerialName("emoji_policy") val emojiPolicy: String,
        @SerialName("working_hours_behaviour") val workingHoursBehaviour: String,
        val business: Business? = null
    )

    @Serializable
    private data class WorkingHoursBlock(
        val enabled: Boolean,
        @SerialName("is_within_working_hours") val isWithinWorkingHours: Boolean,
        @SerialName("current_local_time") val currentLocalTime: String,
        @SerialName("next_working_period") val nextWorkingPeriod: String? = null,
        @SerialName("weekly_schedule") val weeklySchedule: String? = null
    )

    @Serializable
    private data class GenerateResponse(
        val reply: String,
        @SerialName("detected_language") val detectedLanguage: String? = null
    )

    @Serializable
    private data class RegisterRequest(@SerialName("install_id") val installId: String)

    @Serializable
    private data class RegisterResponse(val token: String)

    private companion object {
        val json = Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
            explicitNulls = false
        }
    }
}
