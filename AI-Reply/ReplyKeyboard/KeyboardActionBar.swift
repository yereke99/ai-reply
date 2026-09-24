import UIKit

protocol KeyboardActionBarDelegate: AnyObject {
    func actionBar(_ bar: KeyboardActionBar, didSelectTemplateID id: String)
    func actionBarDidRequestNewTemplate(_ bar: KeyboardActionBar)
    /// Discard the whole session and go back to the template row.
    func actionBarDidTapClose(_ bar: KeyboardActionBar)
    /// Keep the session, show the template row so the audience can be changed.
    func actionBarDidRequestTemplateChange(_ bar: KeyboardActionBar)
    func actionBarDidTapPasteSource(_ bar: KeyboardActionBar)
    func actionBarDidTapGenerate(_ bar: KeyboardActionBar)
    func actionBarDidTapRegenerate(_ bar: KeyboardActionBar)
    func actionBarDidTapInsert(_ bar: KeyboardActionBar)
    func actionBarDidTapBack(_ bar: KeyboardActionBar)
    func actionBarDidEditText(_ bar: KeyboardActionBar)
    func actionBarDidChangeHeight(_ bar: KeyboardActionBar)
    func actionBar(_ bar: KeyboardActionBar, didResolveConflictWith choice: HostTextChoice)
}

/// The contextual area above the keys. It has exactly two shapes:
///
/// * COMPACT - a 36pt horizontal template row: Friend | Client | Business | Work
///   | + plus a transient status line that changes no geometry. This is the
///   keyboard at rest, and its height is what gets cached for the next launch.
/// * COMPOSER - the AI reply composer, which is itself a small state machine
///   (source + instruction, generating, result, conflict).
///
/// Neither shape ever takes height from the keys. The keyboard grows instead,
/// up to the ceiling the controller hands down, which is the rule that keeps
/// typing comfortable no matter what the AI UI is doing.
final class KeyboardActionBar: UIView {

    weak var delegate: KeyboardActionBarDelegate?

    private let templateBar = TemplateBarView()
    private let toastLabel = UILabel()
    private let composer = ReplyComposerView()

    private var theme = KeyboardTheme(isDark: true)
    private var toastWorkItem: DispatchWorkItem?

    private let idleHeight: CGFloat = TemplateBarView.preferredHeight + 4

    private(set) var isComposing = false

    /// Height the bar needs right now.
    var preferredHeight: CGFloat {
        isComposing ? composer.preferredHeight : idleHeight
    }

    /// The height the COMPACT bar needs. The controller caches this one and
    /// never the composer's, so a future launch opens at the right size.
    var compactHeight: CGFloat { idleHeight }

    /// True while the composer is showing the full copied message, which the
    /// controller allows a little extra keyboard height for.
    var wantsExpandedContext: Bool { isComposing && composer.wantsExpandedContext }

    var sourceText: String { composer.sourceText }
    var instructionText: String { composer.instructionText }
    var draftText: String { composer.replyDraft }
    var composerStage: ReplyComposerView.Stage { composer.stage }

    // MARK: Init

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        composer.delegate = self
        templateBar.delegate = self
        buildTemplateBar()
        buildToast()
        buildComposer()
        composer.isHidden = true
        toastLabel.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private func buildTemplateBar() {
        addSubview(templateBar)
        NSLayoutConstraint.activate([
            templateBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            templateBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            templateBar.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            templateBar.heightAnchor.constraint(equalToConstant: TemplateBarView.preferredHeight)
        ])
    }

    private func buildToast() {
        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        toastLabel.textAlignment = .center
        toastLabel.numberOfLines = 2
        toastLabel.font = .systemFont(ofSize: 12, weight: .medium)
        toastLabel.adjustsFontSizeToFitWidth = true
        toastLabel.minimumScaleFactor = 0.75
        addSubview(toastLabel)

        NSLayoutConstraint.activate([
            toastLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            toastLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            toastLabel.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            toastLabel.heightAnchor.constraint(equalToConstant: TemplateBarView.preferredHeight + 2)
        ])
    }

    private func buildComposer() {
        addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: trailingAnchor),
            composer.topAnchor.constraint(equalTo: topAnchor),
            composer.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    // MARK: Configuration

    /// - Parameter uiLanguage: this whole area is product UI, so it follows the
    ///   APP language. Key captions are the keys' own business and never reach
    ///   here, which is why no `KeyboardStrings` is passed in.
    func configure(theme: KeyboardTheme, uiLanguage: AppLanguage) {
        self.theme = theme
        toastLabel.textColor = theme.secondaryText
        templateBar.configure(theme: theme, uiLanguage: uiLanguage)
        composer.configure(theme: theme, uiLanguage: uiLanguage)
    }

    func setChips(_ chips: [TemplateChip]) {
        templateBar.setChips(chips)
    }

    func layout(forWidth width: CGFloat) {
        composer.layout(forWidth: width)
    }

    /// The tallest the composer may become, worked out by the controller from
    /// the screen height.
    func setMaximumComposerHeight(_ height: CGFloat) {
        composer.setMaximumHeight(height)
    }

    // MARK: Composer state

    /// Opens the composer. Nothing is generated: the user writes the
    /// instruction first, which is the whole point of this flow.
    func beginComposing(
        sourceMessage: String,
        instruction: String,
        draft: String,
        templateName: String
    ) {
        cancelToast()
        isComposing = true
        composer.isHidden = false
        templateBar.isHidden = true
        composer.begin(
            sourceMessage: sourceMessage,
            instruction: instruction,
            draft: draft,
            templateName: templateName
        )
    }

    func setSourceMessage(_ text: String) { composer.setSourceMessage(text) }
    func beginGenerating() { composer.beginGenerating() }
    func showResult(_ draft: String) { composer.showResult(draft) }
    func showError(_ message: String) { composer.showError(message) }
    func showConflictChoice() { composer.showConflictChoice() }
    func returnToComposing() { composer.returnToComposing() }
    func returnToResult() { composer.returnToResult() }
    func setTemplateName(_ name: String) { composer.setTemplateName(name) }

    func endComposing() {
        isComposing = false
        composer.end()
        composer.isHidden = true
        templateBar.isHidden = false
    }

    // MARK: Text target passthrough

    func insertText(_ text: String) { composer.insertText(text) }
    func deleteBackward() { composer.deleteBackward() }
    var textBeforeCursor: String? { composer.textBeforeCursor }

    /// Whether a keystroke should edit one of the composer's own fields rather
    /// than the host field. False while a request is in flight and during the
    /// conflict prompt, so keys typed then are ignored instead of leaking into
    /// WhatsApp.
    var acceptsTextInput: Bool { isComposing && composer.acceptsTextInput }

    // MARK: Transient status

    /// Short-lived status message for the COMPACT bar. It never changes the
    /// keyboard geometry, so the typing area is untouched while it is on
    /// screen. Failures that happen with the composer open are shown inline
    /// there instead, where the user's typing is still in front of them.
    func showToast(_ message: String) {
        guard !isComposing, !message.isEmpty else { return }
        cancelToast()
        toastLabel.text = message
        toastLabel.alpha = 0
        toastLabel.isHidden = false
        UIView.animate(withDuration: 0.16) {
            self.toastLabel.alpha = 1
            self.templateBar.alpha = 0
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            UIView.animate(withDuration: 0.2, animations: {
                self.toastLabel.alpha = 0
                self.templateBar.alpha = 1
            }, completion: { _ in
                self.toastLabel.isHidden = true
            })
        }
        toastWorkItem = work
        // Long enough to read a two-line sentence in Kazakh or Russian.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: work)
    }

    private func cancelToast() {
        toastWorkItem?.cancel()
        toastWorkItem = nil
        toastLabel.isHidden = true
        toastLabel.alpha = 0
        templateBar.alpha = 1
    }
}

// MARK: - Template bar

extension KeyboardActionBar: TemplateBarViewDelegate {

    func templateBar(_ bar: TemplateBarView, didSelectTemplateID id: String) {
        delegate?.actionBar(self, didSelectTemplateID: id)
    }

    func templateBarDidRequestNewTemplate(_ bar: TemplateBarView) {
        delegate?.actionBarDidRequestNewTemplate(self)
    }
}

// MARK: - Composer

extension KeyboardActionBar: ReplyComposerViewDelegate {

    func composerDidTapClose(_ composer: ReplyComposerView) {
        delegate?.actionBarDidTapClose(self)
    }

    func composerDidTapChangeTemplate(_ composer: ReplyComposerView) {
        delegate?.actionBarDidRequestTemplateChange(self)
    }

    func composerDidTapPasteSource(_ composer: ReplyComposerView) {
        delegate?.actionBarDidTapPasteSource(self)
    }

    func composerDidTapGenerate(_ composer: ReplyComposerView) {
        delegate?.actionBarDidTapGenerate(self)
    }

    func composerDidTapRegenerate(_ composer: ReplyComposerView) {
        delegate?.actionBarDidTapRegenerate(self)
    }

    func composerDidTapInsert(_ composer: ReplyComposerView) {
        delegate?.actionBarDidTapInsert(self)
    }

    func composerDidTapBack(_ composer: ReplyComposerView) {
        delegate?.actionBarDidTapBack(self)
    }

    func composerDidEditText(_ composer: ReplyComposerView) {
        delegate?.actionBarDidEditText(self)
    }

    func composerDidChangeHeight(_ composer: ReplyComposerView) {
        guard isComposing else { return }
        delegate?.actionBarDidChangeHeight(self)
    }

    func composer(_ composer: ReplyComposerView, didResolveConflictWith choice: HostTextChoice) {
        delegate?.actionBar(self, didResolveConflictWith: choice)
    }
}
