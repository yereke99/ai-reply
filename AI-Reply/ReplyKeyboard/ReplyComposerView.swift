import UIKit

protocol ReplyComposerViewDelegate: AnyObject {
    func composerDidTapClose(_ composer: ReplyComposerView)
    func composerDidTapInsert(_ composer: ReplyComposerView)
    func composerDidTapRegenerate(_ composer: ReplyComposerView)
    func composerDidTapTemplateChip(_ composer: ReplyComposerView)
    func composerDidChangeHeight(_ composer: ReplyComposerView)
    func composer(_ composer: ReplyComposerView, didResolveConflictWith choice: HostTextChoice)
}

/// How an insertion should treat text already in the host field.
enum HostTextChoice {
    case replace
    case append
    case cancel
}

/// The reply composer.
///
/// Three texts are kept deliberately apart:
///
/// * the SOURCE MESSAGE - what the user copied. Read-only, two lines unless
///   expanded, and never seeded into the draft. What the other person wrote
///   must never silently become what this user sends.
/// * the REPLY DRAFT - the AI's answer, which becomes the user's the moment it
///   appears. The only value that can reach the host application.
/// * the TEMPLATE CHIP - which relationship this reply is being written for,
///   shown collapsed so the draft gets the space.
///
/// Typing does not depend on the draft view holding first responder: every edit
/// goes through `insertText`/`deleteBackward`, which mutate the storage and
/// move the caret explicitly. First responder is still requested, because when
/// the system grants it inside an extension the user gets UIKit's own caret,
/// selection handles and magnifier for free. When it is not granted,
/// `fallbackCaret` draws the insertion point instead.
final class ReplyComposerView: UIView {

    weak var delegate: ReplyComposerViewDelegate?

    enum Mode {
        case generating
        case editing
        case conflict
    }

    // MARK: Model

    private(set) var sourceMessage: String = ""
    private(set) var mode: Mode = .editing

    var replyDraft: String { draftTextView.text ?? "" }

    var hasUsableDraft: Bool {
        !replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Views

    private let container = UIView()

    // Header
    private let templateChip = UIButton(type: .system)
    private let regenerateButton = UIButton(type: .system)
    private let insertButton = UIButton(type: .system)

    // Body
    private let sourceLabel = UILabel()
    private let divider = UIView()
    private let draftTextView = UITextView()
    private let placeholderLabel = UILabel()
    private let fallbackCaret = UIView()

    // Loading
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let loadingLabel = UILabel()

    // Conflict
    private let conflictLabel = UILabel()
    private let replaceButton = UIButton(type: .system)
    private let appendButton = UIButton(type: .system)
    private let conflictCancelButton = UIButton(type: .system)
    private let conflictStack = UIStackView()

    // MARK: Layout state

    private var sourceHeight: NSLayoutConstraint?
    private var draftHeight: NSLayoutConstraint?

    private var theme = KeyboardTheme(isDark: true)
    private var strings = AIReplyStrings.forLanguage(.english)
    private var layoutWidth: CGFloat = 0
    private var isSourceExpanded = false
    private var caretTimer: Timer?

    private let sourceFont = UIFont.systemFont(ofSize: 12.5)
    private let draftFont = UIFont.systemFont(ofSize: 15)

    private var measuredSourceHeight: CGFloat = 30
    private var measuredDraftHeight: CGFloat = 36

    private let headerHeight: CGFloat = 30

    /// Height this view needs right now. The controller adds it to the keyboard
    /// height, so the keys keep their full size in every state.
    var preferredHeight: CGFloat {
        switch mode {
        case .conflict:
            return (headerHeight + measuredSourceHeight + 44 + 20).rounded(.up)
        case .generating, .editing:
            return (headerHeight + measuredSourceHeight + measuredDraftHeight + 22).rounded(.up)
        }
    }

    private var collapsedSourceLines: Int { 2 }
    private var expandedSourceLines: Int { 4 }
    private var minimumDraftHeight: CGFloat { 36 }
    private var maximumDraftHeight: CGFloat { 60 }

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

    deinit {
        caretTimer?.invalidate()
    }

    private func build() {
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.cornerRadius = 10
        container.layer.cornerCurve = .continuous
        addSubview(container)

        buildHeader()
        buildBody()
        buildLoading()
        buildConflict()
        activateConstraints()
    }

    private func buildHeader() {
        // The collapsed template selector. Tapping it reopens the full row, so
        // the user is never locked into a template they picked by mistake.
        templateChip.translatesAutoresizingMaskIntoConstraints = false
        var chip = UIButton.Configuration.plain()
        chip.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 8)
        chip.background.cornerRadius = 12
        chip.imagePlacement = .trailing
        chip.imagePadding = 5
        chip.image = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 8, weight: .bold)
        )
        templateChip.configuration = chip
        templateChip.addTarget(self, action: #selector(templateChipTapped), for: .touchUpInside)
        container.addSubview(templateChip)

        regenerateButton.translatesAutoresizingMaskIntoConstraints = false
        var regen = UIButton.Configuration.plain()
        regen.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        regen.image = UIImage(
            systemName: "arrow.clockwise",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        )
        regen.background.cornerRadius = 13
        regenerateButton.configuration = regen
        regenerateButton.addTarget(self, action: #selector(regenerateTapped), for: .touchUpInside)
        container.addSubview(regenerateButton)

        insertButton.translatesAutoresizingMaskIntoConstraints = false
        var insert = UIButton.Configuration.plain()
        insert.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        insert.background.cornerRadius = 13
        insertButton.configuration = insert
        insertButton.addTarget(self, action: #selector(insertTapped), for: .touchUpInside)
        container.addSubview(insertButton)
    }

    private func buildBody() {
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false
        sourceLabel.font = sourceFont
        sourceLabel.numberOfLines = collapsedSourceLines
        sourceLabel.lineBreakMode = .byTruncatingTail
        sourceLabel.isUserInteractionEnabled = true
        sourceLabel.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(toggleSourceExpansion))
        )
        container.addSubview(sourceLabel)

        divider.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(divider)

        draftTextView.translatesAutoresizingMaskIntoConstraints = false
        draftTextView.font = draftFont
        draftTextView.backgroundColor = .clear
        draftTextView.isEditable = true
        draftTextView.isScrollEnabled = true
        draftTextView.alwaysBounceVertical = false
        draftTextView.textContainerInset = UIEdgeInsets(top: 7, left: 0, bottom: 7, right: 0)
        draftTextView.textContainer.lineFragmentPadding = 0
        draftTextView.autocorrectionType = .no
        draftTextView.spellCheckingType = .no
        draftTextView.smartQuotesType = .no
        draftTextView.smartDashesType = .no
        // Never let the system summon a keyboard for our own field: this
        // keyboard IS the keyboard.
        draftTextView.inputView = UIView()
        draftTextView.inputAccessoryView = nil
        draftTextView.delegate = self
        container.addSubview(draftTextView)

        let draftTap = UITapGestureRecognizer(target: self, action: #selector(draftTapped(_:)))
        draftTap.cancelsTouchesInView = false
        draftTextView.addGestureRecognizer(draftTap)

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.font = draftFont
        placeholderLabel.isUserInteractionEnabled = false
        container.addSubview(placeholderLabel)

        // Frame-driven on purpose: its position comes from caretRect(for:).
        fallbackCaret.translatesAutoresizingMaskIntoConstraints = true
        fallbackCaret.isUserInteractionEnabled = false
        fallbackCaret.isHidden = true
        fallbackCaret.layer.cornerRadius = 1
        draftTextView.addSubview(fallbackCaret)
    }

    private func buildLoading() {
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        container.addSubview(spinner)

        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingLabel.font = .systemFont(ofSize: 13)
        loadingLabel.isHidden = true
        container.addSubview(loadingLabel)
    }

    private func buildConflict() {
        conflictLabel.translatesAutoresizingMaskIntoConstraints = false
        conflictLabel.font = .systemFont(ofSize: 12, weight: .medium)
        conflictLabel.numberOfLines = 2
        conflictLabel.adjustsFontSizeToFitWidth = true
        conflictLabel.minimumScaleFactor = 0.8
        container.addSubview(conflictLabel)

        conflictStack.translatesAutoresizingMaskIntoConstraints = false
        conflictStack.axis = .horizontal
        conflictStack.distribution = .fillEqually
        conflictStack.spacing = 8
        container.addSubview(conflictStack)

        for (button, action) in [
            (replaceButton, #selector(replaceTapped)),
            (appendButton, #selector(appendTapped)),
            (conflictCancelButton, #selector(conflictCancelTapped))
        ] {
            var configuration = UIButton.Configuration.plain()
            configuration.background.cornerRadius = 13
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6)
            button.configuration = configuration
            button.addTarget(self, action: action, for: .touchUpInside)
            button.heightAnchor.constraint(equalToConstant: 30).isActive = true
            conflictStack.addArrangedSubview(button)
        }
    }

    private func activateConstraints() {
        let source = sourceLabel.heightAnchor.constraint(equalToConstant: measuredSourceHeight)
        let draft = draftTextView.heightAnchor.constraint(equalToConstant: measuredDraftHeight)
        sourceHeight = source
        draftHeight = draft

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            container.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),

            templateChip.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            templateChip.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            templateChip.heightAnchor.constraint(equalToConstant: 24),
            templateChip.trailingAnchor.constraint(lessThanOrEqualTo: regenerateButton.leadingAnchor, constant: -8),

            regenerateButton.trailingAnchor.constraint(equalTo: insertButton.leadingAnchor, constant: -6),
            regenerateButton.centerYAnchor.constraint(equalTo: templateChip.centerYAnchor),
            regenerateButton.widthAnchor.constraint(equalToConstant: 30),
            regenerateButton.heightAnchor.constraint(equalToConstant: 26),

            insertButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            insertButton.centerYAnchor.constraint(equalTo: templateChip.centerYAnchor),
            insertButton.heightAnchor.constraint(equalToConstant: 26),

            sourceLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            sourceLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            sourceLabel.topAnchor.constraint(equalTo: templateChip.bottomAnchor, constant: 3),
            source,

            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            divider.topAnchor.constraint(equalTo: sourceLabel.bottomAnchor, constant: 4),
            divider.heightAnchor.constraint(equalToConstant: 0.5),

            draftTextView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            draftTextView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            draftTextView.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 1),
            draft,

            placeholderLabel.leadingAnchor.constraint(equalTo: draftTextView.leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: draftTextView.trailingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: draftTextView.topAnchor, constant: 7),

            spinner.leadingAnchor.constraint(equalTo: draftTextView.leadingAnchor),
            spinner.centerYAnchor.constraint(equalTo: draftTextView.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 18),

            loadingLabel.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 8),
            loadingLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -10),
            loadingLabel.centerYAnchor.constraint(equalTo: spinner.centerYAnchor),

            conflictLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            conflictLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            conflictLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 4),

            conflictStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            conflictStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            conflictStack.topAnchor.constraint(equalTo: conflictLabel.bottomAnchor, constant: 5)
        ])
    }

    // MARK: Configuration

    /// - Parameter uiLanguage: the APP's language. The composer is product UI,
    ///   so every label in it follows the app, not the layout being typed on.
    func configure(theme: KeyboardTheme, uiLanguage: AppLanguage) {
        self.theme = theme
        self.strings = AIReplyStrings.forLanguage(uiLanguage)

        container.backgroundColor = theme.panelBackground

        templateChip.configuration?.background.backgroundColor = theme.letterKey
        templateChip.configuration?.baseForegroundColor = theme.primaryText
        templateChip.tintColor = theme.primaryText

        regenerateButton.configuration?.background.backgroundColor = theme.letterKey
        regenerateButton.configuration?.baseForegroundColor = theme.primaryText
        regenerateButton.tintColor = theme.primaryText
        regenerateButton.accessibilityLabel = self.strings.regenerate

        applyInsertTitle()

        sourceLabel.textColor = theme.secondaryText
        divider.backgroundColor = theme.secondaryText.withAlphaComponent(0.22)
        draftTextView.textColor = theme.primaryText
        draftTextView.tintColor = theme.accent
        draftTextView.indicatorStyle = theme.isDark ? .white : .black
        placeholderLabel.textColor = theme.secondaryText
        placeholderLabel.text = self.strings.draftTitle
        fallbackCaret.backgroundColor = theme.accent

        spinner.color = theme.secondaryText
        loadingLabel.textColor = theme.secondaryText
        loadingLabel.text = self.strings.generating

        conflictLabel.textColor = theme.primaryText
        conflictLabel.text = self.strings.hostFieldNotEmpty
        styleConflictButton(replaceButton, title: self.strings.replaceExisting, prominent: true)
        styleConflictButton(appendButton, title: self.strings.appendToExisting, prominent: true)
        styleConflictButton(conflictCancelButton, title: self.strings.keepTyping, prominent: false)

        refreshInsertState()
    }

    private func applyInsertTitle() {
        var attributes = AttributeContainer()
        attributes.font = .systemFont(ofSize: 13, weight: .semibold)
        insertButton.configuration?.attributedTitle = AttributedString(strings.insert, attributes: attributes)
        insertButton.accessibilityLabel = strings.insert
    }

    private func styleConflictButton(_ button: UIButton, title: String, prominent: Bool) {
        var attributes = AttributeContainer()
        attributes.font = .systemFont(ofSize: 13, weight: .semibold)
        button.configuration?.attributedTitle = AttributedString(title, attributes: attributes)
        button.configuration?.background.backgroundColor = prominent ? theme.accent : theme.letterKey
        button.configuration?.baseForegroundColor = prominent ? .white : theme.primaryText
        button.accessibilityLabel = title
    }

    /// Re-measures for the given keyboard width. Safe to call repeatedly.
    func layout(forWidth width: CGFloat) {
        guard width > 0, abs(width - layoutWidth) > 0.5 else { return }
        layoutWidth = width
        recalculate()
    }

    // MARK: Session

    /// Opens the composer for a message, before any reply exists.
    func begin(sourceMessage: String, templateName: String) {
        self.sourceMessage = sourceMessage
        sourceLabel.text = sourceMessage
        isSourceExpanded = false
        sourceLabel.numberOfLines = collapsedSourceLines
        setTemplateName(templateName)
        draftTextView.text = ""
        refreshPlaceholder()
        setMode(.generating)
        recalculate()
    }

    func setTemplateName(_ name: String) {
        var attributes = AttributeContainer()
        attributes.font = .systemFont(ofSize: 12.5, weight: .semibold)
        templateChip.configuration?.attributedTitle = AttributedString(name, attributes: attributes)
        templateChip.accessibilityLabel = name
    }

    /// Installs a generated reply and hands control to the user.
    func showDraft(_ draft: String) {
        draftTextView.text = draft
        let end = (draft as NSString).length
        draftTextView.selectedRange = NSRange(location: end, length: 0)
        setMode(.editing)
        refreshPlaceholder()
        refreshInsertState()
        recalculate()
        startCaretBlink()
        // Requesting first responder is a bonus, never a requirement.
        _ = draftTextView.becomeFirstResponder()
        updateFallbackCaret()
    }

    /// Returns to the editing state with whatever draft is already there, used
    /// when a regeneration fails and the previous draft should survive.
    func endGenerating() {
        setMode(.editing)
        refreshInsertState()
        recalculate()
    }

    func beginRegenerating() {
        setMode(.generating)
        recalculate()
    }

    func showConflictChoice() {
        setMode(.conflict)
        recalculate()
    }

    func end() {
        stopCaretBlink()
        if draftTextView.isFirstResponder { draftTextView.resignFirstResponder() }
        draftTextView.text = ""
        sourceMessage = ""
        sourceLabel.text = nil
        isSourceExpanded = false
        setMode(.editing)
        refreshPlaceholder()
    }

    private func setMode(_ newMode: Mode) {
        mode = newMode
        let generating = newMode == .generating
        let conflict = newMode == .conflict

        spinner.isHidden = !generating
        if generating { spinner.startAnimating() } else { spinner.stopAnimating() }
        loadingLabel.isHidden = !generating

        draftTextView.isHidden = generating || conflict
        placeholderLabel.isHidden = generating || conflict || !(draftTextView.text ?? "").isEmpty
        fallbackCaret.isHidden = generating || conflict || fallbackCaret.isHidden

        conflictLabel.isHidden = !conflict
        conflictStack.isHidden = !conflict

        // Both controls are meaningless mid-flight, and disabling them is what
        // makes a double tap on Regenerate impossible rather than merely
        // unlikely.
        regenerateButton.isEnabled = !generating && !conflict
        regenerateButton.alpha = regenerateButton.isEnabled ? 1 : 0.4
        insertButton.isHidden = conflict
        templateChip.isEnabled = !generating
        refreshInsertState()
    }

    // MARK: Text target

    /// Keys route here while the composer is open. Deliberately storage-based
    /// rather than `UIKeyInput`, so editing behaves identically whether or not
    /// the system granted first responder inside the extension.
    func insertText(_ text: String) {
        guard mode == .editing else { return }
        let current = (draftTextView.text ?? "") as NSString
        let range = clampedSelection(in: current)
        draftTextView.text = current.replacingCharacters(in: range, with: text)
        let caret = range.location + (text as NSString).length
        draftTextView.selectedRange = NSRange(location: caret, length: 0)
        draftDidChange()
    }

    func deleteBackward() {
        guard mode == .editing else { return }
        let current = (draftTextView.text ?? "") as NSString
        let range = clampedSelection(in: current)

        if range.length > 0 {
            draftTextView.text = current.replacingCharacters(in: range, with: "")
            draftTextView.selectedRange = NSRange(location: range.location, length: 0)
        } else if range.location > 0 {
            // Composed-character aware, so emoji and combining marks delete whole.
            let target = current.rangeOfComposedCharacterSequence(at: range.location - 1)
            draftTextView.text = current.replacingCharacters(in: target, with: "")
            draftTextView.selectedRange = NSRange(location: target.location, length: 0)
        } else {
            return
        }
        draftDidChange()
    }

    var textBeforeCursor: String? {
        let current = (draftTextView.text ?? "") as NSString
        let location = min(max(draftTextView.selectedRange.location, 0), current.length)
        return current.substring(to: location)
    }

    private func clampedSelection(in string: NSString) -> NSRange {
        var range = draftTextView.selectedRange
        if range.location == NSNotFound || range.location > string.length {
            range = NSRange(location: string.length, length: 0)
        }
        if range.location + range.length > string.length {
            range.length = max(0, string.length - range.location)
        }
        return range
    }

    private func draftDidChange() {
        refreshPlaceholder()
        refreshInsertState()
        recalculate()
        updateFallbackCaret()
    }

    // MARK: Measurement

    private func recalculate() {
        guard layoutWidth > 0 else { return }
        let contentWidth = max(1, layoutWidth - 12 - 20)

        sourceLabel.numberOfLines = isSourceExpanded ? expandedSourceLines : collapsedSourceLines
        let sourceFit = sourceLabel.sizeThatFits(
            CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
        ).height
        let newSource = max(ceil(sourceFont.lineHeight), ceil(sourceFit))

        let draftFit = draftTextView.sizeThatFits(
            CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
        ).height
        let newDraft = min(max(ceil(draftFit), minimumDraftHeight), maximumDraftHeight)

        guard abs(newSource - measuredSourceHeight) > 0.5 || abs(newDraft - measuredDraftHeight) > 0.5 else {
            return
        }
        measuredSourceHeight = newSource
        measuredDraftHeight = newDraft
        sourceHeight?.constant = newSource
        draftHeight?.constant = newDraft
        delegate?.composerDidChangeHeight(self)
    }

    // MARK: State refresh

    private func refreshPlaceholder() {
        placeholderLabel.isHidden = mode != .editing || !(draftTextView.text ?? "").isEmpty
    }

    private func refreshInsertState() {
        let enabled = mode == .editing && hasUsableDraft
        insertButton.isEnabled = enabled
        insertButton.configuration?.background.backgroundColor = enabled
            ? theme.accent
            : theme.accent.withAlphaComponent(0.30)
        insertButton.configuration?.baseForegroundColor = .white
        insertButton.alpha = enabled ? 1 : 0.75
    }

    // MARK: Caret fallback

    private func startCaretBlink() {
        stopCaretBlink()
        let timer = Timer(timeInterval: 0.55, repeats: true) { [weak self] _ in
            guard let self, !self.fallbackCaret.isHidden else { return }
            self.fallbackCaret.alpha = self.fallbackCaret.alpha > 0.5 ? 0 : 1
        }
        RunLoop.main.add(timer, forMode: .common)
        caretTimer = timer
    }

    private func stopCaretBlink() {
        caretTimer?.invalidate()
        caretTimer = nil
        fallbackCaret.isHidden = true
    }

    /// UIKit draws its own caret when the text view is first responder. When an
    /// extension is not granted first responder, this draws one instead so the
    /// insertion point is always visible.
    private func updateFallbackCaret() {
        guard mode == .editing, !draftTextView.isFirstResponder else {
            fallbackCaret.isHidden = true
            return
        }
        guard let position = draftTextView.position(
            from: draftTextView.beginningOfDocument,
            offset: min(draftTextView.selectedRange.location, (draftTextView.text ?? "").utf16.count)
        ) else {
            fallbackCaret.isHidden = true
            return
        }
        let rect = draftTextView.caretRect(for: position)
        guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.height.isFinite else {
            fallbackCaret.isHidden = true
            return
        }
        fallbackCaret.frame = CGRect(x: rect.minX, y: rect.minY, width: 2, height: rect.height)
        fallbackCaret.isHidden = false
        fallbackCaret.alpha = 1
    }

    // MARK: Actions

    @objc private func templateChipTapped() {
        delegate?.composerDidTapTemplateChip(self)
    }

    @objc private func insertTapped() {
        delegate?.composerDidTapInsert(self)
    }

    @objc private func regenerateTapped() {
        delegate?.composerDidTapRegenerate(self)
    }

    @objc private func replaceTapped() {
        delegate?.composer(self, didResolveConflictWith: .replace)
    }

    @objc private func appendTapped() {
        delegate?.composer(self, didResolveConflictWith: .append)
    }

    @objc private func conflictCancelTapped() {
        delegate?.composer(self, didResolveConflictWith: .cancel)
    }

    @objc private func toggleSourceExpansion() {
        isSourceExpanded.toggle()
        recalculate()
    }

    @objc private func draftTapped(_ recognizer: UITapGestureRecognizer) {
        guard mode == .editing else { return }
        if !draftTextView.isFirstResponder {
            _ = draftTextView.becomeFirstResponder()
        }
        let point = recognizer.location(in: draftTextView)
        if let position = draftTextView.closestPosition(to: point) {
            let offset = draftTextView.offset(from: draftTextView.beginningOfDocument, to: position)
            draftTextView.selectedRange = NSRange(location: offset, length: 0)
        }
        updateFallbackCaret()
    }
}

// MARK: - UITextViewDelegate

extension ReplyComposerView: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        draftDidChange()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        updateFallbackCaret()
    }
}
