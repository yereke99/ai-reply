import SwiftUI

/// Localized labels for the shared enums.
///
/// They live in the app target rather than in `Shared` because they resolve
/// through the app's `Localizable.xcstrings`, which follows the app's interface
/// language. The keyboard needs the same concepts keyed by the KEYBOARD's
/// language instead, and gets them from `AIReplyStrings`.
extension ReplyTone {
    var titleKey: LocalizedStringKey {
        switch self {
        case .natural:      return "tone.natural"
        case .friendly:     return "tone.friendly"
        case .professional: return "tone.professional"
        case .formal:       return "tone.formal"
        case .short:        return "tone.short"
        }
    }
}

extension ReplyLength {
    var titleKey: LocalizedStringKey {
        switch self {
        case .short:  return "templates.length.short"
        case .medium: return "templates.length.medium"
        }
    }
}

extension WorkingHoursBehaviour {
    var titleKey: LocalizedStringKey {
        switch self {
        case .ignore:              return "templates.hours.ignore"
        case .mentionWhenRelevant: return "templates.hours.mentionWhenRelevant"
        case .alwaysMention:       return "templates.hours.alwaysMention"
        }
    }
}

extension RelationshipKind {
    var titleKey: LocalizedStringKey {
        switch self {
        case .friend:   return "relationship.friend"
        case .client:   return "relationship.client"
        case .business: return "relationship.business"
        case .work:     return "relationship.work"
        case .custom:   return "relationship.custom"
        }
    }
}

extension EmojiPolicy {
    var titleKey: LocalizedStringKey {
        switch self {
        case .allowed: return "templates.emoji.allowed"
        case .minimal: return "templates.emoji.minimal"
        case .none:    return "templates.emoji.none"
        }
    }
}
