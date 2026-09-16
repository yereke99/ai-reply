package kz.yerek.aireply.core.lang

import android.content.Context
import kz.yerek.aireply.R
import kz.yerek.aireply.domain.model.RelationshipKind
import kz.yerek.aireply.domain.model.ReplyTemplate

/**
 * Turns a template into the name a user sees.
 *
 * Custom names are shown verbatim — a user who typed "Supplier" gets "Supplier"
 * in every UI language, because that is their word, not ours to translate.
 * Built-ins resolve through ordinary string resources, which is why this needs
 * a [Context]: pass one from [LocalizedContext] to name a template in a
 * specific language rather than the device's.
 */
object TemplateNaming {

    fun displayName(context: Context, template: ReplyTemplate): String {
        template.customName?.takeIf { it.isNotBlank() }?.let { return it }
        return context.getString(resource(template.relationship))
    }

    fun resource(kind: RelationshipKind): Int = when (kind) {
        RelationshipKind.FRIEND -> R.string.relationship_friend
        RelationshipKind.CLIENT -> R.string.relationship_client
        RelationshipKind.BUSINESS -> R.string.relationship_business
        RelationshipKind.WORK -> R.string.relationship_work
        RelationshipKind.CUSTOM -> R.string.relationship_custom
    }
}
