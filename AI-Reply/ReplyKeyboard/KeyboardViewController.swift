import UIKit

private struct KeyboardPageIdentity: Hashable {
    let language: KeyboardLanguage
    let plane: KeyboardPlane
    let includesInputModeSwitch: Bool

    var contentRowCount: Int {
        plane == .letters ? language.letterRows.count : plane.rows.count
    }

    var gridColumns: Int {
        plane == .letters ? language.gridColumns : plane.gridColumns
    }
}

private final class KeyboardPage {
    let identity: KeyboardPageIdentity
    let metrics: KeyboardMetrics
    let stack: UIStackView

    var characterButtons: [KeyButton] = []
    var shiftButtons: [KeyButton] = []
    var returnButtons: [KeyButton] = []
    /// Every key on the page, so a theme change can restyle in place instead of
    /// throwing the page away and rebuilding it.
    var allButtons: [KeyButton] = []

    /// Constraints pinning `stack` to the rows container, kept so the page can
    /// be detached from the view hierarchy completely while it is not the
    /// active one. `isHidden` excludes a view from DRAWING but not from Auto
    /// Layout, so leaving every cached page installed made a single layout pass
    /// solve every cached key rather than only the visible ones.
    var pinConstraints: [NSLayoutConstraint] = []

    var isInstalled: Bool { stack.superview != nil }

    init(identity: KeyboardPageIdentity, metrics: KeyboardMetrics) {
        self.identity = identity
        self.metrics = metrics
        self.stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.distribution = .fillEqually
        stack.spacing = metrics.rowGap
        stack.translatesAutoresizingMaskIntoConstraints = false
    }
}

/// Opting the input view into system key-click feedback. This is the only
/// reason `loadView()` is overridden; deleting both this type and `loadView()`
/// disables the click sound and changes nothing else.
final class ReplyInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

final class KeyboardViewController: UIInputViewController {

    // MARK: State

    /// The LAYOUT being typed on. Drives the character keys and their captions.
    private var language = KeyboardLanguageStore.load()

    /// The APP's interface language. Drives every product label - chips,
    /// Insert, Regenerate, statuses, errors - and nothing else.
    ///
    /// PERFORMANCE. Cached in memory and refreshed only when the keyboard
    /// appears. It is never read from the App Group on a keypress; the typing
    /// path does not touch `UserDefaults` at all.
    private var uiLanguage: AppLanguage = SharedSettings.shared.effectiveAppLanguage

    private var plane: KeyboardPlane = .letters
    private var isShifted = false
    private var isCapsLocked = false

    private var theme = KeyboardTheme(isDark: true)
    private var strings = KeyboardStrings.forLanguage(.english)
    private var metrics = KeyboardMetrics(width: 375, contentRowCount: 3)

    // MARK: Views

    private let actionBar = KeyboardActionBar()
    private let rowsContainer = UIView()

    private var heightConstraint: NSLayoutConstraint?
    private var actionBarHeightConstraint: NSLayoutConstraint?
    private var rowsTopConstraint: NSLayoutConstraint?
    private var rowsHeightConstraint: NSLayoutConstraint?

    private var pageCache: [KeyboardPageIdentity: KeyboardPage] = [:]
    private var activePage: KeyboardPage?
    private var characterButtons: [KeyButton] = []
    private var shiftButtons: [KeyButton] = []
    private var returnButtons: [KeyButton] = []
    private var renderedWidth: CGFloat = 0
    private var isUpdatingGeometry = false
    private var prewarmWorkItem: DispatchWorkItem?
    private var hasAppeared = false

    // MARK: Collaborators

    private let replyCoordinator = ReplyFlowCoordinator()
    /// Draft waiting on a Replace / Add decision because the host field already
    /// had text in it.
    private var pendingInsertion: String?
    /// Guards against reloading the configuration on every appearance when
    /// nothing has changed.
    private var configurationLoadedAt: TimeInterval = 0
    private var deleteRepeatTimer: Timer?
    private var lastShiftTap: TimeInterval = 0
    private var lastSpaceTap: TimeInterval = 0
    private var cachedHostContextBeforeInput: String?
    private var cachedHostAutocapitalization: UITextAutocapitalizationType = .sentences
    private var lastHostMutationTime: TimeInterval = 0
    private var lastAppearanceProbe: TimeInterval = 0

    // MARK: Lifecycle

    override func loadView() {
        let inputView = ReplyInputView(frame: .zero, inputViewStyle: .keyboard)
        inputView.allowsSelfSizing = true
        view = inputView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        strings = KeyboardStrings.forLanguage(language)
        replyCoordinator.delegate = self
        replyCoordinator.uiLanguage = uiLanguage
        actionBar.delegate = self
        // Seeded from the compact App Group summary, which is a property-list
        // read of a few hundred bytes, so the FIRST frame already shows this
        // user's own templates in their own language. The full configuration
        // still loads off the main thread a moment later for generation.
        actionBar.setChips(cachedChips())
        buildHierarchy()
        seedHeightFromCache()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (controller: KeyboardViewController, _) in
            controller.refreshThemeIfNeeded()
        }
        applyTheme(KeyboardTheme.resolve(
            appearance: textDocumentProxy.keyboardAppearance ?? .default,
            traits: traitCollection
        ), rerender: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        lastAppearanceProbe = Date.timeIntervalSinceReferenceDate
        refreshUILanguageIfNeeded()
        refreshThemeIfNeeded()
        refreshAutoShift(allowProxyRead: true)
        refreshReturnKey()
        loadConfigurationIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // The keyboard is going away. Cancel any request in flight and drop the
        // copied message and the draft with it - there is nothing left to show
        // them in, and holding private text past the moment it is useful is
        // exactly what this app promises not to do.
        if replyCoordinator.isComposing || replyCoordinator.isGenerating {
            replyCoordinator.clear()
            pendingInsertion = nil
            actionBar.endComposing()
            updateGeometry()
        }
    }

    /// PERFORMANCE. Profile and templates are read ONCE per appearance, off the
    /// main thread, and never during a keypress. `ProfileStore` additionally
    /// skips decoding when the file has not changed, so a keyboard that opens
    /// and closes repeatedly inside one messenger session pays a `stat` rather
    /// than a JSON decode.
    private func loadConfigurationIfNeeded() {
        let now = Date.timeIntervalSinceReferenceDate
        guard now - configurationLoadedAt > 1.0 else { return }
        configurationLoadedAt = now

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let configuration = ProfileStore.shared.load()
            DispatchQueue.main.async {
                guard let self else { return }
                self.replyCoordinator.configuration = configuration
                self.actionBar.setChips(self.chips(for: configuration))
            }
        }
    }

    /// The template row as the app last saved it, or the defaults on a fresh
    /// install. One small property-list read, only when the keyboard appears.
    private func cachedChips() -> [TemplateChip] {
        if let summaries = SharedSettings.shared.templateSummaries {
            return summaries.map { TemplateChip(id: $0.id, name: $0.name(for: uiLanguage)) }
        }
        return chips(for: .initial)
    }

    private func chips(for configuration: ReplyConfiguration) -> [TemplateChip] {
        configuration.visibleTemplates.map {
            TemplateChip(id: $0.id, name: $0.displayName(appLanguage: uiLanguage))
        }
    }

    /// Picks up a language the user changed in the containing app while this
    /// keyboard was loaded but off screen.
    ///
    /// Only on appearance, and only when the value actually changed - relabelling
    /// the chips is cheap, but doing it for nothing on every appearance is still
    /// work the typing path would eventually pay for.
    private func refreshUILanguageIfNeeded() {
        let current = SharedSettings.shared.effectiveAppLanguage
        guard current != uiLanguage else { return }
        uiLanguage = current
        replyCoordinator.uiLanguage = current
        actionBar.configure(theme: theme, uiLanguage: current)
        actionBar.setChips(chips(for: replyCoordinator.configuration))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Nothing optional runs before the keyboard is actually on screen.
        hasAppeared = true
        scheduleIdlePrewarm()
        reportActivityToContainingApp()
    }

    /// Lets the containing app show a truthful keyboard status. Throttled and
    /// off the main thread: it must never sit in the appearance path.
    private func reportActivityToContainingApp() {
        let fullAccess = hasFullAccess
        let settings = SharedSettings.shared
        let lastSeen = settings.keyboardLastSeen
        let isStale = lastSeen.map { Date().timeIntervalSince($0) > 300 } ?? true
        guard isStale || settings.keyboardHasFullAccess != fullAccess else { return }
        DispatchQueue.global(qos: .utility).async {
            settings.markKeyboardActive(hasFullAccess: fullAccess)
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let width = view.bounds.width
        guard width > 0 else { return }
        if abs(width - renderedWidth) > 0.5 {
            invalidateKeyboardPages()
            renderedWidth = width
            rebuild()
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        let now = Date.timeIntervalSinceReferenceDate
        let localMutationIsFresh = now - lastHostMutationTime < 0.45

        // PERFORMANCE. Every `textDocumentProxy` property is a cross-process
        // read. `textDidChange` fires after every single character, so probing
        // the host's appearance here put an XPC round-trip in the typing hot
        // path. Our own insertions can never change the host's appearance, and
        // when the host does change it a probe within half a second is soon
        // enough for a colour swap.
        if !localMutationIsFresh, now - lastAppearanceProbe > 0.5 {
            lastAppearanceProbe = now
            refreshThemeIfNeeded()
        }

        refreshAutoShift(allowProxyRead: !localMutationIsFresh)
        if !localMutationIsFresh {
            refreshReturnKey()
        }
    }

    deinit {
        deleteRepeatTimer?.invalidate()
        prewarmWorkItem?.cancel()
    }

    // MARK: Hierarchy

    private func buildHierarchy() {
        view.addSubview(actionBar)
        rowsContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rowsContainer)

        let barHeight = actionBar.heightAnchor.constraint(equalToConstant: metrics.actionBarHeight)
        let rowsTop = rowsContainer.topAnchor.constraint(
            equalTo: actionBar.bottomAnchor,
            constant: metrics.actionBarGap + metrics.topPadding
        )
        let rowsHeight = rowsContainer.heightAnchor.constraint(equalToConstant: 200)

        actionBarHeightConstraint = barHeight
        rowsTopConstraint = rowsTop
        rowsHeightConstraint = rowsHeight

        NSLayoutConstraint.activate([
            actionBar.topAnchor.constraint(equalTo: view.topAnchor),
            actionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            actionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            barHeight,
            rowsTop,
            rowsHeight,
            rowsContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: metrics.sidePadding),
            rowsContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -metrics.sidePadding)
        ])
    }

    /// Installs the height constraint from the last measured idle height,
    /// before anything has been laid out.
    ///
    /// PERFORMANCE. The height constraint used to be created inside the first
    /// `updateGeometry()`, i.e. during the first layout pass. Until then the
    /// system sizes the input view itself, so every appearance of this keyboard
    /// began with a visible resize. A cached height makes the first frame
    /// correct; if it is stale the first real layout overwrites it in the same
    /// pass, so there is no case where this makes things worse.
    private func seedHeightFromCache() {
        guard heightConstraint == nil,
              let cached = SharedSettings.shared.keyboardHeight else { return }
        let constraint = view.heightAnchor.constraint(equalToConstant: CGFloat(cached.height))
        constraint.priority = UILayoutPriority(999)
        constraint.isActive = true
        heightConstraint = constraint
    }

    // MARK: Theme

    private func refreshThemeIfNeeded() {
        let resolved = KeyboardTheme.resolve(
            appearance: textDocumentProxy.keyboardAppearance ?? .default,
            traits: traitCollection
        )
        guard resolved != theme else { return }
        applyTheme(resolved, rerender: true)
    }

    private func applyTheme(_ newTheme: KeyboardTheme, rerender: Bool) {
        theme = newTheme
        view.backgroundColor = theme.background
        view.tintColor = theme.primaryText
        actionBar.configure(theme: theme, uiLanguage: uiLanguage)
        guard rerender else { return }

        // A colour change invalidates no geometry, so restyle the cached keys
        // in place. Discarding the page cache and rebuilding every layout was a
        // visible hitch whenever the host app flipped between light and dark
        // while the keyboard was up.
        UIView.performWithoutAnimation {
            for page in pageCache.values {
                for button in page.allButtons {
                    configureAppearance(button, identity: page.identity, metrics: page.metrics)
                }
            }
        }
    }

    // MARK: Layout pipeline

    private var contentRowCount: Int {
        plane == .letters ? language.letterRows.count : plane.rows.count
    }

    private var activePageIdentity: KeyboardPageIdentity {
        KeyboardPageIdentity(
            language: language,
            plane: plane,
            includesInputModeSwitch: needsInputModeSwitchKey
        )
    }

    private func rebuild() {
        metrics = KeyboardMetrics(width: max(view.bounds.width, 1), contentRowCount: contentRowCount)
        displayActiveKeyboardPage()
        updateGeometry()
        scheduleIdlePrewarm()
    }

    private func updateGeometry() {
        isUpdatingGeometry = true
        defer { isUpdatingGeometry = false }

        actionBar.layout(forWidth: metrics.width)
        activePage?.stack.spacing = metrics.rowGap
        rowsTopConstraint?.constant = metrics.actionBarGap + metrics.topPadding

        let rows = CGFloat(metrics.rowCount)
        let rowsHeight = rows * metrics.keyHeight + (rows - 1) * metrics.rowGap
        rowsHeightConstraint?.constant = rowsHeight

        // The keys never give up height: the keyboard grows for the composer.
        let barHeight = max(metrics.actionBarHeight, actionBar.preferredHeight)
        actionBarHeightConstraint?.constant = barHeight

        let total = barHeight + metrics.actionBarGap + metrics.topPadding + rowsHeight + metrics.bottomPadding

        // Only the IDLE height is cached. Seeding a future launch with the
        // taller composing height would open the keyboard oversized.
        if !actionBar.isComposing {
            let cached = SharedSettings.shared.keyboardHeight
            if cached?.height != Double(total) || cached?.width != Double(metrics.width) {
                // Off the main thread: nothing in this layout pass reads it
                // back, and it only matters to the NEXT launch.
                let height = Double(total)
                let width = Double(metrics.width)
                DispatchQueue.global(qos: .utility).async {
                    SharedSettings.shared.setKeyboardHeight(height, width: width)
                }
            }
        }

        if let constraint = heightConstraint {
            if abs(constraint.constant - total) > 0.5 { constraint.constant = total }
        } else {
            let constraint = view.heightAnchor.constraint(equalToConstant: total)
            // The system installs its own height constraint on the input view;
            // 999 wins against it without becoming unsatisfiable.
            constraint.priority = UILayoutPriority(999)
            constraint.isActive = true
            heightConstraint = constraint
        }

        ReplyLog.event(String(
            format: "layout w=%.0f rows=%d key=%.0f total=%.0f typing=%.0f%%",
            metrics.width, metrics.rowCount, metrics.keyHeight, total,
            (metrics.typingHeight / max(total, 1)) * 100
        ))
    }

    // MARK: Rendering

    private func displayActiveKeyboardPage() {
        let identity = activePageIdentity
        let page = ensureKeyboardPage(for: identity, width: metrics.width)

        if page !== activePage {
            if let previous = activePage { detach(previous) }
            install(page)
        }

        activePage = page
        characterButtons = page.characterButtons
        shiftButtons = page.shiftButtons
        returnButtons = page.returnButtons

        refreshCharacterTitles()
        refreshShiftAppearance()
        refreshReturnKey()
    }

    private func invalidateKeyboardPages() {
        prewarmWorkItem?.cancel()
        prewarmWorkItem = nil
        for page in pageCache.values {
            detach(page)
        }
        pageCache.removeAll()
        activePage = nil
        characterButtons.removeAll()
        shiftButtons.removeAll()
        returnButtons.removeAll()
    }

    private func ensureKeyboardPage(for identity: KeyboardPageIdentity, width: CGFloat) -> KeyboardPage {
        if let cached = pageCache[identity] {
            return cached
        }

        let pageMetrics = KeyboardMetrics(width: max(width, 1), contentRowCount: identity.contentRowCount)
        let page = makeKeyboardPage(for: identity, metrics: pageMetrics)
        // Deliberately NOT added to the hierarchy here. A cached page that is
        // not on screen must cost construction only; `install` puts it in when
        // it becomes the active page.
        pageCache[identity] = page
        return page
    }

    private func install(_ page: KeyboardPage) {
        guard page.stack.superview !== rowsContainer else { return }
        page.stack.isHidden = false
        rowsContainer.addSubview(page.stack)
        let pins = [
            page.stack.leadingAnchor.constraint(equalTo: rowsContainer.leadingAnchor),
            page.stack.trailingAnchor.constraint(equalTo: rowsContainer.trailingAnchor),
            page.stack.topAnchor.constraint(equalTo: rowsContainer.topAnchor),
            page.stack.bottomAnchor.constraint(equalTo: rowsContainer.bottomAnchor)
        ]
        NSLayoutConstraint.activate(pins)
        page.pinConstraints = pins
    }

    private func detach(_ page: KeyboardPage) {
        guard page.isInstalled else { return }
        NSLayoutConstraint.deactivate(page.pinConstraints)
        page.pinConstraints = []
        page.stack.removeFromSuperview()
    }

    private func makeKeyboardPage(for identity: KeyboardPageIdentity, metrics: KeyboardMetrics) -> KeyboardPage {
        let page = KeyboardPage(identity: identity, metrics: metrics)
        if identity.plane == .letters {
            renderLetterRows(into: page, metrics: metrics)
        } else {
            renderPlaneRows(into: page, metrics: metrics)
        }
        page.stack.addArrangedSubview(makeBottomRow(for: identity, page: page, metrics: metrics))
        return page
    }

    /// Builds at most ONE not-yet-cached letter page per idle tick, starting
    /// with the language the language key will switch to next.
    ///
    /// PERFORMANCE. The previous version built all three language layouts in a
    /// single `DispatchQueue.main.async` block scheduled from `rebuild()` -
    /// roughly 120 `UIButton`s, their SF Symbol image lookups and their
    /// constraints, on the main thread, at the exact moment the user had just
    /// switched to this keyboard and was waiting to see it. That block is the
    /// main reason switching to the keyboard stuttered. Now nothing is
    /// prewarmed until the keyboard is actually on screen, and the work is
    /// spread one page per runloop turn so no single turn is long enough to
    /// drop a frame.
    private func scheduleIdlePrewarm() {
        guard hasAppeared else { return }
        prewarmWorkItem?.cancel()
        prewarmWorkItem = nil

        let width = renderedWidth
        guard width > 0 else { return }

        let includesInputModeSwitch = needsInputModeSwitchKey
        let order: [KeyboardLanguage] = [language.next, language.next.next, language]
        let pending = order
            .map {
                KeyboardPageIdentity(
                    language: $0,
                    plane: .letters,
                    includesInputModeSwitch: includesInputModeSwitch
                )
            }
            .first { pageCache[$0] == nil }
        guard let next = pending else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.prewarmWorkItem = nil
            guard abs(self.renderedWidth - width) <= 0.5 else { return }
            if self.pageCache[next] == nil {
                UIView.performWithoutAnimation {
                    _ = self.ensureKeyboardPage(for: next, width: width)
                }
            }
            self.scheduleIdlePrewarm()
        }
        prewarmWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func renderLetterRows(into page: KeyboardPage, metrics: KeyboardMetrics) {
        let language = page.identity.language
        let rows = language.letterRows
        let columns = language.gridColumns
        let unit = metrics.unitWidth(columns: columns)

        for (index, row) in rows.enumerated() {
            let keys = row.map { KeyboardKey.character($0) }
            if language.rowFillsWidth(at: index) {
                page.stack.addArrangedSubview(makeEvenRow(keys, page: page, metrics: metrics))
            } else if index == rows.count - 1 {
                page.stack.addArrangedSubview(makeShiftedRow(keys, unit: unit, page: page, metrics: metrics))
            } else {
                page.stack.addArrangedSubview(makeGridRow(keys, unit: unit, columns: columns, page: page, metrics: metrics))
            }
        }
    }

    private func renderPlaneRows(into page: KeyboardPage, metrics: KeyboardMetrics) {
        let plane = page.identity.plane
        let rows = plane.rows
        let unit = metrics.unitWidth(columns: plane.gridColumns)

        for (index, row) in rows.enumerated() {
            let keys = row.map { KeyboardKey.character($0) }
            if index == rows.count - 1 {
                let alternate: KeyboardPlaneTarget = plane == .numbers ? .symbols : .numbers
                let full: [KeyboardKey] = [.plane(alternate)] + keys + [.backspace]
                page.stack.addArrangedSubview(makeEvenRow(full, page: page, metrics: metrics))
            } else {
                page.stack.addArrangedSubview(makeGridRow(keys, unit: unit, columns: plane.gridColumns, page: page, metrics: metrics))
            }
        }
    }

    /// Row whose keys sit on the shared grid, centred when it holds fewer keys
    /// than the grid has columns.
    private func makeGridRow(_ keys: [KeyboardKey], unit: CGFloat, columns: Int, page: KeyboardPage, metrics: KeyboardMetrics) -> UIStackView {
        let row = makeRowStack(metrics: metrics)
        let needsPadding = keys.count < columns

        var leadingSpacer: KeyRowSpacer?
        if needsPadding {
            let spacer = KeyRowSpacer()
            leadingSpacer = spacer
            row.addArrangedSubview(spacer)
        }

        for key in keys {
            let button = makeButton(for: key, page: page, metrics: metrics)
            pin(button, width: unit)
            row.addArrangedSubview(button)
        }

        if let leadingSpacer {
            let trailingSpacer = KeyRowSpacer()
            row.addArrangedSubview(trailingSpacer)
            trailingSpacer.widthAnchor.constraint(equalTo: leadingSpacer.widthAnchor).isActive = true
        }
        return row
    }

    /// Last letter row: shift, the letters, delete. Shift and delete absorb the
    /// leftover width so they stay comfortably wide.
    private func makeShiftedRow(_ keys: [KeyboardKey], unit: CGFloat, page: KeyboardPage, metrics: KeyboardMetrics) -> UIStackView {
        let row = makeRowStack(metrics: metrics)
        let slots = keys.count + 2
        let gaps = CGFloat(slots - 1) * metrics.columnGap
        let leftover = metrics.availableRowWidth - gaps - CGFloat(keys.count) * unit
        let sideWidth = max(unit, (leftover / 2).rounded(.down))

        let shift = makeButton(for: .shift, page: page, metrics: metrics)
        pin(shift, width: sideWidth)
        if sideWidth < 40 { shift.touchInset = -3 }
        row.addArrangedSubview(shift)

        for key in keys {
            let button = makeButton(for: key, page: page, metrics: metrics)
            pin(button, width: unit)
            row.addArrangedSubview(button)
        }

        let backspace = makeButton(for: .backspace, page: page, metrics: metrics)
        pin(backspace, width: sideWidth)
        if sideWidth < 40 { backspace.touchInset = -3 }
        row.addArrangedSubview(backspace)
        return row
    }

    /// Row that spreads its keys edge to edge (Kazakh letter row, symbol rows).
    private func makeEvenRow(_ keys: [KeyboardKey], page: KeyboardPage, metrics: KeyboardMetrics) -> UIStackView {
        let row = makeRowStack(metrics: metrics)
        row.distribution = .fillEqually
        keys.map { makeButton(for: $0, page: page, metrics: metrics) }.forEach(row.addArrangedSubview)
        return row
    }

    private func makeBottomRow(for identity: KeyboardPageIdentity, page: KeyboardPage, metrics: KeyboardMetrics) -> UIStackView {
        let row = makeRowStack(metrics: metrics)
        let planeTarget: KeyboardPlaneTarget = identity.plane == .letters ? .numbers : .letters

        let planeKey = makeButton(for: .plane(planeTarget), page: page, metrics: metrics)
        pin(planeKey, width: metrics.controlKeyWidth)
        row.addArrangedSubview(planeKey)

        // Preserve system keyboard switching exactly as iOS expects it: tap
        // advances, long press opens the system input-mode list.
        if identity.includesInputModeSwitch {
            let globe = makeButton(for: .globe, page: page, metrics: metrics)
            pin(globe, width: metrics.controlKeyWidth)
            row.addArrangedSubview(globe)
        }

        let languageKey = makeButton(for: .language, page: page, metrics: metrics)
        pin(languageKey, width: metrics.controlKeyWidth)
        row.addArrangedSubview(languageKey)

        let space = makeButton(for: .space, page: page, metrics: metrics)
        space.setContentHuggingPriority(.defaultLow, for: .horizontal)
        space.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(space)

        let returnKey = makeButton(for: .ret, page: page, metrics: metrics)
        pin(returnKey, width: metrics.returnKeyWidth)
        row.addArrangedSubview(returnKey)

        return row
    }

    /// Key widths are pinned just below `required` so sub-point rounding can
    /// never produce an unsatisfiable row.
    private func pin(_ button: KeyButton, width: CGFloat) {
        let constraint = button.widthAnchor.constraint(equalToConstant: width)
        constraint.priority = UILayoutPriority(999)
        constraint.isActive = true
    }

    private func makeRowStack(metrics: KeyboardMetrics) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .fill
        row.distribution = .fill
        row.spacing = metrics.columnGap
        return row
    }

    // MARK: Buttons

    private func makeButton(for key: KeyboardKey, page: KeyboardPage, metrics: KeyboardMetrics) -> KeyButton {
        let button = KeyButton(key: key)
        configureAppearance(button, identity: page.identity, metrics: metrics)
        attachActions(to: button)
        page.allButtons.append(button)
        if case .character = key { page.characterButtons.append(button) }
        if case .shift = key { page.shiftButtons.append(button) }
        if case .ret = key { page.returnButtons.append(button) }
        return button
    }

    private func configureAppearance(_ button: KeyButton, identity: KeyboardPageIdentity? = nil, metrics: KeyboardMetrics? = nil) {
        let identity = identity ?? activePageIdentity
        let metrics = metrics ?? activePage?.metrics ?? self.metrics
        let strings = KeyboardStrings.forLanguage(identity.language)

        switch button.key {
        case .character(let value):
            let title = identity.plane == .letters ? displayed(value) : value
            let compact = metrics.unitWidth(columns: identity.gridColumns) < 30
            button.setText(title, size: metrics.fontSize(for: compact ? .compactCharacter : .character))
            button.apply(style: .letter, theme: theme, metrics: metrics)

        case .shift:
            let symbol = isCapsLocked ? "capslock.fill" : (isShifted ? "shift.fill" : "shift")
            button.setSymbol(symbol, pointSize: 17, weight: .light)
            button.apply(style: (isShifted || isCapsLocked) ? .engaged : .special, theme: theme, metrics: metrics)

        case .backspace:
            button.setSymbol("delete.left", pointSize: 17, weight: .light)
            button.apply(style: .special, theme: theme, metrics: metrics)

        case .plane(let target):
            button.setText(target.title, size: metrics.fontSize(for: .control), weight: .regular)
            button.apply(style: .special, theme: theme, metrics: metrics)

        case .globe:
            button.setSymbol("globe", pointSize: 17, weight: .light)
            button.apply(style: .special, theme: theme, metrics: metrics)

        case .language:
            button.setText(strings.languageBadge, size: 13, weight: .semibold)
            button.apply(style: .special, theme: theme, metrics: metrics)

        case .space:
            button.setText(strings.spaceKey, size: metrics.fontSize(for: .space))
            button.apply(style: .letter, theme: theme, metrics: metrics)

        case .ret:
            let type: UIReturnKeyType = isComposing ? .default : (textDocumentProxy.returnKeyType ?? .default)
            button.setText(strings.returnLabel(for: type), size: metrics.fontSize(for: .control))
            let prominent = KeyboardStrings.returnKeyIsProminent(type)
            button.apply(style: prominent ? .prominent : .special, theme: theme, metrics: metrics)
        }
    }

    private func attachActions(to button: KeyButton) {
        switch button.key {
        case .globe:
            button.addTarget(
                self,
                action: #selector(handleInputModeList(from:with:)),
                for: .allTouchEvents
            )
        case .backspace:
            button.addTarget(self, action: #selector(backspaceDown(_:)), for: .touchDown)
            button.addTarget(
                self,
                action: #selector(backspaceUp(_:)),
                for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit]
            )
        default:
            let event: UIControl.Event = button.key.firesOnTouchDown ? .touchDown : .touchUpInside
            button.addTarget(self, action: #selector(keyPressed(_:)), for: event)
        }
    }

    // MARK: Input routing

    /// The keyboard has exactly two possible destinations for a key press and
    /// never guesses between them: the host application's field, or the reply
    /// draft inside the composer.
    private var isComposing: Bool { actionBar.isComposing }

    /// Where a keystroke goes. While the composer is open and editable, keys
    /// edit the LOCAL DRAFT and never reach WhatsApp; while a request is in
    /// flight they are dropped rather than leaking into the host field.
    private enum InputTarget {
        case hostField
        case replyDraft
        case discarded
    }

    private var inputTarget: InputTarget {
        guard actionBar.isComposing else { return .hostField }
        return actionBar.acceptsDraftInput ? .replyDraft : .discarded
    }

    private func targetInsert(_ text: String) {
        switch inputTarget {
        case .hostField:  insertIntoHost(text)
        case .replyDraft: actionBar.insertText(text)
        case .discarded:  break
        }
    }

    private func targetDeleteBackward() {
        switch inputTarget {
        case .hostField:  deleteFromHost()
        case .replyDraft: actionBar.deleteBackward()
        case .discarded:  break
        }
    }

    private func insertIntoHost(_ text: String) {
        textDocumentProxy.insertText(text)
        recordHostInsertion(text)
    }

    private func deleteFromHost() {
        textDocumentProxy.deleteBackward()
        recordHostDeletion()
    }

    private func targetTextBeforeCursor(allowProxyRead: Bool) -> String? {
        if inputTarget != .hostField {
            return actionBar.textBeforeCursor
        }
        if allowProxyRead || cachedHostContextBeforeInput == nil {
            refreshCachedHostContextFromProxy()
        }
        return cachedHostContextBeforeInput
    }

    private var targetAutocapitalization: UITextAutocapitalizationType {
        inputTarget == .hostField ? cachedHostAutocapitalization : .sentences
    }

    private func refreshCachedHostContextFromProxy() {
        let context = textDocumentProxy.documentContextBeforeInput ?? ""
        cachedHostContextBeforeInput = String(context.suffix(180))
        cachedHostAutocapitalization = textDocumentProxy.autocapitalizationType ?? .sentences
    }

    private func recordHostInsertion(_ text: String) {
        guard !text.isEmpty else { return }
        var context = cachedHostContextBeforeInput ?? ""
        context.append(text)
        cachedHostContextBeforeInput = String(context.suffix(180))
        lastHostMutationTime = Date.timeIntervalSinceReferenceDate
    }

    private func recordHostDeletion() {
        guard var context = cachedHostContextBeforeInput, !context.isEmpty else {
            lastHostMutationTime = Date.timeIntervalSinceReferenceDate
            return
        }
        context.removeLast()
        cachedHostContextBeforeInput = String(context.suffix(180))
        lastHostMutationTime = Date.timeIntervalSinceReferenceDate
    }

    // MARK: Key handling

    @objc private func keyPressed(_ sender: KeyButton) {
        UIDevice.current.playInputClick()
        switch sender.key {
        case .character(let value):
            insertCharacter(plane == .letters ? displayed(value) : value)
        case .shift:
            toggleShift()
        case .space:
            insertSpace()
        case .ret:
            targetInsert("\n")
            refreshAutoShift()
        case .plane(let target):
            plane = target.plane
            isShifted = false
            isCapsLocked = false
            UIView.performWithoutAnimation {
                rebuild()
                view.layoutIfNeeded()
            }
            refreshAutoShift()
        case .language:
            cycleLanguage()
        case .globe, .backspace:
            break
        }
    }

    private func displayed(_ value: String) -> String {
        (isShifted || isCapsLocked) ? value.uppercased() : value
    }

    private func insertCharacter(_ value: String) {
        targetInsert(value)
        if plane == .letters, isShifted, !isCapsLocked {
            isShifted = false
            refreshCharacterTitles()
            refreshShiftAppearance()
        }
        refreshAutoShift()
    }

    private func insertSpace() {
        let now = Date.timeIntervalSinceReferenceDate
        let before = targetTextBeforeCursor(allowProxyRead: false) ?? ""
        let doubleTap = now - lastSpaceTap < 0.35
        let previous = before.dropLast().last

        if doubleTap, before.hasSuffix(" "), let previous, previous.isLetter || previous.isNumber {
            targetDeleteBackward()
            targetInsert(". ")
            lastSpaceTap = 0
        } else {
            targetInsert(" ")
            lastSpaceTap = now
        }
        refreshAutoShift()
    }

    private func toggleShift() {
        let now = Date.timeIntervalSinceReferenceDate
        if now - lastShiftTap < 0.35 {
            isCapsLocked = true
            isShifted = true
        } else if isCapsLocked {
            isCapsLocked = false
            isShifted = false
        } else {
            isShifted.toggle()
        }
        lastShiftTap = now
        refreshCharacterTitles()
        refreshShiftAppearance()
    }

    private func cycleLanguage() {
        language = language.next
        KeyboardLanguageStore.saveAsync(language)
        strings = KeyboardStrings.forLanguage(language)
        plane = .letters
        isShifted = false
        isCapsLocked = false
        actionBar.configure(theme: theme, uiLanguage: uiLanguage)
        UIView.performWithoutAnimation {
            rebuild()
            view.layoutIfNeeded()
        }
        refreshAutoShift()
    }

    // MARK: Delete repeat

    @objc private func backspaceDown(_ sender: KeyButton) {
        UIDevice.current.playInputClick()
        targetDeleteBackward()
        deleteRepeatTimer?.invalidate()
        let timer = Timer(timeInterval: 0.45, repeats: false) { [weak self] _ in
            self?.startAcceleratedDelete()
        }
        RunLoop.main.add(timer, forMode: .common)
        deleteRepeatTimer = timer
    }

    private func startAcceleratedDelete() {
        deleteRepeatTimer?.invalidate()
        let timer = Timer(timeInterval: 0.085, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.targetDeleteBackward()
        }
        RunLoop.main.add(timer, forMode: .common)
        deleteRepeatTimer = timer
    }

    @objc private func backspaceUp(_ sender: KeyButton) {
        deleteRepeatTimer?.invalidate()
        deleteRepeatTimer = nil
        refreshAutoShift()
    }

    // MARK: Incremental refresh

    private func refreshCharacterTitles() {
        guard let activePage, activePage.identity.plane == .letters else { return }
        let metrics = activePage.metrics
        let compact = metrics.unitWidth(columns: activePage.identity.gridColumns) < 30
        let size = metrics.fontSize(for: compact ? .compactCharacter : .character)
        for button in characterButtons {
            guard case .character(let value) = button.key else { continue }
            button.setText(displayed(value), size: size)
        }
    }

    private func refreshShiftAppearance() {
        let metrics = activePage?.metrics ?? self.metrics
        for button in shiftButtons {
            let symbol = isCapsLocked ? "capslock.fill" : (isShifted ? "shift.fill" : "shift")
            button.setSymbol(symbol, pointSize: 17, weight: .light)
            button.apply(
                style: (isShifted || isCapsLocked) ? .engaged : .special,
                theme: theme,
                metrics: metrics
            )
        }
    }

    private func refreshReturnKey() {
        // Cheap enough: the return key is the only view that depends on the
        // host's returnKeyType and it can change while the keyboard is up.
        guard let activePage else { return }
        for button in returnButtons {
            configureAppearance(button, identity: activePage.identity, metrics: activePage.metrics)
        }
    }

    /// Turns shift on at sentence starts. It never turns shift off - that is
    /// handled once, at insertion time - so a manual shift is never fought.
    private func refreshAutoShift(allowProxyRead: Bool = false) {
        guard plane == .letters, !isCapsLocked, !isShifted else { return }
        guard targetAutocapitalization == .sentences else { return }
        guard Self.isAtSentenceStart(targetTextBeforeCursor(allowProxyRead: allowProxyRead)) else { return }
        isShifted = true
        refreshCharacterTitles()
        refreshShiftAppearance()
    }

    private static func isAtSentenceStart(_ context: String?) -> Bool {
        guard let context, !context.isEmpty else { return true }
        var index = context.endIndex
        var trailingSpaces = 0
        while index > context.startIndex {
            let previous = context.index(before: index)
            guard context[previous] == " " else { break }
            trailingSpaces += 1
            index = previous
        }
        guard index > context.startIndex else { return true }
        let lastIndex = context.index(before: index)
        let last = context[lastIndex]
        if last == "\n" { return true }
        guard trailingSpaces > 0 else { return false }
        return last == "." || last == "!" || last == "?"
    }
}

// MARK: - Action bar

extension KeyboardViewController: KeyboardActionBarDelegate {

    /// THE one place a network request can start. Nothing else in this file
    /// calls the AI service, and nothing starts one without this tap.
    func actionBar(_ bar: KeyboardActionBar, didSelectTemplateID id: String) {
        guard let template = resolveTemplate(id: id) else { return }
        // The template row is only on screen when no composer is open - tapping
        // the chip closes one - so this is always the start of a new reply.
        replyCoordinator.start(
            template: template,
            proxy: textDocumentProxy,
            hasFullAccess: hasFullAccess
        )
    }

    /// Turns a chip's identifier into the full template the request needs.
    ///
    /// Normally this is an in-memory lookup: the configuration was loaded when
    /// the keyboard appeared. The fallback covers the narrow race where a user
    /// taps a chip in the milliseconds before that load returns - a single file
    /// read, on a tap, never on a keystroke.
    private func resolveTemplate(id: String) -> ReplyTemplate? {
        if let template = replyCoordinator.configuration.template(id: id) { return template }
        let configuration = ProfileStore.shared.load()
        replyCoordinator.configuration = configuration
        return configuration.template(id: id)
    }

    /// A keyboard extension cannot present its own editor or reliably open its
    /// containing app, so this says where templates are created rather than
    /// pretending to create one here.
    func actionBarDidRequestNewTemplate(_ bar: KeyboardActionBar) {
        bar.showToast(aiStrings.addTemplateHint)
    }

    func actionBarDidTapRegenerate(_ bar: KeyboardActionBar) {
        replyCoordinator.updateDraft(bar.draftText)
        replyCoordinator.regenerate()
    }

    /// Reopens template selection, discarding the draft but keeping nothing:
    /// the source message goes with it.
    func actionBarDidReopenTemplateSelection(_ bar: KeyboardActionBar) {
        closeComposer()
    }

    /// The one place the reply draft reaches the host application.
    ///
    /// The source message is never what gets inserted, and nothing is ever
    /// sent: the messenger's own Send button stays under the user's control.
    func actionBarDidTapInsert(_ bar: KeyboardActionBar) {
        replyCoordinator.updateDraft(bar.draftText)
        guard let draft = replyCoordinator.draftForInsertion() else { return }

        // Never destroy what the user already typed. If the field looks
        // non-empty, ask before touching it.
        if hostFieldAppearsToHaveText() {
            pendingInsertion = draft
            bar.showConflictChoice()
            animateBarHeightChange()
            return
        }

        insertIntoHost(draft)
        closeComposer()
        refreshAutoShift()
    }

    func actionBar(_ bar: KeyboardActionBar, didResolveConflictWith choice: HostTextChoice) {
        guard let draft = pendingInsertion else {
            closeComposer()
            return
        }
        pendingInsertion = nil

        switch choice {
        case .cancel:
            // Back to editing with the draft intact. Nothing was touched.
            bar.endGenerating()
            animateBarHeightChange()
            return

        case .append:
            insertIntoHost(separatorForAppend() + draft)

        case .replace:
            clearHostField()
            insertIntoHost(draft)
        }

        closeComposer()
        refreshAutoShift()
    }

    func actionBarDidChangeHeight(_ bar: KeyboardActionBar) {
        guard !isUpdatingGeometry else { return }
        animateBarHeightChange()
    }

    // MARK: Host field

    /// Conservative check. `documentContextBeforeInput` and `...AfterInput` are
    /// the only public view a keyboard has, and a host can legitimately return
    /// nothing for either. Treating "no context" as "empty" is the safe
    /// reading: the worst case is that we insert normally into a field that was
    /// already empty.
    private func hostFieldAppearsToHaveText() -> Bool {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let after = textDocumentProxy.documentContextAfterInput ?? ""
        return !(before + after).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A space unless the existing text already ends in whitespace, so Add does
    /// not jam two sentences together or double-space them.
    private func separatorForAppend() -> String {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        guard let last = before.last else { return "" }
        return last.isWhitespace ? "" : " "
    }

    /// Deletes the host field's contents.
    ///
    /// `deleteBackward()` is the only deletion `UITextDocumentProxy` offers, so
    /// this is inherently a loop. What it does NOT do is re-read the document
    /// context on every iteration: each context read is a cross-process call,
    /// and doing one per deleted character made clearing a long draft take
    /// visibly long. Instead the context is read once per batch, giving roughly
    /// one read per 500 characters instead of one per character.
    ///
    /// The round limit is deliberate. A runaway loop inside another
    /// application's input field is a far worse failure than leaving a few
    /// characters behind, and twelve rounds is well past any realistic chat
    /// draft.
    private func clearHostField() {
        var rounds = 0
        while rounds < 12 {
            let before = textDocumentProxy.documentContextBeforeInput ?? ""
            if before.isEmpty { break }
            for _ in 0..<min(before.count, 500) {
                textDocumentProxy.deleteBackward()
            }
            rounds += 1
        }
        // Anything after the caret cannot be reached by deleteBackward, so it
        // is left alone rather than mangled.
        cachedHostContextBeforeInput = ""
        lastHostMutationTime = Date.timeIntervalSinceReferenceDate
    }

    // MARK: Composer lifecycle

    private var aiStrings: AIReplyStrings { AIReplyStrings.forLanguage(uiLanguage) }

    private func closeComposer() {
        pendingInsertion = nil
        actionBar.endComposing()
        replyCoordinator.clear()
        animateBarHeightChange()
    }

    private func animateBarHeightChange() {
        updateGeometry()
        UIView.animate(withDuration: 0.18) { self.view.layoutIfNeeded() }
    }
}

// MARK: - Reply flow

extension KeyboardViewController: ReplyFlowCoordinatorDelegate {

    func coordinator(_ coordinator: ReplyFlowCoordinator, didBeginFor context: ReplyContext, template: ReplyTemplate) {
        actionBar.beginComposing(
            sourceMessage: context.text,
            templateName: template.displayName(appLanguage: uiLanguage)
        )
        animateBarHeightChange()
    }

    func coordinatorDidBeginRegenerating(_ coordinator: ReplyFlowCoordinator) {
        actionBar.beginRegenerating()
        animateBarHeightChange()
    }

    func coordinator(_ coordinator: ReplyFlowCoordinator, didProduce draft: String) {
        actionBar.showDraft(draft)
        animateBarHeightChange()
        refreshAutoShift()
    }

    func coordinator(_ coordinator: ReplyFlowCoordinator, didFailWith error: AIReplyError) {
        let message = aiStrings.message(for: error, mode: AIConfiguration.shared.mode)

        if actionBar.isComposing {
            // A regeneration failed. Keep the composer and whatever draft was
            // already there rather than throwing the user's work away.
            actionBar.endGenerating()
            animateBarHeightChange()
            if coordinator.session?.usableDraft == nil {
                closeComposer()
                actionBar.showToast(message)
            }
            return
        }

        closeComposer()
        actionBar.showToast(message)
    }
}
