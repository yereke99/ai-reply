package kz.yerek.aireply.core.lang

import android.content.Context
import android.content.res.Configuration
import android.os.LocaleList
import java.util.Locale

/**
 * Resolves resources in a specific language, regardless of the device's own.
 *
 * WHY THIS EXISTS, and why it is the single most useful thing Android offers
 * that iOS does not here. On iOS the keyboard extension cannot see which
 * language the containing app is set to, so the project carries two hand-written
 * Swift tables — `AIReplyStrings` keyed by app language, `KeyboardStrings` keyed
 * by layout — duplicating strings that already exist in the string catalogue.
 *
 * On Android the same problem is one call: a Context configured with a locale
 * reads the ordinary `strings.xml` for that locale. So the keyboard holds two
 * of them — one for the APP's language (chips, Insert, Regenerate, errors) and
 * one for the LAYOUT's language (space, return) — and no UI string is written
 * in Kotlin anywhere in this project.
 */
object LocalizedContext {

    fun wrap(base: Context, language: AppLanguage?): Context =
        if (language == null) base else wrap(base, language.locale)

    fun wrap(base: Context, language: KeyboardLanguage): Context =
        wrap(base, Locale(language.code))

    private fun wrap(base: Context, locale: Locale): Context {
        val configuration = Configuration(base.resources.configuration)
        configuration.setLocale(locale)
        configuration.setLocales(LocaleList(locale))
        configuration.setLayoutDirection(locale)
        return base.createConfigurationContext(configuration)
    }
}
