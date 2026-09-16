import UIKit

/// The KEY LABELS, keyed by the *keyboard* language.
///
/// `Localizable.strings` + `NSLocalizedString` deliberately are not used here:
/// they resolve against the device/system language, while the requirement is
/// that the labels follow the layout the user currently has selected. A user
/// with an English phone typing Kazakh must see "Жауап беру".
///
/// This type covers the keys themselves. Everything the AI reply flow says -
/// actions, status and errors - lives in `AIReplyStrings`, which is in `Shared`
/// so the host app shows the user the same sentences. Adding a language means
/// adding one value to each.
struct KeyboardStrings {

    // Keys
    let languageBadge: String
    let spaceKey: String
    let returnKey: String
    let sendKey: String
    let searchKey: String
    let goKey: String
    let doneKey: String

    static func forLanguage(_ language: KeyboardLanguage) -> KeyboardStrings {
        switch language {
        case .english:  return .english
        case .russian:  return .russian
        case .kazakh:   return .kazakh
        }
    }

    private static let english = KeyboardStrings(
        languageBadge: "EN",
        spaceKey: "space",
        returnKey: "return",
        sendKey: "send",
        searchKey: "search",
        goKey: "go",
        doneKey: "done"
    )

    private static let russian = KeyboardStrings(
        languageBadge: "РУ",
        spaceKey: "пробел",
        returnKey: "ввод",
        sendKey: "отпр.",
        searchKey: "поиск",
        goKey: "перейти",
        doneKey: "готово"
    )

    private static let kazakh = KeyboardStrings(
        languageBadge: "ҚАЗ",
        spaceKey: "бос орын",
        returnKey: "енгізу",
        sendKey: "жіберу",
        searchKey: "іздеу",
        goKey: "өту",
        doneKey: "дайын"
    )

    /// Label for the return key, following the host field's `returnKeyType`.
    func returnLabel(for type: UIReturnKeyType) -> String {
        switch type {
        case .send:     return sendKey
        case .search:   return searchKey
        case .google, .yahoo: return searchKey
        case .go:       return goKey
        case .done:     return doneKey
        default:        return returnKey
        }
    }

    /// Whether the return key should be tinted, as it is on the system keyboard
    /// for confirming actions.
    static func returnKeyIsProminent(_ type: UIReturnKeyType) -> Bool {
        switch type {
        case .send, .go, .search, .done, .google, .yahoo:
            return true
        default:
            return false
        }
    }
}
