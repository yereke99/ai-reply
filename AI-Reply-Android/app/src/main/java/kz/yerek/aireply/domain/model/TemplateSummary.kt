package kz.yerek.aireply.domain.model

import kotlinx.serialization.Serializable
import kz.yerek.aireply.core.lang.AppLanguage

/**
 * The few bytes the keyboard needs to DRAW the template row, and nothing else.
 *
 * WHY THIS EXISTS. The keyboard's first frame cannot wait on a file read, so
 * without this it would be seeded from the four default built-ins — and a user
 * who renamed Client, hid Work or added Supplier would see the wrong chips for
 * one frame and then a visible swap.
 *
 * The fix is not to read the file sooner. It is to keep a summary small enough
 * that reading it synchronously is free: identifiers, the three localized
 * names, and order. No instructions, no business context, no rules, no profile
 * text — none of which the row needs, and all of which the full configuration
 * still carries for the request that generation actually makes.
 */
@Serializable
data class TemplateSummary(
    val id: String,
    /**
     * Name per app language code. Stored resolved rather than as a
     * relationship, so drawing the row needs no string lookup at all.
     */
    val names: Map<String, String>
) {
    fun name(language: AppLanguage): String =
        names[language.code] ?: names[AppLanguage.ENGLISH.code] ?: id
}
