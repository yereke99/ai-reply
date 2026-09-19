package kz.yerek.aireply.data.account

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kz.yerek.aireply.data.legal.StoredLegalConsent

/**
 * What the client tells the server about itself.
 *
 * Құрылғы туралы ең қажетті мәлімет қана.
 *
 * Deliberately minimal: platform, app version, OS version, locale, time zone.
 * No device name, no model identifier, no ANDROID_ID, no advertising id.
 */
@Serializable
data class DeviceDescriptor(
    @SerialName("device_id") val deviceId: String,
    val platform: String,
    @SerialName("app_version") val appVersion: String,
    @SerialName("os_version") val osVersion: String,
    val locale: String,
    val timezone: String
)

@Serializable
internal data class RefreshRequest(
    @SerialName("refresh_token") val refreshToken: String,
    val device: DeviceDescriptor
)

@Serializable
internal data class LogoutRequest(@SerialName("refresh_token") val refreshToken: String)

@Serializable
private data class RequestOtpRequest(val identifier: String, val locale: String)

@Serializable
private data class VerifyOtpRequest(
    val identifier: String,
    val code: String,
    val device: DeviceDescriptor
)

/** Only the fields that changed; everything else is left alone server-side. */
@Serializable
data class ProfileUpdate(
    @SerialName("display_name") val displayName: String? = null,
    val role: String? = null,
    val description: String? = null,
    @SerialName("preferred_tone") val preferredTone: String? = null,
    @SerialName("business_offering") val businessOffering: String? = null,
    @SerialName("business_summary") val businessSummary: String? = null,
    @SerialName("business_rules") val businessRules: List<String>? = null,
    val locale: String? = null,
    val timezone: String? = null,
    @SerialName("onboarding_completed") val onboardingCompleted: Boolean? = null
)

@Serializable
private data class RegisterDeviceRequest(
    @SerialName("device_id") val deviceId: String,
    val platform: String,
    @SerialName("app_version") val appVersion: String,
    @SerialName("os_version") val osVersion: String,
    val locale: String,
    @SerialName("push_token") val pushToken: String? = null,
    @SerialName("push_enabled") val pushEnabled: Boolean
)

@Serializable
private data class CheckoutRequest(@SerialName("plan_id") val planId: String)

@Serializable
private data class LegalConsentRequest(
    @SerialName("terms_version") val termsVersion: String,
    @SerialName("privacy_version") val privacyVersion: String,
    val locale: String,
    val platform: String,
    @SerialName("app_version") val appVersion: String
)

/**
 * Every call the app makes to the AI Reply backend.
 *
 * Барлық сұраныс осы жерден өтеді: қайталанатын желі коды жоқ.
 *
 * The service holds no state. Tokens belong to [AccountSession] and the base
 * URL to the configuration, so a screen only says what it wants, not how
 * authentication works.
 */
class AccountService(
    private val session: AccountSession,
    private val baseUrlProvider: () -> String?,
    private val deviceDescriptor: () -> DeviceDescriptor
) {

    private fun client(): ApiClient {
        val baseUrl = baseUrlProvider() ?: ApiError.InvalidRequest.raise()
        return ApiClient(baseUrl)
    }

    private val json: Json get() = jsonCodec

    // ------------------------------------------------------ public endpoints

    /** Countries, limits and current legal versions. Called before sign-in. */
    suspend fun serverConfig(): ServerConfigDto {
        val client = client()
        return decode(ServerConfigDto.serializer(), client.request("GET", "api/v1/config"))
    }

    suspend fun plans(): List<PlanDto> {
        val client = client()
        return decode(PlanListDto.serializer(), client.request("GET", "api/v1/plans")).plans
    }

    // -------------------------------------------------------------- sign-in

    /** Asks for a code. The server decides how it is delivered. */
    suspend fun requestCode(identifier: String, locale: String): ChallengeDto {
        val client = client()
        val body = json.encodeToString(
            RequestOtpRequest.serializer(), RequestOtpRequest(identifier, locale)
        )
        return decode(ChallengeDto.serializer(), client.request("POST", "api/v1/auth/request-otp", body))
    }

    /** Verifies the code and stores the resulting session. */
    suspend fun verifyCode(identifier: String, code: String): AccountSessionDto {
        val client = client()
        val body = json.encodeToString(
            VerifyOtpRequest.serializer(),
            VerifyOtpRequest(identifier, code, deviceDescriptor())
        )
        val result = decode(
            AccountSessionDto.serializer(),
            client.request("POST", "api/v1/auth/verify-otp", body)
        )
        session.adopt(result)
        return result
    }

    suspend fun signOut() = session.signOut()

    // ----------------------------------------------- authenticated endpoints

    suspend fun account(): AccountDto = session.authenticated { token ->
        decode(AccountDto.serializer(), client().request("GET", "api/v1/me", token = token))
    }

    suspend fun usage(): UsageDto = session.authenticated { token ->
        decode(UsageDto.serializer(), client().request("GET", "api/v1/me/usage", token = token))
    }

    suspend fun subscription(): SubscriptionDto = session.authenticated { token ->
        decode(SubscriptionDto.serializer(), client().request("GET", "api/v1/me/subscription", token = token))
    }

    /**
     * Saves profile changes.
     *
     * POST rather than PATCH on purpose: HttpURLConnection refuses PATCH, and
     * the server exposes this alias for exactly that reason.
     */
    suspend fun updateProfile(update: ProfileUpdate): AccountProfile = session.authenticated { token ->
        val body = json.encodeToString(ProfileUpdate.serializer(), update)
        decode(AccountProfile.serializer(), client().request("POST", "api/v1/me", body, token))
    }

    /** Registers this device so a push token has somewhere to live later. */
    suspend fun registerDevice(pushToken: String? = null) {
        val descriptor = deviceDescriptor()
        val body = json.encodeToString(
            RegisterDeviceRequest.serializer(),
            RegisterDeviceRequest(
                deviceId = descriptor.deviceId,
                platform = descriptor.platform,
                appVersion = descriptor.appVersion,
                osVersion = descriptor.osVersion,
                locale = descriptor.locale,
                pushToken = pushToken,
                pushEnabled = pushToken != null
            )
        )
        session.authenticated { token ->
            client().request("POST", "api/v1/devices", body, token)
        }
    }

    suspend fun recordLegalConsent(consent: StoredLegalConsent): LegalConsentDto =
        session.authenticated { token ->
            val request = LegalConsentRequest(
                termsVersion = consent.termsVersion,
                privacyVersion = consent.privacyVersion,
                locale = consent.locale,
                platform = consent.platform,
                appVersion = consent.appVersion
            )
            val body = json.encodeToString(LegalConsentRequest.serializer(), request)
            decode(
                LegalConsentDto.serializer(),
                client().request("POST", "api/v1/me/consents", body, token)
            )
        }

    // --------------------------------------- subscription (demo payment flow)

    suspend fun startCheckout(planId: String): CheckoutDto = session.authenticated { token ->
        val body = json.encodeToString(CheckoutRequest.serializer(), CheckoutRequest(planId))
        decode(CheckoutDto.serializer(), client().request("POST", "api/v1/payments/checkout", body, token))
    }

    /**
     * Confirms a payment. With the demo adapter this is what actually moves the
     * account onto the chosen plan; with a real acquirer the confirmation
     * arrives from the provider and this call only reads the result.
     */
    suspend fun confirmCheckout(paymentId: String): CheckoutResultDto = session.authenticated { token ->
        decode(
            CheckoutResultDto.serializer(),
            client().request("POST", "api/v1/payments/$paymentId/confirm", "{}", token)
        )
    }

    private companion object {
        val jsonCodec = Json {
            ignoreUnknownKeys = true
            encodeDefaults = false
            explicitNulls = false
        }

        /** A body we cannot parse is a malformed response, not a crash. */
        fun <T> decode(serializer: kotlinx.serialization.KSerializer<T>, body: String): T =
            runCatching { jsonCodec.decodeFromString(serializer, body) }
                .getOrElse { ApiError.MalformedResponse.raise() }
    }
}
