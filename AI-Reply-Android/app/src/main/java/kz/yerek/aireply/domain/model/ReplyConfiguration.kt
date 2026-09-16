package kz.yerek.aireply.domain.model

import kotlinx.serialization.Serializable

/** Everything the user configured, as one value. */
@Serializable
data class ReplyConfiguration(
    val profile: UserProfile = UserProfile.EMPTY,
    val templates: List<ReplyTemplate> = ReplyTemplate.defaults
) {

    /** Templates the keyboard bar should show, in order. */
    val visibleTemplates: List<ReplyTemplate>
        get() = templates.filter { it.isVisible }.sortedBy { it.sortIndex }

    val orderedTemplates: List<ReplyTemplate>
        get() = templates.sortedBy { it.sortIndex }

    fun template(id: String): ReplyTemplate? = templates.firstOrNull { it.id == id }

    /**
     * Repairs anything that would leave the user stuck: missing built-ins after
     * a decode, every template hidden, duplicate sort indices.
     */
    fun normalized(): ReplyConfiguration {
        val working = templates.toMutableList()

        for (kind in RelationshipKind.builtIns) {
            if (working.none { it.id == kind.raw }) {
                working.add(ReplyTemplate.builtIn(kind, working.size))
            }
        }

        if (working.none { it.isVisible }) {
            for (index in working.indices) {
                if (working[index].isBuiltIn) {
                    working[index] = working[index].copy(isVisible = true)
                }
            }
        }

        working.sortBy { it.sortIndex }
        val reindexed = working.mapIndexed { index, template -> template.copy(sortIndex = index) }
        return copy(templates = reindexed)
    }

    companion object {
        val INITIAL = ReplyConfiguration()
    }
}
