import UIKit

// MARK: - Theme

/// Colour palette for the keyboard.
///
/// The keyboard is dark-first, but it resolves correctly for light hosts too.
/// The host application expresses the appearance it wants through
/// `UITextDocumentProxy.keyboardAppearance`. Telegram, WhatsApp and Instagram
/// all set `.dark` while they are in dark mode, so that value is the primary
/// signal. When the host stays on `.default` we fall back to the trait
/// collection.
///
/// No Apple assets are used. Every value is an approximation authored here.
struct KeyboardTheme: Equatable {
    let isDark: Bool

    static func resolve(appearance: UIKeyboardAppearance, traits: UITraitCollection) -> KeyboardTheme {
        switch appearance {
        case .dark:
            return KeyboardTheme(isDark: true)
        case .light:
            return KeyboardTheme(isDark: false)
        default:
            return KeyboardTheme(isDark: traits.userInterfaceStyle == .dark)
        }
    }

    // Surfaces

    var background: UIColor {
        isDark ? .reply(0.106, 0.106, 0.114) : .reply(0.820, 0.831, 0.855)
    }

    /// Letter / number keys: slightly lighter than the backdrop.
    var letterKey: UIColor {
        isDark ? .reply(0.290, 0.290, 0.306) : .reply(1.000, 1.000, 1.000)
    }

    /// Shift, delete, plane switch, globe, language, return.
    var specialKey: UIColor {
        isDark ? .reply(0.173, 0.173, 0.188) : .reply(0.675, 0.690, 0.729)
    }

    /// Native behaviour: pressing a letter key darkens it to the special shade,
    /// pressing a special key lightens it to the letter shade.
    var letterKeyPressed: UIColor { specialKey }
    var specialKeyPressed: UIColor { letterKey }

    /// Shift / caps-lock in the engaged state.
    var engagedKey: UIColor {
        isDark ? .reply(0.937, 0.937, 0.949) : .reply(1.000, 1.000, 1.000)
    }

    var engagedKeyGlyph: UIColor { .reply(0.078, 0.078, 0.086) }

    // Text

    var primaryText: UIColor {
        isDark ? .reply(1.000, 1.000, 1.000) : .reply(0.000, 0.000, 0.000)
    }

    var secondaryText: UIColor {
        isDark ? UIColor(white: 0.92, alpha: 0.62) : UIColor(white: 0.20, alpha: 0.60)
    }

    var accent: UIColor {
        isDark ? .reply(0.039, 0.518, 1.000) : .reply(0.000, 0.478, 1.000)
    }

    // Composer surfaces
    //
    // Three surfaces, three jobs, and they must never be confused for each
    // other: the QUOTED source is recessed and low contrast, an EDITABLE FIELD
    // is raised and reads like a key, and the panel sits between them.

    /// Raised surface for a field the user types into.
    var fieldBackground: UIColor { letterKey }

    /// Recessed surface for the quoted source message.
    var quoteBackground: UIColor {
        isDark ? UIColor(white: 0.0, alpha: 0.22) : UIColor(white: 1.0, alpha: 0.42)
    }

    /// Quoted text: readable, but deliberately quieter than anything the user
    /// is about to send.
    var quoteText: UIColor {
        isDark ? UIColor(white: 1.0, alpha: 0.80) : UIColor(white: 0.0, alpha: 0.72)
    }

    var fieldBorder: UIColor {
        isDark ? UIColor(white: 1.0, alpha: 0.10) : UIColor(white: 0.0, alpha: 0.10)
    }

    /// Focus ring on the field the keys are currently editing.
    var fieldBorderFocused: UIColor { accent.withAlphaComponent(0.9) }

    /// Errors and the over-limit character counter.
    var destructive: UIColor {
        isDark ? .reply(1.000, 0.412, 0.380) : .reply(0.804, 0.153, 0.129)
    }

    // Action bar

    var actionBarKey: UIColor { specialKey }
    var actionBarKeyPressed: UIColor { letterKey }
    var panelBackground: UIColor { specialKey }

    var keyShadow: UIColor {
        isDark ? UIColor.black.withAlphaComponent(0.55) : UIColor.black.withAlphaComponent(0.32)
    }
}

private extension UIColor {
    static func reply(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: 1.0)
    }
}

// MARK: - Metrics

/// All geometry is derived from the live view width and the number of rows the
/// current layout needs, so the keyboard adapts to every iPhone width and to
/// the 5-row Kazakh layout without hard-coded frames.
struct KeyboardMetrics {
    let width: CGFloat
    /// Letter/number rows, excluding the bottom control row.
    let contentRowCount: Int
    /// Slots on the widest row of this page. Cyrillic layouts use 12, Latin and
    /// the symbol planes use 10, and the gap between keys is sized from it so a
    /// 12-column row does not spend a fifth of the screen on whitespace.
    var gridColumns: Int = 10

    var rowCount: Int { contentRowCount + 1 }

    var sidePadding: CGFloat { 3 }
    var topPadding: CGFloat { 5 }
    var bottomPadding: CGFloat { 5 }

    /// ONE gap for the whole page, derived from its widest row.
    ///
    /// It has to be page-wide rather than per-row: every row is solved against
    /// the same unit width, so giving rows their own gaps would put the columns
    /// out of alignment with each other. A 12-column Cyrillic row at the Latin
    /// 6pt gap spends 66pt of a 390pt screen on gaps and leaves 26.5pt keys;
    /// at 4pt it spends 44pt and leaves 28.3pt keys, which is the difference
    /// between mistyping `ъ` and not.
    var columnGap: CGFloat {
        if gridColumns >= 12 {
            return width >= 390 ? 4 : 3.5
        }
        return width >= 375 ? 6 : 5
    }

    var rowGap: CGFloat { rowCount >= 5 ? 7 : 11 }

    /// The shortest key this keyboard will ever draw. Below this the keys stop
    /// being comfortable to hit, and no amount of AI chrome above them is worth
    /// that: the AI area is what gives way, never this.
    static let minimumComfortableKeyHeight: CGFloat = 42

    /// Native iOS portrait keys are ~42-48pt tall.
    ///
    /// The 5-row Kazakh layout used to be scaled to 85.5% of the base height,
    /// which took a 46pt key down to 39pt - noticeably smaller than the same
    /// user's Russian keyboard and the single loudest complaint about this
    /// keyboard. The extra row is now paid for out of the row GAPS and 3pt of
    /// key height, with a hard floor underneath, so Kazakh keys stay in the
    /// same band as every other layout.
    var keyHeight: CGFloat {
        let base: CGFloat
        if width >= 410 {
            base = 48
        } else if width >= 375 {
            base = 46
        } else {
            base = 43
        }
        guard rowCount >= 5 else { return base }
        return max(Self.minimumComfortableKeyHeight, base - 3)
    }

    var typingHeight: CGFloat {
        topPadding + CGFloat(rowCount) * keyHeight
            + CGFloat(rowCount - 1) * rowGap + bottomPadding
    }

    var actionBarHeight: CGFloat { 42 }
    var actionBarGap: CGFloat { 3 }

    var cornerRadius: CGFloat { keyHeight >= 44 ? 6 : 5 }

    var availableRowWidth: CGFloat { width - sidePadding * 2 }

    /// Width of a single key on a row that spans `columns` evenly spaced slots.
    func unitWidth(columns: Int) -> CGFloat {
        guard columns > 0 else { return 0 }
        let gaps = CGFloat(columns - 1) * columnGap
        return max(1, (availableRowWidth - gaps) / CGFloat(columns))
    }

    /// Width of the fixed-size keys on the bottom row (plane switch, globe,
    /// language).
    var controlKeyWidth: CGFloat {
        min(52, max(38, (width * 0.108).rounded()))
    }

    var returnKeyWidth: CGFloat { (controlKeyWidth * 1.55).rounded() }

    func fontSize(for style: KeyFontStyle) -> CGFloat {
        switch style {
        case .character:
            return keyHeight >= 44 ? 23 : 21
        case .compactCharacter:
            // The tighter 12-column gap bought ~2pt of key width back, which
            // is enough to stop shrinking Cyrillic glyphs quite so far.
            return keyHeight >= 44 ? 20 : 19
        case .control:
            return 15
        case .space:
            return 15
        }
    }
}

enum KeyFontStyle {
    case character
    case compactCharacter
    case control
    case space
}
