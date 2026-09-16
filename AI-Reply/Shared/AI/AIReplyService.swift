import Foundation

/// The single entry point for generating a reply.
///
/// Responsibilities, and nothing else: validate the input, assemble the
/// context, choose a transport, run the call off the main actor, map every
/// failure onto `AIReplyError`. No UI, no storage writes, no clipboard access
/// and no knowledge of which screen asked.
///
/// It lives in `Shared` so the keyboard and the host app generate replies
/// through exactly the same code, including the dictation flow in the app.
struct AIReplyService: Sendable {

    /// What the caller supplies. The service never reads the clipboard itself;
    /// the message arrives already acquired by an explicit user action.
    struct Request: Sendable {
        var message: String
        var template: ReplyTemplate
        var configuration: ReplyConfiguration
        /// The APP's language, used only to name the selected template in the
        /// prompt the way the user saw it on the chip. It is NOT the reply
        /// language: that follows the incoming message, always.
        var uiLanguage: AppLanguage
        /// Injectable so working-hours behaviour is testable without waiting
        /// for 18:30.
        var now: Date = Date()
    }

    private let configuration: AIConfiguration
    private let transportOverride: (@Sendable (Request, ReplyPromptBuilder.Prompt) -> ReplyTransport)?

    init(
        configuration: AIConfiguration = .shared,
        transportOverride: (@Sendable (Request, ReplyPromptBuilder.Prompt) -> ReplyTransport)? = nil
    ) {
        self.configuration = configuration
        self.transportOverride = transportOverride
    }

    // MARK: Validation

    /// The 300-character rule.
    ///
    /// It applies to the INCOMING MESSAGE ONLY. The profile, the template
    /// instructions and the developer rules are separate and are not counted
    /// against it - the limit exists to keep one pasted chat message sane, not
    /// to cap the prompt.
    ///
    /// Counted in Unicode scalars, which is what the user sees as characters
    /// for these three languages and what the backend counts too.
    static func validate(message: String) -> Result<String, AIReplyError> {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.noSourceMessage) }
        guard trimmed.unicodeScalars.count <= AIConfiguration.maximumMessageCharacters else {
            return .failure(.messageTooLong(limit: AIConfiguration.maximumMessageCharacters))
        }
        return .success(trimmed)
    }

    static func characterCount(_ message: String) -> Int {
        message.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
    }

    // MARK: Generation

    func generate(_ request: Request) async throws -> GeneratedReply {
        let message: String
        switch Self.validate(message: request.message) {
        case .success(let value): message = value
        case .failure(let error): throw error
        }

        guard configuration.isReady else { throw AIReplyError.notConfigured }

        let profile = request.configuration.profile
        let templateName = request.template.displayName(appLanguage: request.uiLanguage)

        // The template's own schedule wins when it has one; otherwise the
        // profile's applies. Resolved HERE, deterministically, so the model is
        // never asked to work out what "after hours" means - it is told.
        let hours = request.template.effectiveWorkingHours(profile: profile.workingHours)

        // Only computed when the user actually enabled working hours, so a
        // profile without them sends no time context at all.
        let business = hours.isEnabled ? hours.context(now: request.now) : nil

        let prompt = ReplyPromptBuilder.build(
            ReplyPromptBuilder.Input(
                message: message,
                template: request.template,
                templateName: templateName,
                profileDescription: profile.promptDescription,
                profileRole: profile.role,
                preferredTone: profile.preferredTone,
                profileBusiness: profile.business,
                templateBusiness: request.template.effectiveBusiness,
                businessContext: business
            )
        )

        let transport = transportOverride?(request, prompt)
            ?? makeTransport(request: request, message: message, templateName: templateName, business: business)

        do {
            let reply = try await transport.generate(prompt: prompt)
            try Task.checkCancellation()
            return reply
        } catch let error as AIReplyError {
            throw error
        } catch is CancellationError {
            throw AIReplyError.cancelled
        } catch {
            throw ReplyNetworking.mapURLError(error)
        }
    }

    private func makeTransport(
        request: Request,
        message: String,
        templateName: String,
        business: WorkingHours.Context?
    ) -> ReplyTransport {
        switch configuration.mode {
        case .direct:
            return DirectOpenAITransport(model: configuration.model)

        case .backend:
            guard let baseURL = configuration.backendBaseURL else {
                return UnconfiguredTransport()
            }
            let template = request.template
            let profile = request.configuration.profile
            return BackendTransport(
                baseURL: baseURL,
                context: BackendTransport.RequestContext(
                    message: message,
                    templateID: template.id,
                    keyboardLanguage: request.uiLanguage.rawValue,
                    profileDescription: profile.promptDescription,
                    profileRole: profile.role,
                    preferredTone: profile.preferredTone,
                    profileBusiness: profile.business,
                    templateName: templateName,
                    templateRelationship: template.relationship.rawValue,
                    templateTone: template.tone,
                    templateInstructions: template.instructions,
                    templateReplyLength: template.replyLength,
                    templateEmojiPolicy: template.emojiPolicy,
                    templateBusiness: template.effectiveBusiness,
                    templateWorkingHoursBehaviour: template.workingHoursBehaviour,
                    business: business
                )
            )
        }
    }
}

/// Fails cleanly when the chosen mode has not been set up, rather than making
/// `makeTransport` optional and pushing the branch onto every caller.
private struct UnconfiguredTransport: ReplyTransport {
    func generate(prompt: ReplyPromptBuilder.Prompt) async throws -> GeneratedReply {
        throw AIReplyError.notConfigured
    }
}

#if DEBUG
/// Offline development transport.
///
/// DEBUG ONLY, and deliberately not reachable from any production path: it is
/// opt-in through `AIReplyService(transportOverride:)`, which release code
/// never calls. The deterministic `ReplySimulator` that used to sit in the
/// real reply flow has been deleted; this replaces it without being able to
/// masquerade as a real answer in a shipped build.
struct MockReplyTransport: ReplyTransport {
    var delay: Duration = .milliseconds(400)
    var result: Result<String, AIReplyError> = .success("This is a mock reply for offline development.")

    func generate(prompt: ReplyPromptBuilder.Prompt) async throws -> GeneratedReply {
        try? await Task.sleep(for: delay)
        try Task.checkCancellation()
        switch result {
        case .success(let text): return GeneratedReply(text: text, detectedLanguage: nil)
        case .failure(let error): throw error
        }
    }
}
#endif
