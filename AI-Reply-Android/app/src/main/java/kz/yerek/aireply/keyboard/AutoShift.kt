package kz.yerek.aireply.keyboard

/**
 * Where a sentence starts.
 *
 * Ported from the iOS implementation, including its most important property: it
 * only ever answers "should shift go ON". Shift is turned off once, at insertion
 * time, so a manual shift the user pressed themselves is never fought by this.
 */
object AutoShift {

    fun isAtSentenceStart(context: String?): Boolean {
        if (context.isNullOrEmpty()) return true

        var index = context.length
        var trailingSpaces = 0
        while (index > 0 && context[index - 1] == ' ') {
            trailingSpaces++
            index--
        }
        if (index == 0) return true

        val last = context[index - 1]
        if (last == '\n') return true
        if (trailingSpaces == 0) return false
        return last == '.' || last == '!' || last == '?'
    }
}
