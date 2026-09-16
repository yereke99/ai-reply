import UIKit

// MARK: - Model

enum ReplyContextSource {
    /// Text the host exposed through `UITextDocumentProxy.selectedText`, i.e. a
    /// selection inside the ACTIVE EDITABLE INPUT.
    case editableSelection
    /// Text the user explicitly copied, read only in direct response to the
    /// user tapping a template.
    case clipboard
}

struct ReplyContext {
    let text: String
    let source: ReplyContextSource
}

/// The two texts a reply involves, deliberately kept in separate fields.
///
/// `sourceMessage` is the incoming message the user copied. It is read-only and
/// is NEVER seeded into `replyDraft`: what the other person wrote must never
/// silently become what this user is about to send.
///
/// `replyDraft` is what the model produced and the user then edited. It is the
/// only value that can reach the host application's input field.
struct ReplySession {
    let sourceMessage: String
    let source: ReplyContextSource
    var template: ReplyTemplate
    var replyDraft: String = ""

    var usableDraft: String? {
        let trimmed = replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : replyDraft
    }
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
/// Copy, then tap a template.
final class ContextTextProvider {

    /// - Parameters:
    ///   - proxy: the active text document proxy.
    ///   - hasFullAccess: `UIInputViewController.hasFullAccess`. `UIPasteboard`
    ///     is unavailable to a keyboard extension without it.
    /// - Note: CLIPBOARD PRIVACY. The clipboard is touched ONLY from inside this
    ///   call, which only ever runs as the direct result of the user tapping a
    ///   template. There is no polling, no timer, no read on appearance and no
    ///   background access.
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
    func coordinator(_ coordinator: ReplyFlowCoordinator, didBeginFor context: ReplyContext, template: ReplyTemplate)
    func coordinatorDidBeginRegenerating(_ coordinator: ReplyFlowCoordinator)
    func coordinator(_ coordinator: ReplyFlowCoordinator, didProduce draft: String)
    func coordinator(_ coordinator: ReplyFlowCoordinator, didFailWith error: AIReplyError)
}

/// Drives the clipboard to template to AI to draft flow.
///
/// GENERATION IS NEVER AUTOMATIC. Copying text does not start a request;
/// opening the keyboard does not start a request; the keyboard reappearing does
/// not start a request. Exactly one thing does: the user tapping a template or
/// Regenerate. That is what keeps token cost, accidental clipboard content and
/// privacy all under the user's control at once.
@MainActor
final class ReplyFlowCoordinator {

    weak var delegate: ReplyFlowCoordinatorDelegate?

    private let provider: ContextTextProvider
    private let normalizer: ReplyDraftNormalizer
    private let service: AIReplyService

    /// The in-flight request. Holding it is what makes cancellation, duplicate
    /// suppression and "keyboard closed mid-request" all one mechanism rather
    /// than three flags.
    private var task: Task<Void, Never>?

    private(set) var session: ReplySession?

    /// Configuration snapshot taken when the keyboard appeared, so no request
    /// has to touch storage.
    var configuration: ReplyConfiguration = .initial
    /// The APP's language. Names the template in the prompt the way the user
    /// saw it on the chip. The LAYOUT is deliberately absent: what the user is
    /// typing on has no bearing on the reply, whose language follows the
    /// incoming message.
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

    var isComposing: Bool { session != nil }
    var isGenerating: Bool { task != nil }

    // MARK: Entry points

    /// The user tapped a template. Acquires the message, validates it, and only
    /// then makes a network request.
    func start(template: ReplyTemplate, proxy: UITextDocumentProxy, hasFullAccess: Bool) {
        // Debounce: a second tap while a request is in flight is ignored rather
        // than queued, so an impatient double tap cannot spend twice.
        guard task == nil else { return }

        switch provider.acquire(proxy: proxy, hasFullAccess: hasFullAccess) {
        case .failure(let error):
            session = nil
            delegate?.coordinator(self, didFailWith: error)

        case .success(let context):
            // The 300-character rule is enforced BEFORE the request, so an
            // over-long paste costs nothing and reports immediately.
            switch AIReplyService.validate(message: context.text) {
            case .failure(let error):
                session = nil
                delegate?.coordinator(self, didFailWith: error)
            case .success(let message):
                session = ReplySession(sourceMessage: message, source: context.source, template: template)
                delegate?.coordinator(self, didBeginFor: context, template: template)
                generate()
            }
        }
    }

    /// Regenerate: SAME source message, SAME template, new answer.
    func regenerate() {
        guard session != nil, task == nil else { return }
        delegate?.coordinatorDidBeginRegenerating(self)
        generate()
    }

    // MARK: Generation

    private func generate() {
        guard let session else { return }

        let request = AIReplyService.Request(
            message: session.sourceMessage,
            template: session.template,
            configuration: configuration,
            uiLanguage: uiLanguage
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

    // MARK: Draft

    /// Mirrors what the user has typed into the composer.
    func updateDraft(_ draft: String) {
        session?.replyDraft = draft
    }

    /// The text to hand to the host application, or nil when the draft is
    /// blank. Never returns the source message.
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
    /// PRIVACY. The source message and the draft live only here and in the
    /// composer's views, only for as long as the composer is open. Nothing is
    /// written to disk, to the App Group or to a log at any point.
    func clear() {
        task?.cancel()
        task = nil
        session = nil
    }
}

// MARK: - Logging

/// Diagnostics never reach the UI and never carry message content, profile text
/// or draft text - only lengths and outcomes, and only in a debug build.
enum ReplyLog {
    static func event(_ message: @autoclosure () -> String) {
        #if DEBUG
        NSLog("[ReplyKeyboard] %@", message())
        #endif
    }
}
