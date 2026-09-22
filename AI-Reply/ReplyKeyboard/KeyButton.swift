import UIKit

// MARK: - Key model

enum KeyboardKey: Equatable {
    case character(String)
    case shift
    case backspace
    case plane(KeyboardPlaneTarget)
    case globe
    case language
    case space
    case ret

    var isCharacter: Bool {
        if case .character = self { return true }
        return false
    }

    /// Keys whose only job is to put characters somewhere. When there is
    /// nowhere to put them - the composer is showing a result, or a request is
    /// in flight - these are the keys that must stay silent, while shift, the
    /// plane switch and the language key keep clicking because they still do
    /// something visible.
    var editsText: Bool {
        switch self {
        case .character, .backspace, .space, .ret:
            return true
        case .shift, .plane, .globe, .language:
            return false
        }
    }

    /// Keys that fire immediately on touch-down, matching the system keyboard.
    /// Keys that rebuild the whole keyboard fire on touch-up instead, so the
    /// button is never torn out from under the finger.
    var firesOnTouchDown: Bool {
        switch self {
        case .character, .backspace, .space, .ret, .shift:
            return true
        case .plane, .globe, .language:
            return false
        }
    }
}

enum KeyboardPlaneTarget: Equatable {
    case letters
    case numbers
    case symbols

    var plane: KeyboardPlane {
        switch self {
        case .letters: return .letters
        case .numbers: return .numbers
        case .symbols: return .symbols
        }
    }

    var title: String {
        switch self {
        case .letters: return "ABC"
        case .numbers: return "123"
        case .symbols: return "#+="
        }
    }
}

enum KeyVisualStyle {
    case letter
    case special
    case engaged
    case prominent
}

// MARK: - Button

final class KeyButton: UIButton {

    let key: KeyboardKey

    private var normalBackground: UIColor = .clear
    private var pressedBackground: UIColor = .clear
    private var lastTextConfiguration: (text: String, size: CGFloat, weight: UIFont.Weight)?
    private var lastSymbolConfiguration: (name: String, pointSize: CGFloat, weight: UIImage.SymbolWeight)?

    /// Negative value grows the touch target beyond the drawn key. Used for the
    /// narrow Cyrillic shift/delete keys.
    var touchInset: CGFloat = 0

    private var shadowPathBounds: CGRect = .null
    private var shadowPathRadius: CGFloat = -1

    init(key: KeyboardKey) {
        self.key = key
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerCurve = .continuous
        layer.shadowOpacity = 1
        layer.shadowRadius = 0
        layer.shadowOffset = CGSize(width: 0, height: 1)
        titleLabel?.textAlignment = .center
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.62
        titleLabel?.baselineAdjustment = .alignCenters
        titleLabel?.lineBreakMode = .byClipping
        imageView?.contentMode = .scaleAspectFit
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            backgroundColor = isHighlighted ? pressedBackground : normalBackground
        }
    }

    /// PERFORMANCE. A layer with a shadow and no `shadowPath` makes Core
    /// Animation derive the shadow shape from the layer's own alpha channel on
    /// every bounds change - one offscreen pass per key. With ~40 keys on
    /// screen that cost is paid on every layout and every animation frame.
    /// Handing it an explicit path removes the offscreen pass entirely and the
    /// drawn result is identical: `shadowRadius` is 0 and the offset is 1pt
    /// down, so this is a hard bottom edge, not a blur.
    override func layoutSubviews() {
        super.layoutSubviews()
        let radius = layer.cornerRadius
        guard bounds != shadowPathBounds || radius != shadowPathRadius else { return }
        shadowPathBounds = bounds
        shadowPathRadius = radius
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: radius).cgPath
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard touchInset != 0 else {
            return super.point(inside: point, with: event)
        }
        return bounds.insetBy(dx: touchInset, dy: 0).contains(point)
    }

    func apply(style: KeyVisualStyle, theme: KeyboardTheme, metrics: KeyboardMetrics) {
        layer.cornerRadius = metrics.cornerRadius
        layer.shadowColor = theme.keyShadow.cgColor

        switch style {
        case .letter:
            normalBackground = theme.letterKey
            pressedBackground = theme.letterKeyPressed
            tintColor = theme.primaryText
            setTitleColor(theme.primaryText, for: .normal)
        case .special:
            normalBackground = theme.specialKey
            pressedBackground = theme.specialKeyPressed
            tintColor = theme.primaryText
            setTitleColor(theme.primaryText, for: .normal)
        case .engaged:
            normalBackground = theme.engagedKey
            pressedBackground = theme.engagedKey
            tintColor = theme.engagedKeyGlyph
            setTitleColor(theme.engagedKeyGlyph, for: .normal)
        case .prominent:
            normalBackground = theme.accent
            pressedBackground = theme.accent.withAlphaComponent(0.72)
            tintColor = .white
            setTitleColor(.white, for: .normal)
        }

        backgroundColor = isHighlighted ? pressedBackground : normalBackground
    }

    /// PERFORMANCE. Shift and caps-lock rewrite the title of every letter key
    /// at once - about 30 buttons on a Cyrillic layout, and the user can tap
    /// shift as fast as they can type. Two things are avoided per button:
    /// re-resolving a `UIFont` that has not changed, and clearing an image that
    /// was never set. Neither is expensive alone; thirty of each, on the main
    /// thread, inside a tap handler, is what a dropped frame is made of.
    func setText(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular) {
        let previous = lastTextConfiguration
        if let previous,
           previous.text == text,
           abs(previous.size - size) < 0.1,
           previous.weight == weight {
            return
        }

        let fontChanged = previous.map { abs($0.size - size) >= 0.1 || $0.weight != weight } ?? true
        let hadSymbol = lastSymbolConfiguration != nil

        lastTextConfiguration = (text, size, weight)
        lastSymbolConfiguration = nil

        if hadSymbol { setImage(nil, for: .normal) }
        setTitle(text, for: .normal)
        if fontChanged { titleLabel?.font = KeyFontCache.font(size: size, weight: weight) }
    }

    func setSymbol(_ name: String, pointSize: CGFloat, weight: UIImage.SymbolWeight = .regular) {
        if let current = lastSymbolConfiguration,
           current.name == name,
           abs(current.pointSize - pointSize) < 0.1,
           current.weight == weight {
            return
        }
        let hadText = lastTextConfiguration != nil
        lastSymbolConfiguration = (name, pointSize, weight)
        lastTextConfiguration = nil
        if hadText { setTitle(nil, for: .normal) }
        setImage(KeySymbolCache.image(name: name, pointSize: pointSize, weight: weight), for: .normal)
    }
}

// MARK: - Caches

/// Fonts and SF Symbol images, resolved once per distinct configuration.
///
/// Both `UIFont.systemFont` and `UIImage(systemName:)` do real work on a miss -
/// a descriptor lookup and an asset-catalog render respectively. A keyboard
/// asks for the same handful of sizes over and over across rebuilds, layout
/// changes and shift toggles, so a dictionary is a much better fit than a fresh
/// lookup every time. Both are touched only from the main thread.
enum KeyFontCache {
    private struct Key: Hashable {
        let size: CGFloat
        let weight: CGFloat
    }
    private static var cache: [Key: UIFont] = [:]

    static func font(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let key = Key(size: size.rounded(), weight: weight.rawValue)
        if let cached = cache[key] { return cached }
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        cache[key] = font
        return font
    }
}

enum KeySymbolCache {
    private struct Key: Hashable {
        let name: String
        let pointSize: CGFloat
        let weight: Int
    }
    private static var cache: [Key: UIImage] = [:]

    static func image(name: String, pointSize: CGFloat, weight: UIImage.SymbolWeight) -> UIImage? {
        let key = Key(name: name, pointSize: pointSize.rounded(), weight: weight.rawValue)
        if let cached = cache[key] { return cached }
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let image = UIImage(systemName: name, withConfiguration: configuration) else { return nil }
        cache[key] = image
        return image
    }
}

// MARK: - Spacer

/// Zero-content view used to centre rows that hold fewer keys than the grid.
final class KeyRowSpacer: UIView {
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        backgroundColor = .clear
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }
}
