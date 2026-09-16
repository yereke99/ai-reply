import UIKit

protocol TemplateBarViewDelegate: AnyObject {
    func templateBar(_ bar: TemplateBarView, didSelectTemplateID id: String)
    func templateBarDidRequestNewTemplate(_ bar: TemplateBarView)
}

/// The only thing the row needs to draw one template: an identifier to report
/// back and a name to show.
///
/// Deliberately NOT a `ReplyTemplate`. The bar has no business holding a user's
/// instructions, business description or rules, and keeping it to two strings is
/// what lets the row be drawn from the App Group summary cache on the very first
/// frame, before the full configuration file has been read.
struct TemplateChip: Equatable {
    let id: String
    let name: String
}

/// The horizontal template selector that sits above the keys.
///
/// SIZE IS THE POINT. It is 36pt tall and scrolls horizontally, so however many
/// templates a user creates, the row's height never changes and the keys below
/// never shrink. An earlier version of this keyboard let its own chrome eat the
/// typing area; the geometry here makes that impossible rather than merely
/// discouraged.
///
/// PERFORMANCE. Pills are built once per template set and then reused. Nothing
/// in this view is touched on a keypress: it is not in the typing path at all,
/// and a keystroke never causes it to lay out.
final class TemplateBarView: UIView {

    weak var delegate: TemplateBarViewDelegate?

    static let preferredHeight: CGFloat = 36

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let hintLabel = UILabel()

    private var theme = KeyboardTheme(isDark: true)
    private var strings = AIReplyStrings.forLanguage(.english)
    private var chips: [TemplateChip] = []
    private var pills: [UIButton] = []

    // MARK: Init

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private func build() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        // Otherwise a horizontal drag that starts on a pill is swallowed by the
        // button and the row feels stuck.
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        addSubview(scrollView)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        scrollView.addSubview(stack)

        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        hintLabel.textAlignment = .center
        hintLabel.adjustsFontSizeToFitWidth = true
        hintLabel.minimumScaleFactor = 0.8
        hintLabel.isHidden = true
        addSubview(hintLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

            hintLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            hintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            hintLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    // MARK: Configuration

    /// - Parameter uiLanguage: the APP's language, which is what the product
    ///   vocabulary follows. Changing the keyboard LAYOUT does not reach here,
    ///   which is the point: the chips stay in the user's own language while
    ///   they switch layouts to type.
    func configure(theme: KeyboardTheme, uiLanguage: AppLanguage) {
        self.theme = theme
        self.strings = AIReplyStrings.forLanguage(uiLanguage)
        hintLabel.textColor = theme.secondaryText
        hintLabel.text = strings.chooseTemplate
        if let addPill = pills.last, pills.count > chips.count {
            addPill.accessibilityLabel = strings.addTemplate
        }
        restyle()
    }

    /// Replaces the row's contents. Only rebuilds when they actually differ, so
    /// a keyboard reappearing with an unchanged configuration - or a layout
    /// switch, which does not touch this row at all - does no work.
    ///
    /// When only the NAMES changed (an app-language switch), the existing
    /// buttons are relabelled in place rather than thrown away: rebuilding the
    /// row was a visible hitch.
    func setChips(_ newChips: [TemplateChip]) {
        guard newChips != chips else { return }

        let sameSet = newChips.count == chips.count
            && zip(newChips, chips).allSatisfy { $0.id == $1.id }
        chips = newChips

        if sameSet {
            for (index, pill) in pills.enumerated() where index < chips.count {
                applyTitle(chips[index].name, to: pill)
            }
            return
        }
        rebuildPills()
    }

    private func rebuildPills() {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        pills.removeAll(keepingCapacity: true)

        for (index, chip) in chips.enumerated() {
            let pill = makePill()
            pill.tag = index
            applyTitle(chip.name, to: pill)
            pill.addTarget(self, action: #selector(templateTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(pill)
            pills.append(pill)
        }

        let addPill = makePill()
        applySymbol("plus", to: addPill)
        addPill.accessibilityLabel = strings.addTemplate
        addPill.widthAnchor.constraint(equalToConstant: 40).isActive = true
        addPill.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        stack.addArrangedSubview(addPill)
        pills.append(addPill)

        hintLabel.isHidden = !chips.isEmpty
        restyle()
    }

    private func makePill() -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false

        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 13, bottom: 0, trailing: 13)
        configuration.background.cornerRadius = 14
        button.configuration = configuration

        // Highlight is handled here rather than by swapping `backgroundColor`,
        // because a configured button rewrites its own background on every
        // state change and would undo a direct assignment.
        button.configurationUpdateHandler = { [weak self] button in
            guard let self else { return }
            button.configuration?.background.backgroundColor =
                button.isHighlighted ? self.theme.specialKey : self.theme.letterKey
        }

        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    private func applyTitle(_ title: String, to button: UIButton) {
        var attributes = AttributeContainer()
        attributes.font = .systemFont(ofSize: 13.5, weight: .medium)
        button.configuration?.image = nil
        button.configuration?.attributedTitle = AttributedString(title, attributes: attributes)
        button.titleLabel?.lineBreakMode = .byTruncatingTail
    }

    private func applySymbol(_ name: String, to button: UIButton) {
        button.configuration?.attributedTitle = nil
        button.configuration?.image = UIImage(
            systemName: name,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        )
    }

    private func restyle() {
        for pill in pills {
            pill.configuration?.background.backgroundColor = theme.letterKey
            pill.configuration?.baseForegroundColor = theme.primaryText
            pill.tintColor = theme.primaryText
        }
    }

    // MARK: Actions

    @objc private func templateTapped(_ sender: UIButton) {
        guard chips.indices.contains(sender.tag) else { return }
        delegate?.templateBar(self, didSelectTemplateID: chips[sender.tag].id)
    }

    @objc private func addTapped() {
        delegate?.templateBarDidRequestNewTemplate(self)
    }
}
