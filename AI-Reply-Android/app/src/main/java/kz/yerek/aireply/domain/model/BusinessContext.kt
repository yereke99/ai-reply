package kz.yerek.aireply.domain.model

import kotlinx.serialization.Serializable
import kz.yerek.aireply.core.text.clampToCodePoints

/**
 * What the user offers and the rules a reply has to respect.
 *
 * Deliberately three plain fields rather than a prompt. The user answers normal
 * questions ("what do you sell?", "what should the assistant never promise?")
 * and this type carries the answers; turning them into model context is
 * `ReplyPromptBuilder`'s job and nobody else's. That separation is what keeps
 * the UI free of prompt engineering and lets the wording of the prompt improve
 * without migrating anyone's saved data.
 *
 * Used at two levels: on [UserProfile] for facts true in every conversation,
 * and optionally on a [ReplyTemplate] for facts that apply only when replying
 * to that kind of person.
 */
@Serializable
data class BusinessContext(
    val offering: String = "",
    val summary: String = "",
    val rules: List<String> = emptyList()
) {

    val isEmpty: Boolean
        get() = offering.isBlank() && summary.isBlank() && cleanRules.isEmpty()

    /**
     * Rules with blanks and duplicates removed, in entry order. This is what
     * the prompt sees, so an empty row a user left behind in the editor never
     * reaches the model as an empty instruction.
     */
    val cleanRules: List<String>
        get() {
            val seen = HashSet<String>()
            val result = ArrayList<String>(rules.size)
            for (rule in rules) {
                val trimmed = rule.trim()
                if (trimmed.isEmpty()) continue
                if (!seen.add(trimmed.lowercase())) continue
                result.add(trimmed)
            }
            return result
        }

    fun withOffering(value: String) = copy(offering = value.clampToCodePoints(MAX_OFFERING))

    fun withSummary(value: String) = copy(summary = value.clampToCodePoints(MAX_SUMMARY))

    fun withRule(value: String, index: Int): BusinessContext {
        if (index !in rules.indices) return this
        val updated = rules.toMutableList()
        updated[index] = value.clampToCodePoints(MAX_RULE)
        return copy(rules = updated)
    }

    /**
     * Ignored once the list is full, so a dictation that produces twenty
     * candidate rules cannot quietly grow the prompt without bound.
     */
    fun addingRule(value: String = ""): BusinessContext {
        if (rules.size >= MAX_RULES) return this
        return copy(rules = rules + value.clampToCodePoints(MAX_RULE))
    }

    fun removingRule(index: Int): BusinessContext {
        if (index !in rules.indices) return this
        return copy(rules = rules.filterIndexed { position, _ -> position != index })
    }

    companion object {
        const val MAX_OFFERING = 120
        const val MAX_SUMMARY = 400
        const val MAX_RULE = 200
        const val MAX_RULES = 8

        val EMPTY = BusinessContext()
    }
}
