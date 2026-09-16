import Foundation

/// The three layouts this keyboard ships. The selected value drives BOTH the
/// character layout and every piece of UI text, so the two can never drift
/// apart (see `KeyboardStrings`).
enum KeyboardLanguage: String, CaseIterable, Hashable {
    case english = "en"
    case russian = "ru"
    case kazakh = "kk"

    var next: KeyboardLanguage {
        switch self {
        case .english: return .russian
        case .russian: return .kazakh
        case .kazakh: return .english
        }
    }

    /// Number of slots the widest row of this layout uses. Every row is sized
    /// against this so the rows line up on a single grid.
    var gridColumns: Int {
        switch self {
        case .english: return 10
        case .russian, .kazakh: return 12
        }
    }

    /// Rows of letters, top to bottom. The last row is rendered with shift in
    /// front of it and delete after it.
    ///
    /// English: standard 10 / 9 / 7 QWERTY.
    ///
    /// Russian: 12 / 12 / 9. This is the standard iOS ЙЦУКЕН layout with one
    /// deliberate change - `ё` sits at the end of the second row instead of
    /// behind a long press on `е`. Every Cyrillic letter is therefore visible,
    /// and the third row keeps only 9 letters so shift and delete stay wide
    /// (~43pt) instead of shrinking to letter width.
    ///
    /// Kazakh: the Russian rows plus a dedicated top row carrying all nine
    /// Kazakh-specific letters. Nothing is hidden behind a gesture.
    var letterRows: [[String]] {
        switch self {
        case .english:
            return [
                ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
                ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
                ["z", "x", "c", "v", "b", "n", "m"]
            ]
        case .russian:
            return KeyboardLanguage.cyrillicRows
        case .kazakh:
            return [["ә", "ғ", "қ", "ң", "ө", "ұ", "ү", "һ", "і"]]
                + KeyboardLanguage.cyrillicRows
        }
    }

    private static let cyrillicRows: [[String]] = [
        ["й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х", "ъ"],
        ["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э", "ё"],
        ["я", "ч", "с", "м", "и", "т", "ь", "б", "ю"]
    ]

    /// Rows that should be stretched edge to edge rather than centred on the
    /// grid. The Kazakh letter row has only nine keys; spreading it across the
    /// full width gives comfortably wide keys instead of a narrow centred block.
    func rowFillsWidth(at index: Int) -> Bool {
        self == .kazakh && index == 0
    }
}

// MARK: - Persistence

/// Remembers the chosen layout between keyboard sessions.
///
/// Now stored in the App Group container rather than the extension's own one,
/// so the containing app can show and change the keyboard's layout too. The
/// previous value is migrated on first read (see `SharedSettings`), so an
/// existing install does not reset to English.
enum KeyboardLanguageStore {

    static func load() -> KeyboardLanguage {
        guard let raw = SharedSettings.shared.keyboardLanguageCode,
              let language = KeyboardLanguage(rawValue: raw) else {
            return .english
        }
        return language
    }

    static func save(_ language: KeyboardLanguage) {
        SharedSettings.shared.setKeyboardLanguageCode(language.rawValue)
    }

    static func saveAsync(_ language: KeyboardLanguage) {
        DispatchQueue.global(qos: .utility).async {
            save(language)
        }
    }
}

// MARK: - Non-letter planes

enum KeyboardPlane: Hashable {
    case letters
    case numbers
    case symbols

    var rows: [[String]] {
        switch self {
        case .letters:
            return []
        case .numbers:
            return [
                ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
                ["-", "/", ":", ";", "(", ")", "₸", "&", "@", "\""],
                [".", ",", "?", "!", "'"]
            ]
        case .symbols:
            return [
                ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
                ["_", "\\", "|", "~", "<", ">", "$", "€", "£", "¥"],
                [".", ",", "?", "!", "'"]
            ]
        }
    }

    var gridColumns: Int { 10 }
}
