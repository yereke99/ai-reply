import Foundation

/// The language the CONTAINING APP's interface is presented in.
///
/// Deliberately separate from `KeyboardLanguage`, which is the language of the
/// currently selected keyboard LAYOUT. The two are different by design: someone
/// with a Russian phone can be typing Kazakh, and the keyboard's own labels
/// have to follow the layout while the app follows the system (or an explicit
/// override). Collapsing them into one type would force one of those to be
/// wrong.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case russian = "ru"
    case kazakh = "kk"
    case uzbek = "uz"

    var id: String { rawValue }

    /// Locale used for speech recognition and for formatting.
    var localeIdentifier: String {
        switch self {
        case .english: return "en_US"
        case .russian: return "ru_RU"
        case .kazakh:  return "kk_KZ"
        case .uzbek:   return "uz_UZ"
        }
    }

    /// The language's name in that language. Never localized into another one:
    /// a language picker that says "Kazakh" to a Kazakh speaker is a worse
    /// picker than one that says "Қазақша".
    var nativeName: String {
        switch self {
        case .english: return "English"
        case .russian: return "Русский"
        case .kazakh:  return "Қазақша"
        case .uzbek:   return "O‘zbekcha"
        }
    }

    /// The keyboard LAYOUT that corresponds to this interface language.
    ///
    /// Used where the product UI has to speak the same vocabulary the keyboard
    /// uses for templates and errors. It is a mapping, not an equivalence: the
    /// app language never changes which layout the user is typing on.
    var keyboardLanguage: KeyboardLanguage {
        switch self {
        case .english: return .english
        case .russian: return .russian
        case .kazakh:  return .kazakh
        case .uzbek:   return .english
        }
    }

    /// The app language implied by the device's own preferences, used when the
    /// user has not chosen an explicit override.
    static var systemDefault: AppLanguage {
        for identifier in Locale.preferredLanguages {
            let code = String(identifier.prefix(2)).lowercased()
            if let match = AppLanguage(rawValue: code) { return match }
        }
        return .english
    }
}

extension ReplyTemplate {
    /// Name for display in product UI, which follows the APP language.
    ///
    /// Distinct from `displayName(language:)`, which takes a keyboard layout.
    /// Both exist because both questions are asked: the keys follow the layout,
    /// the product UI follows the app.
    func displayName(appLanguage: AppLanguage) -> String {
        if appLanguage == .uzbek,
           customName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            switch relationship {
            case .friend: return "Do‘st"
            case .client: return "Mijoz"
            case .business: return "Biznes"
            case .work: return "Ish"
            case .custom: return "Boshqa"
            }
        }
        return displayName(language: appLanguage.keyboardLanguage)
    }
}
