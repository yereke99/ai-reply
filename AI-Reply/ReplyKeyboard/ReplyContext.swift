import UIKit

// MARK: - Model

enum ReplyContextSource {
    /// Text the host exposed through `UITextDocumentProxy.selectedText`, i.e. a
    /// selection inside the ACTIVE EDITABLE INPUT.
    case editableSelection
    /// Text the user explicitly copied, read only in direct response to a user
    /// gesture.
    case clipboard
    /// Text the user typed into the source field themselves.
    case typed
}

/// The THREE texts a reply involves, deliberately kept in three fields.
///
/// `sourceMessage` is the incoming message. It is reference material: it is
/// never seeded into `instruction` and never into `replyDraft`, because what
/// the other person wrote must never silently become what this user sends.
///
/// `instruction` is what THIS user wants said - "ответь вежливо, что согласен".
/// It is sent to the model as a separate, named block and is never inserted
/// into the host application.
///
/// `replyDraft` is what the model produced and the user then edited. It is the
/// only one of the three that can reach the host application's input field.
struct ReplySession {
    var sourceMessage: String
    var source: ReplyContextSource?
    var template: ReplyTemplate
    var instruction: String = ""
    var replyDraft: String = ""

    var usableSource: String? {
        let trimmed = sourceMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var usableDraft: String? {
        let trimmed = replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : replyDraft
    }
}

struct ReplyContext {
    let text: String
    let source: ReplyContextSource
}

// MARK: - Acquisition

/// Resolves "the message the user wants to reply to" using only public,
/// documented iOS APIs.
///
/// IMPORTANT LIMITATION, stated here so no caller can misread the intent:
/// an iOS Custom Keyboard Extension CANNOT read incoming message bubbles in
/// WhatsApp, Telegram, Instagram Direct, Messenger or iMessage.
/// `UITextDocumentProxy` is a view onto the active editable text input only.
/// There is no public API that exposes another application's view hierarchy or
/// its chat content to a keyboard, and this file deliberately contains no
/// Accessibility, screen-scraping, OCR or private-API path to fake one. The
/// universal fallback is the explicit user gesture: long press the message,
/// Copy, then open the composer.
final class ContextTextProvider {

    /// - Parameters:
    ///   - proxy: the active text document proxy.
    ///   - hasFullAccess: `UIInputViewController.hasFullAccess`. `UIPasteboard`
    ///     is unavailable to a keyboard extension without it.
    /// - Note: CLIPBOARD PRIVACY. The clipboard is touched ONLY from inside this
    ///   call, and this call only ever runs as the direct result of a user
    ///   gesture: opening the composer from a template chip, or tapping Paste
    ///   inside it. There is no polling, no timer, no read on appearance, no
    ///   read on regeneration and no background access. The acquired text is
    ///   then held in the session and reused, so a second generation never
    ///   touches the pasteboard again.
    func acquire(proxy: UITextDocumentProxy, hasFullAccess: Bool) -> Result<ReplyContext, AIReplyError> {
        // STEP 1 - selection inside the active editable input.
        if let selection = Self.normalised(proxy.selectedText) {
            ReplyLog.event("source: selection")
            return .success(ReplyContext(text: selection, source: .editableSelection))
        }

        // STEP 2 - explicitly copied text.
        guard hasFullAccess else {
            ReplyLog.event("clipboard unavailable: full access off")
            return .failure(.fullAccessRequired)
        }

        let pasteboard = UIPasteboard.general
        // `hasStrings` is a metadata query and does not trigger the system
        // paste prompt; only reading `string` does.
        guard pasteboard.hasStrings, let copied = Self.normalised(pasteboard.string) else {
            ReplyLog.event("clipboard: no usable text")
            return .failure(.noSourceMessage)
        }

        ReplyLog.event("source: clipboard, length \(copied.count)")
        return .success(ReplyContext(text: copied, source: .clipboard))
    }

    private static func normalised(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

// MARK: - Coordinator

@MainActor
protocol ReplyFlowCoordinatorDelegate: AnyObject {
    /// The composer should open for this session. NOTHING has been generated.
    func coordinator(_ coordinator: ReplyFlowCoordinator, didOpen session: ReplySession)
    /// The source text changed underneath the composer, e.g. after a Paste.
    func coordinator(_ coordinator: ReplyFlowCoordinator, didUpdateSource text: String)
    func coordinatorDidBeginGenerating(_ coordinator: ReplyFlowCoordinator)
    func coordinator(_ coordinator: ReplyFlowCoordinator, didProduce draft: String)
    func coordinator(_ coordinator: ReplyFlowCoordinator, didFailWith error: AIReplyError)
}

/// Drives source -> instruction -> AI -> draft.
///
/// GENERATION IS NEVER AUTOMATIC, and after this redesign it is not even
/// automatic on a template tap. Copying text does not start a request; opening
/// the keyboard does not start a request; picking an audience does not start a
/// request. Exactly one thing does: the user tapping Generate or Regenerate.
/// That is what keeps token cost, accidental clipboard content and privacy all
/// under the user's control at once.
@MainActor
final class ReplyFlowCoordinator {

    weak var delegate: ReplyFlowCoordinatorDelegate?

    private let provider: ContextTextProvider
    private let normalizer: ReplyDraftNormalizer
    private let service: AIReplyService

    /// The in-flight request. Holding it is what makes cancellation, duplicate
    /// suppression and "keyboard closed mid-request" one mechanism rather than
    /// three flags.
    private var task: Task<Void, Never>?

    private(set) var session: ReplySession?

    /// True while the template row is showing over a session the user has not
    /// finished. Picking an audience resumes it with the source and the
    /// instruction intact, rather than making them start again.
    private(set) var isSuspended = false

    /// Configuration snapshot taken when the keyboard appeared, so no request
    /// has to touch storage.
    var configuration: ReplyConfiguration = .initial

    /// The APP's language. Names the template in the prompt the way the user
    /// saw it on the chip. The LAYOUT is deliberately absent: what the user is
    /// typing on has no bearing on the reply, whose language follows the
    /// incoming message unless the instruction asks otherwise.
    var uiLanguage: AppLanguage = .systemDefault

    init(
        provider: ContextTextProvider = ContextTextProvider(),
        normalizer: ReplyDraftNormalizer = ReplyDraftNormalizer(),
        service: AIReplyService = AIReplyService()
    ) {
        self.provider = provider
        self.normalizer = normalizer
        self.service = service
    }

    var isComposing: Bool { session != nil && !isSuspended }
    var isGenerating: Bool { task != nil }

    // MARK: Entry points

    /// The user picked an audience. Opens the composer; it does NOT generate.
    ///
    /// Resuming a suspended session keeps the source message and the
    /// instruction and only swaps the template, so "wrong chip" costs a tap.
    func open(template: ReplyTemplate, proxy: UITextDocumentProxy, hasFullAccess: Bool) {
        guard task == nil else { return }

        if session != nil {
            session?.template = template
            isSuspended = false
            if let session { delegate?.coordinator(self, didOpen: session) }
            return
        }

        var opened = ReplySession(sourceMessage: "", source: nil, template: template)
        var failure: AIReplyError?

        switch provider.acquire(proxy: proxy, hasFullAccess: hasFullAccess) {
        case .success(let context):
            opened.sourceMessage = context.text
            opened.source = context.source
        case .failure(let error):
            // An empty clipboard is not an error worth shouting about: the
            // composer opens anyway and its placeholder says what to do. Full
            // Access being off IS worth saying, because nothing the user does
            // inside the keyboard can fix it.
            failure = error == .noSourceMessage ? nil : error
        }

        session = opened
        isSuspended = false
        delegate?.coordinator(self, didOpen: opened)
        if let failure { delegate?.coordinator(self, didFailWith: failure) }
    }

    /// Explicit Paste inside the composer. The only other place the clipboard
    /// is read, and again only from a direct user gesture.
    func pasteSource(proxy: UITextDocumentProxy, hasFullAccess: Bool) {
        guard session != nil else { return }
        switch provider.acquire(proxy: proxy, hasFullAccess: hasFullAccess) {
        case .success(let context):
            session?.sourceMessage = context.text
            session?.source = context.source
            delegate?.coordinator(self, didUpdateSource: context.text)
        case .failure(let error):
            delegate?.coordinator(self, didFailWith: error)
        }
    }

    /// Keeps the session but hands the screen back to the template row.
    func suspend() {
        guard session != nil else { return }
        task?.cancel()
        task = nil
        isSuspended = true
    }

    // MARK: Generation

    /// Generate from the CURRENT source and instruction.
    func generate() {
        guard let current = session, task == nil else { return }

        guard let source = current.usableSource else {
            delegate?.coordinator(self, didFailWith: .noSourceMessage)
            return
        }
        // The 300-character rule is enforced BEFORE the request, so an
        // over-long paste costs nothing and reports immediately.
        switch AIReplyService.validate(message: source) {
        case .failure(let error):
            delegate?.coordinator(self, didFailWith: error)
        case .success:
            delegate?.coordinatorDidBeginGenerating(self)
            run()
        }
    }

    /// Regenerate: SAME source, SAME instruction, SAME template, new answer.
    func regenerate() {
        generate()
    }

    private func run() {
        guard let session else { return }

        let request = AIReplyService.Request(
            message: session.sourceMessage,
            template: session.template,
            configuration: configuration,
            uiLanguage: uiLanguage,
            instruction: session.instruction
        )

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let reply = try await self.service.generate(request)
                guard !Task.isCancelled else { return }
                self.task = nil
                // The session can have been cleared while the request was in
                // flight - the user closed the composer, or the keyboard went
                // away. Dropping the answer is correct; there is nothing left
                // to put it in.
                guard self.session != nil else { return }
                self.session?.replyDraft = reply.text
                self.delegate?.coordinator(self, didProduce: reply.text)
            } catch {
                guard !Task.isCancelled else { return }
                self.task = nil
                let mapped = (error as? AIReplyError) ?? .serviceUnavailable
                guard mapped != .cancelled else { return }
                self.delegate?.coordinator(self, didFailWith: mapped)
            }
        }
    }

    // MARK: Mirroring the composer

    func updateSource(_ text: String) { session?.sourceMessage = text }
    func updateInstruction(_ text: String) { session?.instruction = text }
    func updateDraft(_ draft: String) { session?.replyDraft = draft }

    func setTemplate(_ template: ReplyTemplate) { session?.template = template }

    /// The text to hand to the host application, or nil when the draft is
    /// blank. Never returns the source message and never returns the
    /// instruction.
    func draftForInsertion() -> String? {
        guard let rawDraft = session?.usableDraft else { return nil }
        let draft = normalizer.normalize(rawDraft)
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        ReplyLog.event("insert accepted, length \(draft.count)")
        return draft
    }

    // MARK: Teardown

    /// Cancels any request and drops every trace of the message.
    ///
    /// PRIVACY. The source message, the instruction and the draft live only
    /// here and in the composer's views, only for as long as the composer is
    /// open. Nothing is written to disk, to the App Group or to a log at any
    /// point.
    func clear() {
        task?.cancel()
        task = nil
        session = nil
        isSuspended = false
    }
}

// MARK: - Logging

/// Diagnostics never reach the UI and never carry message content, instruction
/// text, profile text or draft text - only lengths and outcomes, and only in a
/// debug build.
enum ReplyLog {
    static func event(_ message: @autoclosure () -> String) {
        #if DEBUG
        NSLog("[ReplyKeyboard] %@", message())
        #endif
    }
}
