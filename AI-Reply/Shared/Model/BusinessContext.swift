import Foundation

/// What the user offers and the rules a reply has to respect.
///
/// Deliberately three plain fields rather than a prompt. The user answers
/// normal questions ("what do you sell?", "what should the assistant never
/// promise?") and this type carries the answers; turning them into model
/// context is `ReplyPromptBuilder`'s job and nobody else's. That separation is
/// what keeps the UI free of prompt engineering and lets the wording of the
/// prompt improve without migrating anyone's saved data.
///
/// Used at two levels:
/// * on `UserProfile`, for facts that are true of the user in every
///   conversation ("I run an online clothing store");
/// * optionally on a `ReplyTemplate`, for facts that only apply when replying
///   to that kind of person.
struct BusinessContext: Codable, Hashable, Sendable {

    static let maximumOfferingCharacters = 120
    static let maximumSummaryCharacters = 400
    static let maximumRuleCharacters = 200
    static let maximumRules = 8

    /// What is sold or provided, in the user's own words: "Clothing",
    /// "Дизайн сайтов", "Киім".
    var offering: String

    /// A sentence or two about the work: "We sell men's and women's clothing
    /// and deliver across the country."
    var summary: String

    /// Things the reply must always or never do. One short line each, because
    /// a list the model can follow beats a paragraph it has to interpret.
    var rules: [String]

    static let empty = BusinessContext(offering: "", summary: "", rules: [])

    var isEmpty: Bool {
        offering.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && cleanRules.isEmpty
    }

    /// Rules with blanks and duplicates removed, in entry order. This is what
    /// the prompt sees, so an empty row a user left behind in the editor never
    /// reaches the model as an empty instruction.
    var cleanRules: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for rule in rules {
            let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    // MARK: Editing

    mutating func setOffering(_ value: String) {
        offering = Self.clamp(value, to: Self.maximumOfferingCharacters)
    }

    mutating func setSummary(_ value: String) {
        summary = Self.clamp(value, to: Self.maximumSummaryCharacters)
    }

    mutating func setRule(_ value: String, at index: Int) {
        guard rules.indices.contains(index) else { return }
        rules[index] = Self.clamp(value, to: Self.maximumRuleCharacters)
    }

    /// Ignored once the list is full, so a dictation that produces twenty
    /// candidate rules cannot quietly grow the prompt without bound.
    mutating func addRule(_ value: String = "") {
        guard rules.count < Self.maximumRules else { return }
        rules.append(Self.clamp(value, to: Self.maximumRuleCharacters))
    }

    /// Written by index rather than with `remove(atOffsets:)`, which is a
    /// SwiftUI extension: this type is compiled into the keyboard extension,
    /// which must not link SwiftUI.
    mutating func removeRules(at offsets: IndexSet) {
        rules = rules.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)
    }

    /// Counted in Unicode scalars, matching every other limit in this project
    /// and the backend's own counting.
    private static func clamp(_ value: String, to limit: Int) -> String {
        value.unicodeScalars.count <= limit ? value : String(value.prefix(limit))
    }

    // Tolerant decoding, so a configuration written by a build that did not
    // have one of these fields still loads instead of resetting the user's
    // answers to empty.
    enum CodingKeys: String, CodingKey {
        case offering, summary, rules
    }

    init(offering: String, summary: String, rules: [String]) {
        self.offering = offering
        self.summary = summary
        self.rules = rules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        offering = try container.decodeIfPresent(String.self, forKey: .offering) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        rules = try container.decodeIfPresent([String].self, forKey: .rules) ?? []
    }
}
