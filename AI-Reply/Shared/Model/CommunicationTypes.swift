import Foundation

/// How a reply should sound. Kept deliberately short: five presets a user can
/// hold in their head beat twenty sliders nobody touches.
enum ReplyTone: String, CaseIterable, Codable, Identifiable, Sendable {
    case natural
    case friendly
    case professional
    case formal
    case short

    var id: String { rawValue }
}

/// How long a reply should be. Two values, because the real constraint is
/// "messenger short", and the model already knows what that means.
enum ReplyLength: String, CaseIterable, Codable, Identifiable, Sendable {
    case short
    case medium

    var id: String { rawValue }
}

/// How much emoji a reply may use. A Friend template that answers with no
/// emoji at all reads as cold; a Client template that answers with three reads
/// as unserious. One setting, three values, is enough to separate them.
enum EmojiPolicy: String, CaseIterable, Codable, Identifiable, Sendable {
    case allowed
    case minimal
    case none

    var id: String { rawValue }
}

/// What a template should do with the user's working hours.
enum WorkingHoursBehaviour: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Never bring hours up. Right for the Friend template.
    case ignore
    /// Mention them only when the incoming message asks for something
    /// time-sensitive that falls outside them. The sane default.
    case mentionWhenRelevant = "mention_when_relevant"
    /// Acknowledge them whenever they are relevant at all.
    case alwaysMention = "always_mention"

    var id: String { rawValue }
}

/// The relationship a template describes. Drives the built-in behaviour that
/// the brief specifies for each one.
enum RelationshipKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case friend
    case client
    case business
    case work
    case custom

    var id: String { rawValue }

    /// The four the app ships with, in bar order. `custom` is not one of them:
    /// it is what a user-created template is.
    static let builtIns: [RelationshipKind] = [.friend, .client, .business, .work]

    /// Sensible starting point for a template of this kind.
    var defaultTone: ReplyTone {
        switch self {
        case .friend:   return .friendly
        case .client:   return .professional
        case .business: return .professional
        case .work:     return .natural
        case .custom:   return .natural
        }
    }

    var defaultEmojiPolicy: EmojiPolicy {
        switch self {
        case .friend:   return .allowed
        case .client:   return .minimal
        case .business: return .none
        case .work:     return .minimal
        case .custom:   return .minimal
        }
    }

    /// Whether this kind of conversation has business facts worth configuring.
    /// A friend does not: asking someone what they sell before they can set up
    /// a casual template would be a worse product, not a more capable one.
    var usesBusinessContext: Bool {
        switch self {
        case .friend:   return false
        case .client, .business, .work, .custom: return true
        }
    }

    var defaultWorkingHoursBehaviour: WorkingHoursBehaviour {
        switch self {
        case .friend:   return .ignore
        case .client:   return .mentionWhenRelevant
        case .business: return .mentionWhenRelevant
        case .work:     return .mentionWhenRelevant
        case .custom:   return .mentionWhenRelevant
        }
    }
}
