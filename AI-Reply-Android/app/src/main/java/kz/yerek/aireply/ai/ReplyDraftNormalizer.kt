package kz.yerek.aireply.ai

/**
 * Final lightweight cleanup before a draft is inserted into the host field.
 *
 * URL substrings are copied through untouched, which is the whole reason this
 * is not a single chain of replaces: collapsing double spaces inside a URL, or
 * removing the space before the punctuation in one, produces a link that does
 * not work.
 */
class ReplyDraftNormalizer {

    fun normalize(draft: String): String {
        val trimmed = draft.trim()
        if (trimmed.isEmpty()) return ""

        val output = StringBuilder()
        var cursor = 0

        for (match in URL.findAll(trimmed)) {
            if (match.range.first > cursor) {
                output.append(normalizePlain(trimmed.substring(cursor, match.range.first)))
            }
            output.append(match.value)
            cursor = match.range.last + 1
        }

        if (cursor < trimmed.length) {
            output.append(normalizePlain(trimmed.substring(cursor)))
        }

        return EXCESSIVE_BLANK_LINES.replace(output.toString(), "\n\n").trim()
    }

    private fun normalizePlain(segment: String): String {
        var value = REPEATED_SPACE.replace(segment, " ")
        value = SPACE_BEFORE_PUNCTUATION.replace(value) { it.groupValues[1] }
        return value
    }

    private companion object {
        val URL = Regex("""\b(?:https?://|www\.)\S+""", RegexOption.IGNORE_CASE)
        val REPEATED_SPACE = Regex("""[^\S\r\n]{2,}""")
        val SPACE_BEFORE_PUNCTUATION = Regex("""[^\S\r\n]+([,.!?;:])""")
        val EXCESSIVE_BLANK_LINES = Regex("""\n[ \t]*\n(?:[ \t]*\n)+""")
    }
}
