package kz.yerek.aireply.core.text

/**
 * Length limits, counted the way the iOS project counts them.
 *
 * Swift counts `unicodeScalars`, not UTF-16 units, and the backend counts the
 * same. A Kotlin `String.length` would disagree with both the moment a user
 * types an emoji, so every limit in this project goes through these two
 * helpers rather than through `length`.
 */

fun String.codePointLength(): Int = codePointCount(0, length)

/**
 * Truncates to [limit] code points. Never splits a surrogate pair, so the
 * result is always valid text rather than a lone high surrogate.
 */
fun String.clampToCodePoints(limit: Int): String {
    if (limit <= 0) return ""
    if (codePointLength() <= limit) return this
    return substring(0, offsetByCodePoints(0, limit))
}
