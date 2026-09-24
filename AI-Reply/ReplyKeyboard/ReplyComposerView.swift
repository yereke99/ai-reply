import UIKit

protocol ReplyComposerViewDelegate: AnyObject {
    /// Discard everything and go back to the template row.
    func composerDidTapClose(_ composer: ReplyComposerView)
    /// Keep the session, show the template row so another audience can be picked.
    func composerDidTapChangeTemplate(_ composer: ReplyComposerView)
    /// Explicit, user-initiated clipboard read.
    func composerDidTapPasteSource(_ composer: ReplyComposerView)
    func composerDidTapGenerate(_ composer: ReplyComposerView)
    func composerDidTapRegenerate(_ composer: ReplyComposerView)
    func composerDidTapInsert(_ composer: ReplyComposerView)
    /// Back from the result to the composer, with source and instruction intact.
    func composerDidTapBack(_ composer: ReplyComposerView)
    func composerDidChangeHeight(_ composer: ReplyComposerView)
    /// Any of the three texts changed, so the session can mirror it.
    func composerDidEditText(_ composer: ReplyComposerView)
    func composer(_ composer: ReplyComposerView, didResolveConflictWith choice: HostTextChoice)
}

/// How an insertion should treat text already in the host field.
enum HostTextChoice {
    case replace
    case append
    case cancel
}

/// The AI reply composer.
///
/// THE ONE IDEA THIS VIEW EXISTS TO EXPRESS:
///
///     SOURCE MESSAGE  !=  REPLY INSTRUCTION  !=  GENERATED REPLY
///
/// * the SOURCE MESSAGE is what the other person wrote. It is quoted - inset
///   surface, accent bar down its leading edge, secondary text colour - so it
///   never reads as something this user is about to send. It is editable, but
///   only after a deliberate tap, because the common case is that it arrived
///   from the clipboard and should be left alone.
/// * the REPLY INSTRUCTION is what THIS user wants said ("ответь вежливо, что
///   согласен"). It is the field that looks like a field: raised surface, real
///   placeholder, focus ring. It is never sent to the other person and never
///   becomes the reply.
/// * the GENERATED REPLY is the answer. It only exists in the result stage, and
///   it is the ONLY one of the three that can reach the host application.
///
/// The three are separate values, separate views and separate blocks in the
/// request. Nothing in this file merges them.
///
/// STAGES. The composer is a small state machine rather than one panel with
/// every control on it:
///
///     composing  - source + instruction + quick intents + Generate
///     generating - the same content, locked, with progress on the button
///     result     - the generated reply + Back / Regenerate / Edit / Insert
///     editing    - result, with the reply editable by the keys
///     conflict   - the host field already had text: Replace / Add / Cancel
///
/// Typing does not depend on a text view holding first responder: every edit
/// goes through `insertText`/`deleteBackward`, which mutate storage and move the
/// caret explicitly. First responder is still requested, because when the system
/// grants it inside an extension the user gets UIKit's own caret, selection
/// handles and magnifier for free. When it is not granted, `fallbackCaret` draws
/// the insertion point instead.
final class ReplyComposerView: UIView {

    weak var delegate: ReplyComposerViewDelegate?

    enum Stage: Equatable {
        case composing
        case generating
        case result
        case editing
        case conflict
    }

    /// Which of the three texts the keys are editing right now.
    enum Field: Equatable {
        case none
        case source
        case instruction
        case draft
    }

    // MARK: Model

    private(set) var stage: Stage = .composing
    private(set) var focus: Field = .instruction

    /// True while the user has asked to see the whole copied message. The
    /// controller allows the keyboard a little more height in that state,
    /// because it is an explicit and momentary request.
    var wantsExpandedContext: Bool { isSourceExpanded && stage != .conflict }

    var sourceText: String { sourceTextView.text ?? "" }
    var instructionText: String { instructionTextView.text ?? "" }
    var replyDraft: String { draftTextView.text ?? "" }

    var hasUsableSource: Bool {
        !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasUsableDraft: Bool {
        !replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sourceCharacterCount: Int {
        AIReplyService.characterCount(sourceText)
    }

    private var isSourceOverLimit: Bool {
        sourceCharacterCount > AIConfiguration.maximumMessageCharacters
    }

    /// Whether the keys should edit one of our own text views rather than the
    /// host application's field. False while a request is in flight and during
    /// the conflict prompt, so keystrokes are dropped instead of leaking into
    /// WhatsApp.
    var acceptsTextInput: Bool {
        switch stage {
        case .composing, .editing: return focus != .none
        case .generating, .result, .conflict: return false
        }
    }

    // MARK: Views

    private let container = UIView()

    // Header
    private let templateChip = UIButton(type: .system)
    /// The COLLAPSED form of the copied message: one quiet line beside the
    /// audience chip. This is the default in every stage; the full card below
    /// only appears when the user asks for it.
    private let contextPreview = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)

    // Source
    private let sourceCard = UIView()
    private let sourceCaption = UILabel()
    private let sourceCounter = UILabel()
    private let pasteButton = UIButton(type: .system)
    private let clearSourceButton = UIButton(type: .system)
    private let sourceCollapseButton = UIButton(type: .system)
    private let quoteBar = UIView()
    private let sourceTextView = UITextView()
    private let sourcePlaceholder = UILabel()

    // Instruction
    private let instructionTextView = UITextView()
    private let instructionPlaceholder = UILabel()

    // Result
    private let draftCaption = UILabel()
    private let draftTextView = UITextView()

    // Shared caret for whichever field has focus without first responder.
    private let fallbackCaret = UIView()

    // Status
    private let errorLabel = UILabel()

    // Compose actions
    private let composeActionRow = UIView()
    private let quickActions = QuickActionRow()
    private let generateButton = UIButton(type: .system)

    // Result actions
    private let resultActionRow = UIView()
    private let backButton = UIButton(type: .system)
    private let regenerateButton = UIButton(type: .system)
    private let editButton = UIButton(type: .system)
    private let insertButton = UIButton(type: .system)

    // Conflict
    private let conflictLabel = UILabel()
    private let conflictStack = UIStackView()
    private let replaceButton = UIButton(type: .system)
    private let appendButton = UIButton(type: .system)
    private let conflictCancelButton = UIButton(type: .system)

    // MARK: Layout state

    private var draftCaptionHeight: NSLayoutConstraint?
    private var sourceCardHeight: NSLayoutConstraint?
    private var sourceTextHeight: NSLayoutConstraint?
    private var instructionHeight: NSLayoutConstraint?
    private var draftHeight: NSLayoutConstraint?
    private var errorHeight: NSLayoutConstraint?
    private var errorBottom: NSLayoutConstraint?

    private var theme = KeyboardTheme(isDark: true)
    private var strings = AIReplyStrings.forLanguage(.english)
    private var layoutWidth: CGFloat = 0
    private var caretTimer: Timer?
    private var errorMessage: String?
    private var isSourceExpanded = false
    private var sourceNaturalLines = 1
    private var draftNaturalLines = 3
    /// Where to go back to when the conflict prompt is cancelled.
    private var stageBeforeConflict: Stage?

    /// Ceiling handed down by the controller, derived from the screen height, so
    /// the keyboard can grow for the composer without swallowing the
    /// conversation. See `KeyboardViewController.maximumActionBarHeight`.
    private var maximumHeight: CGFloat = 220

    private var measuredHeight: CGFloat = 200

    // MARK: Metrics

    private let sourceFont = UIFont.systemFont(ofSize: 14)
    private let instructionFont = UIFont.systemFont(ofSize: 15.5)
    private let draftFont = UIFont.systemFont(ofSize: 16)

    private let outerInset: CGFloat = 6
    private let cardInset: CGFloat = 10
    private let quoteBarWidth: CGFloat = 3
    private let quoteGap: CGFloat = 8
    private let cardPadding: CGFloat = 10

    private let headerHeight: CGFloat = 26
    private let captionHeight: CGFloat = 16
    private let actionRowHeight: CGFloat = 38
    private let gap: CGFloat = 6

    /// Quick actions on their own line above a full-width primary button.
    ///
    /// They used to share one 38pt row, which is what forced the intents into
    /// a scroll view and put the primary action shoulder to shoulder with its
    /// own secondary options. Separating them costs 36pt here and saves more
    /// than that by collapsing the quoted message into the header.
    private var composeActionRowHeight: CGFloat {
        QuickActionRow.preferredHeight + 6 + primaryButtonHeight
    }

    private let primaryButtonHeight: CGFloat = 38

    /// Height this view needs right now. The controller adds it to the keyboard
    /// height, so the keys keep their full size in every state.
    var preferredHeight: CGFloat { measuredHeight }

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

    // MARK: Hierarchy

    private func build() {
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.cornerRadius = 12
        container.layer.cornerCurve = .continuous
        addSubview(container)

        buildHeader()
        buildSource()
        buildInstruction()
        buildResult()
        buildStatus()
        buildComposeActions()
        buildResultActions()
        buildConflict()
        activateConstraints()
        setStage(.composing)
    }

    private func buildHeader() {
        // The audience. Tapping it goes back to the template row WITHOUT losing
        // the source or the instruction, so picking the wrong one costs a tap
        // rather than a retype.
        var chip = UIButton.Configuration.plain()
        chip.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 11, bottom: 0, trailing: 8)
        chip.background.cornerRadius = 13
        chip.imagePlacement = .trailing
        chip.imagePadding = 5
        chip.image = UIImage(
            systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        )
        templateChip.configuration = chip
        templateChip.translatesAutoresizingMaskIntoConstraints = false
        templateChip.addTarget(self, action: #selector(templateChipTapped), for: .touchUpInside)
        container.addSubview(templateChip)

        // The copied message, collapsed onto the header line. One tap opens
        // the full card; when there is nothing copied yet the same control is
        // the Paste affordance, so the empty state costs no height at all.
        var preview = UIButton.Configuration.plain()
        preview.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 9, bottom: 0, trailing: 7)
        preview.background.cornerRadius = 8
        preview.imagePlacement = .trailing
        preview.imagePadding = 6
        preview.titleLineBreakMode = .byTruncatingTail
        contextPreview.configuration = preview
        contextPreview.translatesAutoresizingMaskIntoConstraints = false
        contextPreview.contentHorizontalAlignment = .leading
        contextPreview.addTarget(self, action: #selector(contextPreviewTapped), for: .touchUpInside)
        contextPreview.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        contextPreview.setContentHuggingPriority(.defaultLow, for: .horizontal)
        container.addSubview(contextPreview)

        configureIconButton(closeButton, symbol: "xmark", pointSize: 12)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        container.addSubview(closeButton)
    }

    private func buildSource() {
        sourceCard.translatesAutoresizingMaskIntoConstraints = false
        sourceCard.layer.cornerRadius = 9
        sourceCard.layer.cornerCurve = .continuous
        container.addSubview(sourceCard)

        sourceCaption.translatesAutoresizingMaskIntoConstraints = false
        sourceCaption.font = .systemFont(ofSize: 11, weight: .semibold)
        sourceCaption.adjustsFontSizeToFitWidth = true
        sourceCaption.minimumScaleFactor = 0.8
        sourceCard.addSubview(sourceCaption)

        sourceCounter.translatesAutoresizingMaskIntoConstraints = false
        sourceCounter.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        sourceCounter.textAlignment = .right
        sourceCounter.isHidden = true
        sourceCard.addSubview(sourceCounter)

        configureIconButton(sourceCollapseButton, symbol: "chevron.up", pointSize: 11, diameter: 22)
        sourceCollapseButton.addTarget(self, action: #selector(collapseSourceTapped), for: .touchUpInside)
        sourceCard.addSubview(sourceCollapseButton)

        configureIconButton(pasteButton, symbol: "doc.on.clipboard", pointSize: 12, diameter: 22)
        pasteButton.addTarget(self, action: #selector(pasteTapped), for: .touchUpInside)
        sourceCard.addSubview(pasteButton)

        configureIconButton(clearSourceButton, symbol: "xmark.circle.fill", pointSize: 13, diameter: 22)
        clearSourceButton.addTarget(self, action: #selector(clearSourceTapped), for: .touchUpInside)
        sourceCard.addSubview(clearSourceButton)

        quoteBar.translatesAutoresizingMaskIntoConstraints = false
        quoteBar.layer.cornerRadius = quoteBarWidth / 2
        sourceCard.addSubview(quoteBar)

        configureTextView(sourceTextView, font: sourceFont, inset: UIEdgeInsets(top: 5, left: 0, bottom: 5, right: 0))
        sourceCard.addSubview(sourceTextView)
        attachTap(to: sourceTextView, action: #selector(sourceTapped(_:)))

        sourcePlaceholder.translatesAutoresizingMaskIntoConstraints = false
        sourcePlaceholder.font = sourceFont
        sourcePlaceholder.numberOfLines = 1
        sourcePlaceholder.isUserInteractionEnabled = false
        sourceCard.addSubview(sourcePlaceholder)
    }

    private func buildInstruction() {
        configureTextView(
            instructionTextView,
            font: instructionFont,
            inset: UIEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
        )
        instructionTextView.layer.cornerRadius = 9
        instructionTextView.layer.cornerCurve = .continuous
        instructionTextView.layer.borderWidth = 1
        container.addSubview(instructionTextView)
        attachTap(to: instructionTextView, action: #selector(instructionTapped(_:)))

        instructionPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        instructionPlaceholder.font = instructionFont
        instructionPlaceholder.numberOfLines = 1
        instructionPlaceholder.adjustsFontSizeToFitWidth = true
        instructionPlaceholder.minimumScaleFactor = 0.8
        instructionPlaceholder.isUserInteractionEnabled = false
        container.addSubview(instructionPlaceholder)
    }

    private func buildResult() {
        draftCaption.translatesAutoresizingMaskIntoConstraints = false
        draftCaption.font = .systemFont(ofSize: 11, weight: .semibold)
        container.addSubview(draftCaption)

        configureTextView(
            draftTextView,
            font: draftFont,
            inset: UIEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
        )
        draftTextView.layer.cornerRadius = 9
        draftTextView.layer.cornerCurve = .continuous
        container.addSubview(draftTextView)
        attachTap(to: draftTextView, action: #selector(draftTapped(_:)))

        // Frame-driven on purpose: its position comes from caretRect(for:).
        fallbackCaret.translatesAutoresizingMaskIntoConstraints = true
        fallbackCaret.isUserInteractionEnabled = false
        fallbackCaret.isHidden = true
        fallbackCaret.layer.cornerRadius = 1
    }

    private func buildStatus() {
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        errorLabel.numberOfLines = 2
        errorLabel.adjustsFontSizeToFitWidth = true
        errorLabel.minimumScaleFactor = 0.8
        errorLabel.isHidden = true
        container.addSubview(errorLabel)
    }

    private func buildComposeActions() {
        composeActionRow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(composeActionRow)

        // Quick intents. They WRITE INTO THE INSTRUCTION and never touch the
        // source message - that is the whole rule for presets here. They get
        // their own line: sharing one with the primary button is what made a
        // third pill impossible to draw whole.
        quickActions.delegate = self
        composeActionRow.addSubview(quickActions)

        // The primary action, full width and unmistakable. No trailing arrow:
        // a button that says "Жауап беру" across the whole panel does not need
        // a glyph to explain that it is the thing to press.
        var generate = UIButton.Configuration.plain()
        generate.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
        generate.background.cornerRadius = 12
        generate.titleAlignment = .center
        generateButton.configuration = generate
        generateButton.translatesAutoresizingMaskIntoConstraints = false
        generateButton.addTarget(self, action: #selector(generateTapped), for: .touchUpInside)
        composeActionRow.addSubview(generateButton)
    }

    private func buildResultActions() {
        resultActionRow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(resultActionRow)

        configureIconButton(backButton, symbol: "chevron.left", pointSize: 13, diameter: 34)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        resultActionRow.addSubview(backButton)

        configureIconButton(regenerateButton, symbol: "arrow.clockwise", pointSize: 14, diameter: 34)
        regenerateButton.addTarget(self, action: #selector(regenerateTapped), for: .touchUpInside)
        resultActionRow.addSubview(regenerateButton)

        configureIconButton(editButton, symbol: "pencil", pointSize: 14, diameter: 34)
        editButton.addTarget(self, action: #selector(editTapped), for: .touchUpInside)
        resultActionRow.addSubview(editButton)

        var insert = UIButton.Configuration.plain()
        insert.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18)
        insert.background.cornerRadius = 17
        insertButton.configuration = insert
        insertButton.translatesAutoresizingMaskIntoConstraints = false
        insertButton.addTarget(self, action: #selector(insertTapped), for: .touchUpInside)
        insertButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        resultActionRow.addSubview(insertButton)
    }

    private func buildConflict() {
        conflictLabel.translatesAutoresizingMaskIntoConstraints = false
        conflictLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
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
            configuration.background.cornerRadius = 17
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6)
            button.configuration = configuration
            button.addTarget(self, action: action, for: .touchUpInside)
            conflictStack.addArrangedSubview(button)
        }
    }

    // MARK: Building blocks

    private func configureIconButton(
        _ button: UIButton,
        symbol: String,
        pointSize: CGFloat,
        diameter: CGFloat = 26
    ) {
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = .zero
        configuration.background.cornerRadius = diameter / 2
        configuration.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        )
        button.configuration = configuration
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: diameter),
            button.heightAnchor.constraint(equalToConstant: diameter)
        ])
    }

    /// Every editable surface in here is a `UITextView` with the system keyboard
    /// disabled: THIS keyboard is the keyboard, and letting UIKit summon another
    /// one inside an extension is how you get two carets and no input.
    private func configureTextView(_ textView: UITextView, font: UIFont, inset: UIEdgeInsets) {
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = font
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = false
        textView.textContainerInset = inset
        textView.textContainer.lineFragmentPadding = 0
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.inputView = UIView()
        textView.inputAccessoryView = nil
        textView.delegate = self
    }

    private func attachTap(to view: UIView, action: Selector) {
        let tap = UITapGestureRecognizer(target: self, action: action)
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    private func activateConstraints() {
        let sourceCardH = sourceCard.heightAnchor.constraint(equalToConstant: 79)
        let sourceTextH = sourceTextView.heightAnchor.constraint(equalToConstant: 27)
        let instructionH = instructionTextView.heightAnchor.constraint(equalToConstant: 51)
        let draftH = draftTextView.heightAnchor.constraint(equalToConstant: 72)
        let errorH = errorLabel.heightAnchor.constraint(equalToConstant: 0)
        // Sits above whichever action row the current stage is showing. The
        // compose row and the result row are no longer the same height, so
        // this follows the stage rather than one particular row.
        let errorB = errorLabel.bottomAnchor.constraint(
            equalTo: container.bottomAnchor,
            constant: -(8 + composeActionRowHeight + 4)
        )
        errorBottom = errorB
        let draftCaptionH = draftCaption.heightAnchor.constraint(equalToConstant: captionHeight)
        draftCaptionHeight = draftCaptionH
        sourceCardHeight = sourceCardH
        sourceTextHeight = sourceTextH
        instructionHeight = instructionH
        draftHeight = draftH
        errorHeight = errorH

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: outerInset),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -outerInset),
            container.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),

            // Header: audience, collapsed message, close.
            templateChip.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: cardInset),
            templateChip.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            templateChip.heightAnchor.constraint(equalToConstant: headerHeight),
            // A long audience name yields to the message preview rather than
            // pushing it off the row.
            templateChip.widthAnchor.constraint(lessThanOrEqualToConstant: 150),

            contextPreview.leadingAnchor.constraint(equalTo: templateChip.trailingAnchor, constant: 6),
            contextPreview.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -6),
            contextPreview.centerYAnchor.constraint(equalTo: templateChip.centerYAnchor),
            contextPreview.heightAnchor.constraint(equalToConstant: headerHeight),

            closeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -cardInset),
            closeButton.centerYAnchor.constraint(equalTo: templateChip.centerYAnchor),

            // Source card
            sourceCard.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: cardInset),
            sourceCard.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -cardInset),
            sourceCard.topAnchor.constraint(equalTo: templateChip.bottomAnchor, constant: 4),
            sourceCardH,

            sourceCaption.leadingAnchor.constraint(equalTo: sourceCard.leadingAnchor, constant: cardPadding),
            sourceCaption.topAnchor.constraint(equalTo: sourceCard.topAnchor, constant: 4),
            sourceCaption.heightAnchor.constraint(equalToConstant: 14),
            sourceCaption.trailingAnchor.constraint(lessThanOrEqualTo: sourceCounter.leadingAnchor, constant: -6),

            sourceCounter.trailingAnchor.constraint(equalTo: sourceCollapseButton.leadingAnchor, constant: -2),
            sourceCounter.centerYAnchor.constraint(equalTo: sourceCaption.centerYAnchor),

            sourceCollapseButton.trailingAnchor.constraint(equalTo: pasteButton.leadingAnchor, constant: -2),
            sourceCollapseButton.centerYAnchor.constraint(equalTo: sourceCaption.centerYAnchor),

            pasteButton.trailingAnchor.constraint(equalTo: clearSourceButton.leadingAnchor, constant: -2),
            pasteButton.centerYAnchor.constraint(equalTo: sourceCaption.centerYAnchor),

            clearSourceButton.trailingAnchor.constraint(equalTo: sourceCard.trailingAnchor, constant: -6),
            clearSourceButton.centerYAnchor.constraint(equalTo: sourceCaption.centerYAnchor),

            quoteBar.leadingAnchor.constraint(equalTo: sourceCard.leadingAnchor, constant: cardPadding),
            quoteBar.widthAnchor.constraint(equalToConstant: quoteBarWidth),
            quoteBar.topAnchor.constraint(equalTo: sourceTextView.topAnchor, constant: 3),
            quoteBar.bottomAnchor.constraint(equalTo: sourceTextView.bottomAnchor, constant: -3),

            sourceTextView.leadingAnchor.constraint(equalTo: quoteBar.trailingAnchor, constant: quoteGap),
            sourceTextView.trailingAnchor.constraint(equalTo: sourceCard.trailingAnchor, constant: -cardPadding),
            sourceTextView.topAnchor.constraint(equalTo: sourceCaption.bottomAnchor, constant: 2),
            sourceTextH,

            sourcePlaceholder.leadingAnchor.constraint(equalTo: sourceTextView.leadingAnchor),
            sourcePlaceholder.trailingAnchor.constraint(lessThanOrEqualTo: sourceTextView.trailingAnchor),
            sourcePlaceholder.topAnchor.constraint(equalTo: sourceTextView.topAnchor, constant: 5),

            // Instruction
            instructionTextView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: cardInset),
            instructionTextView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -cardInset),
            instructionTextView.topAnchor.constraint(equalTo: sourceCard.bottomAnchor, constant: gap),
            instructionH,

            instructionPlaceholder.leadingAnchor.constraint(equalTo: instructionTextView.leadingAnchor, constant: 10),
            instructionPlaceholder.trailingAnchor.constraint(
                lessThanOrEqualTo: instructionTextView.trailingAnchor, constant: -10
            ),
            instructionPlaceholder.topAnchor.constraint(equalTo: instructionTextView.topAnchor, constant: 7),

            // Result
            draftCaption.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: cardInset),
            draftCaption.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -cardInset),
            draftCaption.topAnchor.constraint(equalTo: sourceCard.bottomAnchor, constant: gap),
            draftCaptionH,

            draftTextView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: cardInset),
            draftTextView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -cardInset),
            draftTextView.topAnchor.constraint(equalTo: draftCaption.bottomAnchor, constant: 2),
            draftH,

            // Bottom cluster
            composeActionRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: cardInset),
            composeActionRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -cardInset),
            composeActionRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            composeActionRow.heightAnchor.constraint(equalToConstant: composeActionRowHeight),

            resultActionRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: cardInset),
            resultActionRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -cardInset),
            resultActionRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            resultActionRow.heightAnchor.constraint(equalToConstant: actionRowHeight),

            errorLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: cardInset),
            errorLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -cardInset),
            errorB,
            errorH,

            // Compose actions: secondary line, then the primary button.
            quickActions.leadingAnchor.constraint(equalTo: composeActionRow.leadingAnchor),
            quickActions.trailingAnchor.constraint(equalTo: composeActionRow.trailingAnchor),
            quickActions.topAnchor.constraint(equalTo: composeActionRow.topAnchor),
            quickActions.heightAnchor.constraint(equalToConstant: QuickActionRow.preferredHeight),

            generateButton.leadingAnchor.constraint(equalTo: composeActionRow.leadingAnchor),
            generateButton.trailingAnchor.constraint(equalTo: composeActionRow.trailingAnchor),
            generateButton.bottomAnchor.constraint(equalTo: composeActionRow.bottomAnchor),
            generateButton.heightAnchor.constraint(equalToConstant: primaryButtonHeight),

            // Result actions
            backButton.leadingAnchor.constraint(equalTo: resultActionRow.leadingAnchor),
            backButton.centerYAnchor.constraint(equalTo: resultActionRow.centerYAnchor),
            regenerateButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 6),
            regenerateButton.centerYAnchor.constraint(equalTo: resultActionRow.centerYAnchor),
            editButton.leadingAnchor.constraint(equalTo: regenerateButton.trailingAnchor, constant: 6),
            editButton.centerYAnchor.constraint(equalTo: resultActionRow.centerYAnchor),

            insertButton.trailingAnchor.constraint(equalTo: resultActionRow.trailingAnchor),
            insertButton.centerYAnchor.constraint(equalTo: resultActionRow.centerYAnchor),
            insertButton.heightAnchor.constraint(equalToConstant: 34),
            insertButton.leadingAnchor.constraint(
                greaterThanOrEqualTo: editButton.trailingAnchor, constant: 8
            ),

            // Conflict
            conflictLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: cardInset),
            conflictLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -cardInset),
            conflictLabel.topAnchor.constraint(equalTo: templateChip.bottomAnchor, constant: 8),
            conflictLabel.heightAnchor.constraint(equalToConstant: 34),

            conflictStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: cardInset),
            conflictStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -cardInset),
            conflictStack.topAnchor.constraint(equalTo: conflictLabel.bottomAnchor, constant: 6),
            conflictStack.heightAnchor.constraint(equalToConstant: 34)
        ])
    }

    // MARK: Configuration

    /// - Parameter uiLanguage: the APP's language. The composer is product UI,
    ///   so every label in it follows the app, not the layout being typed on.
    func configure(theme: KeyboardTheme, uiLanguage: AppLanguage) {
        self.theme = theme
        self.strings = AIReplyStrings.forLanguage(uiLanguage)
        applyStrings()
        // `applyTheme` configures the quick-action row; doing it twice here
        // would just make the row rebuild for nothing.
        applyTheme()
        refreshControls()
    }

    private func applyStrings() {
        sourceCaption.text = strings.copiedMessage.uppercased()
        sourcePlaceholder.text = strings.noSourceMessage
        instructionPlaceholder.text = strings.instructionPlaceholder
        draftCaption.text = strings.draftTitle.uppercased()
        conflictLabel.text = strings.hostFieldNotEmpty

        closeButton.accessibilityLabel = strings.cancel
        sourceCollapseButton.accessibilityLabel = strings.hideFullMessage
        pasteButton.accessibilityLabel = strings.pasteMessage
        clearSourceButton.accessibilityLabel = strings.clearSource
        backButton.accessibilityLabel = strings.back
        regenerateButton.accessibilityLabel = strings.regenerate
        editButton.accessibilityLabel = strings.editReply
        instructionTextView.accessibilityLabel = strings.instructionPlaceholder
        sourceTextView.accessibilityLabel = strings.copiedMessage
        draftTextView.accessibilityLabel = strings.draftTitle

        refreshContextPreview()
        applyTitle(strings.insert, to: insertButton, size: 15, weight: .semibold)
        applyTitle(strings.replaceExisting, to: replaceButton, size: 13, weight: .semibold)
        applyTitle(strings.appendToExisting, to: appendButton, size: 13, weight: .semibold)
        applyTitle(strings.keepTyping, to: conflictCancelButton, size: 13, weight: .semibold)
        refreshGenerateTitle()
    }

    private func applyTheme() {
        container.backgroundColor = theme.panelBackground

        templateChip.configuration?.background.backgroundColor = theme.fieldBackground
        templateChip.configuration?.baseForegroundColor = theme.primaryText
        templateChip.tintColor = theme.primaryText

        contextPreview.configuration?.background.backgroundColor = theme.quoteBackground
        contextPreview.configuration?.baseForegroundColor = theme.quoteText
        contextPreview.tintColor = theme.secondaryText

        styleIconButton(closeButton, prominent: false)
        styleIconButton(sourceCollapseButton, prominent: false)
        styleIconButton(pasteButton, prominent: false)
        styleIconButton(clearSourceButton, prominent: false)
        styleIconButton(backButton, prominent: false)
        styleIconButton(regenerateButton, prominent: false)
        styleIconButton(editButton, prominent: false)

        sourceCard.backgroundColor = theme.quoteBackground
        quoteBar.backgroundColor = theme.accent.withAlphaComponent(0.75)
        sourceCaption.textColor = theme.secondaryText
        sourceTextView.textColor = theme.quoteText
        sourceTextView.tintColor = theme.accent
        sourceTextView.indicatorStyle = theme.isDark ? .white : .black
        sourcePlaceholder.textColor = theme.secondaryText

        instructionTextView.backgroundColor = theme.fieldBackground
        instructionTextView.textColor = theme.primaryText
        instructionTextView.tintColor = theme.accent
        instructionTextView.indicatorStyle = theme.isDark ? .white : .black
        instructionPlaceholder.textColor = theme.secondaryText

        draftCaption.textColor = theme.secondaryText
        draftTextView.backgroundColor = theme.fieldBackground
        draftTextView.textColor = theme.primaryText
        draftTextView.tintColor = theme.accent
        draftTextView.indicatorStyle = theme.isDark ? .white : .black

        errorLabel.textColor = theme.destructive
        conflictLabel.textColor = theme.primaryText
        fallbackCaret.backgroundColor = theme.accent

        for button in [replaceButton, appendButton] {
            button.configuration?.background.backgroundColor = theme.accent
            button.configuration?.baseForegroundColor = .white
        }
        conflictCancelButton.configuration?.background.backgroundColor = theme.fieldBackground
        conflictCancelButton.configuration?.baseForegroundColor = theme.primaryText

        quickActions.configure(theme: theme, strings: strings)
        refreshFieldBorders()
    }

    private func styleIconButton(_ button: UIButton, prominent: Bool) {
        button.configuration?.background.backgroundColor = prominent ? theme.accent : theme.fieldBackground
        button.configuration?.baseForegroundColor = prominent ? .white : theme.primaryText
        button.tintColor = prominent ? .white : theme.primaryText
    }

    private func applyTitle(_ title: String, to button: UIButton, size: CGFloat, weight: UIFont.Weight) {
        var attributes = AttributeContainer()
        attributes.font = .systemFont(ofSize: size, weight: weight)
        button.configuration?.attributedTitle = AttributedString(title, attributes: attributes)
        button.accessibilityLabel = title
    }

    /// One button, three jobs: Generate, Generating…, and Retry after a failure.
    /// Keeping them on the same control is what makes "try again" cost one tap
    /// and lose nothing.
    private func refreshGenerateTitle() {
        let title: String
        if stage == .generating {
            title = strings.generating
        } else if errorMessage != nil {
            title = strings.retry
        } else {
            title = strings.generate
        }
        applyTitle(title, to: generateButton, size: 16, weight: .semibold)
    }

    // MARK: Quick intents

    /// Presets WRITE INTO THE INSTRUCTION. They never replace the source
    /// message and they never become the reply: the user can read what was
    /// added, edit it, and add a second intent on top.
    ///
    /// The row itself owns its layout (see `QuickActionRow`), which is what
    /// guarantees that no action is ever drawn half-clipped whatever the
    /// language or the screen width.
    private func applyIntent(_ intent: QuickIntent) {
        guard stage == .composing else { return }
        setFocus(.instruction)
        let current = instructionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = current.isEmpty ? intent.phrase : current + " " + intent.phrase
        instructionTextView.text = ReplyInstruction.clamp(combined)
        moveCaretToEnd(instructionTextView)
        textsDidChange(remeasure: true)
    }

    // MARK: Collapsed context

    /// The one-line form of the copied message that lives on the header row.
    ///
    /// When nothing has been copied it becomes the Paste control, so the empty
    /// state costs a single line instead of an empty quote card with a caption
    /// over it.
    private func refreshContextPreview() {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSource = !trimmed.isEmpty
        let symbol = hasSource ? "chevron.down" : "doc.on.clipboard"
        contextPreview.configuration?.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        )
        // One line, whitespace flattened: a pasted message with newlines in it
        // must not be able to change the height of the header.
        let preview = hasSource
            ? trimmed.split(whereSeparator: \.isNewline).joined(separator: " ")
            : strings.pasteMessage
        var attributes = AttributeContainer()
        attributes.font = .systemFont(ofSize: 13, weight: hasSource ? .regular : .medium)
        contextPreview.configuration?.attributedTitle = AttributedString(preview, attributes: attributes)
        contextPreview.accessibilityLabel = hasSource
            ? "\(strings.copiedMessage): \(preview)"
            : strings.pasteMessage
        contextPreview.accessibilityHint = hasSource ? strings.showFullMessage : nil
    }

    /// Re-measures for the given keyboard width. Safe to call repeatedly.
    func layout(forWidth width: CGFloat) {
        guard width > 0, abs(width - layoutWidth) > 0.5 else { return }
        layoutWidth = width
        recalculate(force: true)
    }

    /// The ceiling the keyboard is willing to grow to. Set by the controller
    /// from the screen height.
    func setMaximumHeight(_ height: CGFloat) {
        guard abs(height - maximumHeight) > 0.5 else { return }
        maximumHeight = height
        recalculate(force: true)
    }

    // MARK: Session

    /// Opens the composer for an audience with whatever source text was
    /// acquired. NOTHING IS GENERATED HERE - the user gets to say how they want
    /// to reply first, which is the entire point of this screen.
    /// - Parameter draft: a reply that already exists, when the composer is
    ///   being REOPENED rather than started - the user went back to the
    ///   template row to change the audience and then picked one. A generation
    ///   costs the user a request from their daily allowance, so losing one to
    ///   a mistapped chip is not an acceptable outcome; it comes back with the
    ///   composer, in the result stage where it was left.
    func begin(sourceMessage: String, instruction: String, draft: String, templateName: String) {
        sourceTextView.text = sourceMessage
        instructionTextView.text = instruction
        draftTextView.text = draft
        errorMessage = nil
        isSourceExpanded = false
        stageBeforeConflict = nil
        setTemplateName(templateName)
        if hasUsableDraft {
            moveCaretToEnd(draftTextView)
            setStage(.result)
        } else {
            moveCaretToEnd(instructionTextView)
            setStage(.composing)
        }
    }

    func setTemplateName(_ name: String) {
        applyTitle(name, to: templateChip, size: 12.5, weight: .semibold)
        templateChip.accessibilityLabel = name
    }

    /// Replaces the quoted source, e.g. after an explicit Paste.
    func setSourceMessage(_ text: String) {
        sourceTextView.text = text
        isSourceExpanded = false
        errorMessage = nil
        if stage == .composing { setFocus(.instruction) }
        textsDidChange(remeasure: true)
    }

    func beginGenerating() {
        errorMessage = nil
        setStage(.generating)
    }

    func showResult(_ draft: String) {
        draftTextView.text = draft
        errorMessage = nil
        moveCaretToEnd(draftTextView)
        setStage(.result)
    }

    /// A failure never costs the user their typing: the stage falls back to
    /// whatever still has content, and the message appears inline with the
    /// primary button relabelled to Retry.
    func showError(_ message: String) {
        errorMessage = message.isEmpty ? nil : message
        errorLabel.text = errorMessage

        // Only move the user when the stage they are in cannot show a message
        // and cannot be typed in. Re-entering `.composing` from `.composing`
        // would reset focus to the instruction - which is wrong when the
        // failure happened while they were editing the quoted source.
        switch stage {
        case .composing, .editing, .result:
            errorLabel.isHidden = errorMessage == nil
            refreshGenerateTitle()
            refreshControls()
            recalculate(force: true)
        case .generating, .conflict:
            setStage(hasUsableDraft ? .result : .composing)
        }
    }

    func showConflictChoice() {
        // A stale failure has no business reappearing underneath the answer to
        // a different question.
        errorMessage = nil
        errorLabel.isHidden = true
        stageBeforeConflict = stage
        setStage(.conflict)
    }

    /// Returns from the result to the composer with source and instruction
    /// intact, so "not quite right" is one tap from being fixed.
    func returnToComposing() {
        errorMessage = nil
        setStage(.composing)
    }

    /// Back from the host-field conflict prompt, to EXACTLY where the user
    /// was. Cancelling a prompt must not also drop them out of edit mode.
    func returnToResult() {
        let remembered = stageBeforeConflict
        stageBeforeConflict = nil
        guard hasUsableDraft else { return setStage(.composing) }
        switch remembered {
        case .editing: setStage(.editing)
        default:       setStage(.result)
        }
    }

    func end() {
        stopCaretBlink()
        resignAllFields()
        sourceTextView.text = ""
        instructionTextView.text = ""
        draftTextView.text = ""
        errorMessage = nil
        isSourceExpanded = false
        setStage(.composing)
        setFocus(.none)
    }

    // MARK: Stage machine

    private func setStage(_ newStage: Stage) {
        stage = newStage

        let composing = newStage == .composing || newStage == .generating
        let result = newStage == .result || newStage == .editing
        let conflict = newStage == .conflict

        // `sourceCard` / `contextPreview` visibility is decided in
        // `refreshControls`, which runs at the end of this method and is the
        // single place that knows whether the quote is expanded.
        instructionTextView.isHidden = !composing
        instructionPlaceholder.isHidden = true
        composeActionRow.isHidden = !composing

        // ONLY the field this stage can focus is editable and selectable.
        //
        // Leaving all three permanently editable let UIKit's own text
        // interaction hand first responder to whichever one was tapped, behind
        // this state machine's back: a caret would blink in the quoted message
        // while the keys went on editing the draft, and a hidden view could
        // keep first responder through the conflict prompt. Keys never depend
        // on first responder - `insertText` edits storage directly - so
        // restricting it costs nothing and closes both.
        setInteraction(sourceTextView, enabled: newStage == .composing)
        setInteraction(instructionTextView, enabled: newStage == .composing)
        setInteraction(draftTextView, enabled: newStage == .editing)

        draftCaption.isHidden = !result || !showsDraftCaption
        draftTextView.isHidden = !result
        resultActionRow.isHidden = !result

        conflictLabel.isHidden = !conflict
        conflictStack.isHidden = !conflict

        errorLabel.isHidden = conflict || errorMessage == nil
        errorBottom?.constant = -(8 + (result ? actionRowHeight : composeActionRowHeight) + 4)

        switch newStage {
        case .composing:  setFocus(.instruction)
        case .editing:    setFocus(.draft)
        case .generating, .result, .conflict: setFocus(.none)
        }

        refreshGenerateTitle()
        refreshControls()
        recalculate(force: true)
    }

    // MARK: Focus

    private var focusedTextView: UITextView? {
        switch focus {
        case .none:        return nil
        case .source:      return sourceTextView
        case .instruction: return instructionTextView
        case .draft:       return draftTextView
        }
    }

    /// A text view is editable exactly when it is the field its stage can
    /// focus. `isSelectable` goes with it, because a selectable view still
    /// accepts first responder for the selection UI.
    private func setInteraction(_ textView: UITextView, enabled: Bool) {
        guard textView.isEditable != enabled else { return }
        if !enabled, textView.isFirstResponder { textView.resignFirstResponder() }
        textView.isEditable = enabled
        textView.isSelectable = enabled
    }

    private func setFocus(_ field: Field) {
        focus = field
        // Unconditional: focus can be unchanged and still need resigning,
        // because UIKit can have moved first responder on its own.
        resignAllFields()

        if let target = focusedTextView {
            // A bonus, never a requirement: when an extension is granted first
            // responder the user gets UIKit's caret, selection handles and
            // magnifier. When it is not, `fallbackCaret` stands in.
            _ = target.becomeFirstResponder()
            startCaretBlink()
        } else {
            stopCaretBlink()
        }
        refreshFieldBorders()
        updateFallbackCaret()
    }

    private func resignAllFields() {
        for view in [sourceTextView, instructionTextView, draftTextView] where view.isFirstResponder {
            view.resignFirstResponder()
        }
    }

    private func refreshFieldBorders() {
        instructionTextView.layer.borderColor = (focus == .instruction
            ? theme.fieldBorderFocused
            : theme.fieldBorder).cgColor
        sourceCard.layer.borderWidth = focus == .source ? 1 : 0
        sourceCard.layer.borderColor = theme.fieldBorderFocused.cgColor
        draftTextView.layer.borderWidth = 1
        draftTextView.layer.borderColor = (focus == .draft
            ? theme.fieldBorderFocused
            : theme.fieldBorder).cgColor
    }

    private func moveCaretToEnd(_ textView: UITextView) {
        let end = ((textView.text ?? "") as NSString).length
        textView.selectedRange = NSRange(location: end, length: 0)
    }

    // MARK: Control state

    private func refreshControls() {
        let composing = stage == .composing
        let result = stage == .result || stage == .editing

        sourcePlaceholder.isHidden = !sourceText.isEmpty
        instructionPlaceholder.isHidden = !(stage == .composing || stage == .generating)
            || !instructionText.isEmpty

        refreshContextPreview()
        // The header preview and the full card are two views of one thing and
        // are never on screen together.
        let showsCard = isSourceExpanded && stage != .conflict
        sourceCard.isHidden = !showsCard
        contextPreview.isHidden = showsCard || stage == .conflict
        contextPreview.isEnabled = stage == .composing || stage == .result || stage == .editing
        sourceCollapseButton.isHidden = !showsCard

        pasteButton.isHidden = !composing
        clearSourceButton.isHidden = !composing || sourceText.isEmpty

        let count = sourceCharacterCount
        let limit = AIConfiguration.maximumMessageCharacters
        sourceCounter.isHidden = !composing || count < limit - 60
        sourceCounter.text = "\(count)/\(limit)"
        sourceCounter.textColor = count > limit ? theme.destructive : theme.secondaryText

        let canGenerate = composing && hasUsableSource && !isSourceOverLimit
        generateButton.isEnabled = canGenerate
        generateButton.configuration?.background.backgroundColor = canGenerate
            ? theme.accent
            : theme.accent.withAlphaComponent(0.30)
        generateButton.configuration?.baseForegroundColor = .white
        generateButton.configuration?.showsActivityIndicator = stage == .generating
        generateButton.alpha = canGenerate || stage == .generating ? 1 : 0.8

        quickActions.setEnabled(composing)

        let canInsert = result && hasUsableDraft
        insertButton.isEnabled = canInsert
        insertButton.configuration?.background.backgroundColor = canInsert
            ? theme.accent
            : theme.accent.withAlphaComponent(0.30)
        insertButton.configuration?.baseForegroundColor = .white

        regenerateButton.isEnabled = result
        editButton.isEnabled = result
        templateChip.isEnabled = stage != .generating && stage != .conflict
        // Deliberately left interactive in every stage: in the result the tap
        // expands the collapsed quote, and while generating it still scrolls.
        // What a tap DOES is decided by `sourceTapped`, not by disabling it.
        sourceTextView.isUserInteractionEnabled = true
    }

    // MARK: Text target

    /// Keys route here while the composer is open. Deliberately storage-based
    /// rather than `UIKeyInput`, so editing behaves identically whether or not
    /// the system granted first responder inside the extension.
    func insertText(_ text: String) {
        guard acceptsTextInput, let view = focusedTextView else { return }
        let current = (view.text ?? "") as NSString
        let range = clampedSelection(in: current, of: view)

        // The instruction has a hard limit, and the honest place to enforce it
        // is the keystroke that would exceed it. Letting it be typed and then
        // cutting it silently at request time means the user sends something
        // they never saw.
        if view === instructionTextView {
            let resulting = current.replacingCharacters(in: range, with: text)
            guard resulting.unicodeScalars.count <= ReplyInstruction.maximumCharacters else { return }
        }
        view.text = current.replacingCharacters(in: range, with: text)
        let caret = range.location + (text as NSString).length
        view.selectedRange = NSRange(location: caret, length: 0)
        textsDidChange()
    }

    func deleteBackward() {
        guard acceptsTextInput, let view = focusedTextView else { return }
        let current = (view.text ?? "") as NSString
        let range = clampedSelection(in: current, of: view)

        if range.length > 0 {
            view.text = current.replacingCharacters(in: range, with: "")
            view.selectedRange = NSRange(location: range.location, length: 0)
        } else if range.location > 0 {
            // Composed-character aware, so emoji and combining marks delete whole.
            let target = current.rangeOfComposedCharacterSequence(at: range.location - 1)
            view.text = current.replacingCharacters(in: target, with: "")
            view.selectedRange = NSRange(location: target.location, length: 0)
        } else {
            return
        }
        textsDidChange()
    }

    var textBeforeCursor: String? {
        guard let view = focusedTextView else { return nil }
        let current = (view.text ?? "") as NSString
        let location = min(max(view.selectedRange.location, 0), current.length)
        return current.substring(to: location)
    }

    private func clampedSelection(in string: NSString, of view: UITextView) -> NSRange {
        var range = view.selectedRange
        if range.location == NSNotFound || range.location > string.length {
            range = NSRange(location: string.length, length: 0)
        }
        if range.location + range.length > string.length {
            range.length = max(0, string.length - range.location)
        }
        return range
    }

    /// - Parameter remeasure: `true` only when the text changed because of a
    ///   paste, a clear, a quick intent or a generated result - i.e. an event,
    ///   not a keystroke. Typing deliberately does not re-measure, so it cannot
    ///   move the keyboard.
    private func textsDidChange(remeasure: Bool = false) {
        // Typing is the user saying "I know, let me fix it". The message goes,
        // the content stays.
        if errorMessage != nil {
            errorMessage = nil
            errorLabel.isHidden = true
        }
        refreshControls()
        refreshGenerateTitle()
        recalculate(remeasure: remeasure)
        if let view = focusedTextView {
            view.scrollRangeToVisible(view.selectedRange)
        }
        updateFallbackCaret()
        delegate?.composerDidEditText(self)
    }

    // MARK: Measurement

    private struct Heights {
        var sourceText: CGFloat = 0
        var sourceCard: CGFloat = 0
        var instruction: CGFloat = 0
        var draft: CGFloat = 0
        var draftCaption: CGFloat = 0
        var error: CGFloat = 0
        var total: CGFloat = 0
    }

    /// On a screen with no room to spare the "Your reply" caption is the first
    /// thing to go: in the result stage the reply is the only editable field on
    /// screen and it sits next to Insert, so the label is a nicety and the two
    /// lines of reply it costs are not.
    private var showsDraftCaption: Bool { maximumHeight >= 215 }

    /// Vertical chrome inside the source card: 4 above the caption, the 14pt
    /// caption, 2 below it, 6 at the bottom.
    private let sourceCardChrome: CGFloat = 26
    private let sourceInsetV: CGFloat = 10
    private let fieldInsetV: CGFloat = 14

    private func lines(_ font: UIFont, _ count: Int, inset: CGFloat) -> CGFloat {
        (font.lineHeight * CGFloat(count) + inset).rounded(.up)
    }

    /// Shrinks two growable areas toward their minimums, proportionally to how
    /// much slack each of them has.
    ///
    /// The alternative - starve one completely before touching the other - is
    /// what produced the original problem: a copied message crushed into one
    /// truncated line. Here a tight screen costs both of them a line rather
    /// than costing the source all of them.
    private static func fit(
        first: CGFloat, firstMinimum: CGFloat,
        second: CGFloat, secondMinimum: CGFloat,
        budget: CGFloat
    ) -> (CGFloat, CGFloat) {
        guard first + second > budget else { return (first, second) }
        let need = first + second - budget
        let firstSlack = max(0, first - firstMinimum)
        let secondSlack = max(0, second - secondMinimum)
        let totalSlack = firstSlack + secondSlack
        guard totalSlack > 0 else { return (first, second) }
        let firstCut = min(firstSlack, (need * firstSlack / totalSlack).rounded())
        let secondCut = min(secondSlack, need - firstCut)
        return (first - firstCut, second - secondCut)
    }

    /// Chrome that does not depend on content, read straight off the
    /// constraints above so the two cannot drift apart. There is no auto-layout
    /// chain from the instruction down to the action row - the panel's height
    /// is solved here - so these have to be right.
    private var composingChrome: CGFloat {
        // container insets 2+2, chip top 4, header, card top gap 4,
        // card->instruction gap, instruction->actions gap, action block,
        // bottom 8.
        4 + 4 + headerHeight + 4 + gap + gap + composeActionRowHeight + 8
    }

    private var resultChrome: CGFloat {
        // ... caption top gap, caption->draft 2, draft->actions gap, row, 8.
        4 + 4 + headerHeight + 4 + gap + 2 + gap + actionRowHeight + 8
    }

    /// Natural line counts of the two long texts.
    ///
    /// PERFORMANCE / STABILITY. These are refreshed on CONTENT events - a
    /// paste, a generated result, a width change - and never from a keystroke.
    /// The composer used to re-measure both text views inside `textsDidChange`,
    /// which meant every character typed into the instruction could change the
    /// panel's height and animate the whole keyboard. Pinning the measurement
    /// to content events is what makes the keyboard stand still while the user
    /// types; past the pinned size the field simply scrolls.
    private func remeasureContent(cardWidth: CGFloat) {
        let sourceWidth = cardWidth - cardPadding * 2 - quoteBarWidth - quoteGap
        sourceNaturalLines = naturalLines(sourceTextView, font: sourceFont, width: sourceWidth, inset: sourceInsetV)
        draftNaturalLines = naturalLines(draftTextView, font: draftFont, width: cardWidth, inset: fieldInsetV)
    }

    private func naturalLines(_ view: UITextView, font: UIFont, width: CGFloat, inset: CGFloat) -> Int {
        let measured = ceil(
            view.sizeThatFits(CGSize(width: max(width, 1), height: .greatestFiniteMagnitude)).height
        )
        let text = max(0, measured - inset)
        return max(1, Int((text / font.lineHeight).rounded(.up)))
    }

    private func solveHeights(cardWidth: CGFloat) -> Heights {
        var heights = Heights()

        // One quoted line is always solved for, even while the card is
        // collapsed and hidden: the quote bar is pinned 3pt inside the text
        // view, so a zero-height text view would ask Auto Layout for a bar of
        // height -6.
        let oneSourceLine = lines(sourceFont, 1, inset: sourceInsetV)

        if stage == .conflict {
            heights.total = 122
            heights.sourceCard = 0
            heights.sourceText = oneSourceLine
            heights.instruction = instructionHeight?.constant ?? 51
            heights.draft = draftHeight?.constant ?? 72
            heights.draftCaption = draftCaptionHeight?.constant ?? captionHeight
            return heights
        }

        let isResult = stage == .result || stage == .editing
        let captionH: CGFloat = showsDraftCaption ? captionHeight : 0

        // Error row, measured before anything competes for what is left.
        if let message = errorMessage, !message.isEmpty {
            let fit = errorLabel.sizeThatFits(
                CGSize(width: cardWidth, height: .greatestFiniteMagnitude)
            ).height
            heights.error = min(30, max(15, ceil(fit)))
        }
        let errorBlock = heights.error > 0 ? heights.error + 4 : 0

        // THE COMPACT RULE. Collapsed, the copied message costs NOTHING here:
        // it is the one line beside the audience chip in the header. The card
        // only exists while the user has asked to read or edit the whole
        // message.
        let sourceCeilingLines = isResult ? 3 : 4
        var sourceCardH: CGFloat = 0
        var sourceTextH = oneSourceLine
        if isSourceExpanded {
            sourceTextH = lines(
                sourceFont,
                min(max(sourceNaturalLines, 1), sourceCeilingLines),
                inset: sourceInsetV
            )
            sourceCardH = sourceTextH + sourceCardChrome
        }
        let sourceFloor = isSourceExpanded ? oneSourceLine + sourceCardChrome : 0

        if isResult {
            // Three lines of reply is the comfortable floor and two is the
            // survivable one. An iPhone SE cannot afford three without the
            // keyboard eating most of the conversation.
            let draftMinimumLines = maximumHeight < 215 ? 2 : 3
            let draftMinimum = lines(draftFont, draftMinimumLines, inset: fieldInsetV)
            var draftH = lines(
                draftFont,
                min(max(draftNaturalLines, draftMinimumLines), 7),
                inset: fieldInsetV
            )
            let fixed = resultChrome + captionH + errorBlock
            (sourceCardH, draftH) = Self.fit(
                first: sourceCardH, firstMinimum: sourceFloor,
                second: draftH, secondMinimum: draftMinimum,
                budget: max(60, maximumHeight - fixed)
            )
            heights.sourceCard = sourceCardH
            heights.sourceText = max(oneSourceLine, sourceCardH - sourceCardChrome)
            heights.draft = draftH
            heights.draftCaption = captionH
            heights.instruction = instructionHeight?.constant ?? 51
            heights.total = fixed + sourceCardH + draftH
            return heights
        }

        // Composing / generating.
        //
        // The instruction field's height is a function of the BUDGET, never of
        // what has been typed into it. That is deliberate: it is a single
        // comfortable field that scrolls, rather than a field that grows a line
        // at a time and takes the whole keyboard with it.
        let instructionMinimum = lines(instructionFont, 1, inset: fieldInsetV)
        var instructionH = lines(instructionFont, maximumHeight < 200 ? 1 : 2, inset: fieldInsetV)
        let fixed = composingChrome + errorBlock
        (sourceCardH, instructionH) = Self.fit(
            first: sourceCardH, firstMinimum: sourceFloor,
            second: instructionH, secondMinimum: instructionMinimum,
            budget: max(60, maximumHeight - fixed)
        )

        heights.sourceCard = sourceCardH
        heights.sourceText = max(oneSourceLine, sourceCardH - sourceCardChrome)
        heights.instruction = instructionH
        heights.draft = draftHeight?.constant ?? 72
        heights.draftCaption = captionH
        heights.total = fixed + sourceCardH + instructionH
        return heights
    }

    /// - Parameter remeasure: whether the long texts should be measured again.
    ///   A keystroke passes `false`; a content event passes `true`. See
    ///   `remeasureContent`.
    private func recalculate(force: Bool = false, remeasure: Bool = false) {
        guard layoutWidth > 0 else { return }
        let containerWidth = layoutWidth - outerInset * 2
        let cardWidth = containerWidth - cardInset * 2
        guard cardWidth > 60 else { return }

        if remeasure || force { remeasureContent(cardWidth: cardWidth) }
        let heights = solveHeights(cardWidth: cardWidth)
        let heightChanged = abs(heights.total - measuredHeight) > 0.5

        guard force || heightChanged
            || abs(heights.sourceText - (sourceTextHeight?.constant ?? 0)) > 0.5
            || abs(heights.instruction - (instructionHeight?.constant ?? 0)) > 0.5
            || abs(heights.draft - (draftHeight?.constant ?? 0)) > 0.5
            || abs(heights.error - (errorHeight?.constant ?? 0)) > 0.5
            || abs(heights.draftCaption - (draftCaptionHeight?.constant ?? 0)) > 0.5
        else { return }

        sourceTextHeight?.constant = heights.sourceText
        sourceCardHeight?.constant = heights.sourceCard
        draftCaptionHeight?.constant = heights.draftCaption
        instructionHeight?.constant = heights.instruction
        draftHeight?.constant = heights.draft
        errorHeight?.constant = heights.error
        measuredHeight = heights.total

        if heightChanged { delegate?.composerDidChangeHeight(self) }
    }

    // MARK: Caret fallback

    private func startCaretBlink() {
        guard caretTimer == nil else { return }
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

    /// UIKit draws its own caret when a text view is first responder. When an
    /// extension is not granted first responder, this draws one in the focused
    /// field instead, so the insertion point is always visible.
    private func updateFallbackCaret() {
        guard acceptsTextInput, let view = focusedTextView, !view.isFirstResponder else {
            fallbackCaret.isHidden = true
            return
        }
        if fallbackCaret.superview !== view {
            fallbackCaret.removeFromSuperview()
            view.addSubview(fallbackCaret)
        }
        let length = ((view.text ?? "") as NSString).length
        guard let position = view.position(
            from: view.beginningOfDocument,
            offset: min(max(view.selectedRange.location, 0), length)
        ) else {
            fallbackCaret.isHidden = true
            return
        }
        let rect = view.caretRect(for: position)
        guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.height.isFinite else {
            fallbackCaret.isHidden = true
            return
        }
        fallbackCaret.frame = CGRect(x: rect.minX, y: rect.minY, width: 2, height: rect.height)
        fallbackCaret.isHidden = false
        fallbackCaret.alpha = 1
    }

    private func placeCaret(in view: UITextView, at point: CGPoint) {
        guard let position = view.closestPosition(to: point) else { return }
        let offset = view.offset(from: view.beginningOfDocument, to: position)
        view.selectedRange = NSRange(location: offset, length: 0)
        updateFallbackCaret()
    }

    // MARK: Actions

    @objc private func templateChipTapped() {
        delegate?.composerDidTapChangeTemplate(self)
    }

    @objc private func closeTapped() {
        delegate?.composerDidTapClose(self)
    }

    @objc private func pasteTapped() {
        delegate?.composerDidTapPasteSource(self)
    }

    @objc private func clearSourceTapped() {
        sourceTextView.text = ""
        isSourceExpanded = false
        setFocus(.instruction)
        textsDidChange(remeasure: true)
    }

    @objc private func generateTapped() {
        guard stage == .composing else { return }
        delegate?.composerDidTapGenerate(self)
    }

    @objc private func intentTapped(_ sender: UIButton) {
        guard stage == .composing, strings.quickIntents.indices.contains(sender.tag) else { return }
        let phrase = strings.quickIntents[sender.tag].phrase
        setFocus(.instruction)
        let current = instructionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = current.isEmpty ? phrase : current + " " + phrase
        instructionTextView.text = ReplyInstruction.clamp(combined)
        moveCaretToEnd(instructionTextView)
        textsDidChange()
    }

    @objc private func backTapped() {
        delegate?.composerDidTapBack(self)
    }

    @objc private func regenerateTapped() {
        delegate?.composerDidTapRegenerate(self)
    }

    @objc private func editTapped() {
        guard stage == .result || stage == .editing else { return }
        setStage(.editing)
        moveCaretToEnd(draftTextView)
        updateFallbackCaret()
    }

    @objc private func insertTapped() {
        delegate?.composerDidTapInsert(self)
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

    /// The collapsed preview in the header: Paste when there is nothing
    /// copied yet, otherwise open the full card.
    @objc private func contextPreviewTapped() {
        guard stage != .generating, stage != .conflict else { return }
        if hasUsableSource {
            isSourceExpanded = true
            refreshControls()
            recalculate(force: true)
        } else {
            delegate?.composerDidTapPasteSource(self)
        }
    }

    @objc private func collapseSourceTapped() {
        isSourceExpanded = false
        if focus == .source { setFocus(.instruction) }
        refreshControls()
        recalculate(force: true)
    }

    @objc private func sourceTapped(_ recognizer: UITapGestureRecognizer) {
        switch stage {
        case .composing:
            setFocus(.source)
            placeCaret(in: sourceTextView, at: recognizer.location(in: sourceTextView))
        case .result, .editing:
            // The card is only on screen here because the user expanded it, and
            // the chevron in its caption row is what closes it again.
            break
        case .generating, .conflict:
            break
        }
    }

    @objc private func instructionTapped(_ recognizer: UITapGestureRecognizer) {
        guard stage == .composing else { return }
        setFocus(.instruction)
        placeCaret(in: instructionTextView, at: recognizer.location(in: instructionTextView))
    }

    @objc private func draftTapped(_ recognizer: UITapGestureRecognizer) {
        guard stage == .result || stage == .editing else { return }
        if stage == .result { setStage(.editing) }
        setFocus(.draft)
        placeCaret(in: draftTextView, at: recognizer.location(in: draftTextView))
    }
}

// MARK: - UITextViewDelegate

extension ReplyComposerView: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        textsDidChange()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        updateFallbackCaret()
    }
}

// MARK: - Quick actions

extension ReplyComposerView: QuickActionRowDelegate {

    func quickActionRow(_ row: QuickActionRow, didSelect intent: QuickIntent) {
        applyIntent(intent)
    }
}
