package kz.yerek.aireply.data.legal

import android.content.Context
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kz.yerek.aireply.data.account.LegalConfigDto
import kz.yerek.aireply.data.account.LegalConsentDto
import java.time.Instant

@Serializable
data class StoredLegalConsent(
    val termsVersion: String,
    val privacyVersion: String,
    val acceptedAt: String,
    val locale: String,
    val platform: String,
    val appVersion: String,
    val pendingSync: Boolean
)

/** Stores non-secret legal acceptance until it can be attached to an account. */
class LegalConsentStore(context: Context) {
    private val prefs = context.applicationContext
        .getSharedPreferences(NAME, Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    fun current(): StoredLegalConsent? {
        val raw = prefs.getString(KEY_RECORD, null) ?: return null
        return runCatching { json.decodeFromString<StoredLegalConsent>(raw) }.getOrNull()
    }

    fun hasAccepted(config: LegalConfigDto): Boolean {
        val record = current() ?: return false
        return record.termsVersion == config.termsVersion &&
            record.privacyVersion == config.privacyVersion
    }

    fun accept(config: LegalConfigDto, locale: String, appVersion: String): StoredLegalConsent {
        val record = StoredLegalConsent(
            termsVersion = config.termsVersion,
            privacyVersion = config.privacyVersion,
            acceptedAt = Instant.now().toString(),
            locale = locale,
            platform = "android",
            appVersion = appVersion,
            pendingSync = true
        )
        save(record)
        return record
    }

    fun restore(consent: LegalConsentDto) {
        save(
            StoredLegalConsent(
                termsVersion = consent.termsVersion,
                privacyVersion = consent.privacyVersion,
                acceptedAt = consent.acceptedAt,
                locale = consent.locale,
                platform = consent.platform,
                appVersion = consent.appVersion.orEmpty(),
                pendingSync = false
            )
        )
    }

    private fun save(record: StoredLegalConsent) {
        prefs.edit().putString(KEY_RECORD, json.encodeToString(record)).apply()
    }

    private companion object {
        const val NAME = "aireply_legal"
        const val KEY_RECORD = "legal.consent.v1"
    }
}
