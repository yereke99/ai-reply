import Foundation

/// Generates a reply through the authenticated `/api/v1/ai/reply` endpoint.
///
/// Жауап серверде жасалады: құрылғыда провайдер кілті жоқ.
///
/// This is the transport a signed-in user gets. Compared with the legacy
/// install-token path it adds exactly two things: the request is attributed to
/// a real account, and the response carries the quota back, so the app can show
/// "3 left today" without a second round trip. The profile is not sent - the
/// server holds it - but the template and working-hours context still are,
/// because those are per-reply choices the user just made on screen.
struct AccountReplyTransport: ReplyTransport {

    /// What this one reply needs. No device identifier, no contacts, no chat
    /// history, no location: only the message being answered and how to answer it.
    struct RequestContext: Sendable {
        var message: String
        /// What the user asked for in this particular reply, if anything.
        var instruction: String = ""
        var templateID: String
        var templateName: String
        var templateRelationship: String
        var templateTone: ReplyTone
        var templateInstructions: String
        var templateReplyLength: ReplyLength
        var templateEmojiPolicy: EmojiPolicy
        var templateWorkingHoursBehaviour: WorkingHoursBehaviour
        var templateBusiness: BusinessContext?
        /// The app's language, used for logging and template naming only. The
        /// reply's language follows the incoming message, always.
        var appLanguage: String
        var business: WorkingHours.Context?
    }

    private let context: RequestContext
    private let session: AccountSession
    private let onUsage: (@Sendable (AccountAPI.Usage) -> Void)?

    init(
        context: RequestContext,
        session: AccountSession = .shared,
        onUsage: (@Sendable (AccountAPI.Usage) -> Void)? = nil
    ) {
        self.context = context
        self.session = session
        self.onUsage = onUsage
    }

    // MARK: Wire format

    private struct Business: Encodable {
        let offering: String?
        let summary: String?
        let rules: [String]?

        init?(_ source: BusinessContext?) {
            guard let source, !source.isEmpty else { return nil }
            let offering = source.offering.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = source.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let rules = source.cleanRules
            self.offering = offering.isEmpty ? nil : offering
            self.summary = summary.isEmpty ? nil : summary
            self.rules = rules.isEmpty ? nil : rules
        }
    }

    private struct Template: Encodable {
        let name: String
        let relationship: String
        let tone: String
        let instructions: String
        let reply_length: String
        let emoji_policy: String
        let working_hours_behaviour: String
        let business: Business?
    }

    private struct WorkingHoursBlock: Encodable {
        let enabled: Bool
        let is_within_working_hours: Bool
        let current_local_time: String
        let next_working_period: String?
        let weekly_schedule: String?
    }

    private struct Request: Encodable {
        let source_text: String
        let instruction: String?
        let language: String
        let template_id: String
        let template: Template
        let business_context: WorkingHoursBlock?
        let platform: String
        let app_version: String
    }

    // MARK: Call

    func generate(prompt: ReplyPromptBuilder.Prompt) async throws -> GeneratedReply {
        guard let baseURL = AIConfiguration.shared.backendBaseURL else {
            throw AIReplyError.notConfigured
        }
        guard session.isSignedIn else { throw AIReplyError.authenticationFailed }

        let client = APIClient(baseURL: baseURL)
        let descriptor = DeviceDescriptor.current
        let instruction = context.instruction.trimmingCharacters(in: .whitespacesAndNewlines)

        let request = Request(
            source_text: context.message,
            instruction: instruction.isEmpty ? nil : instruction,
            language: context.appLanguage,
            template_id: context.templateID,
            template: Template(
                name: context.templateName,
                relationship: context.templateRelationship,
                tone: context.templateTone.rawValue,
                instructions: context.templateInstructions,
                reply_length: context.templateReplyLength.rawValue,
                emoji_policy: context.templateEmojiPolicy.rawValue,
                working_hours_behaviour: context.templateWorkingHoursBehaviour.rawValue,
                business: Business(context.templateBusiness)
            ),
            business_context: context.business.map {
                WorkingHoursBlock(
                    enabled: $0.isEnabled,
                    is_within_working_hours: $0.isWithinWorkingHours,
                    current_local_time: $0.currentLocalTime,
                    next_working_period: $0.nextWorkingPeriod,
                    weekly_schedule: $0.weeklySchedule
                )
            },
            platform: descriptor.platform,
            app_version: descriptor.app_version
        )

        do {
            let response: AccountAPI.ReplyResponse = try await session.authenticated { token in
                try await client.post("api/v1/ai/reply", body: request, token: token)
            }
            onUsage?(response.usage)

            let text = ReplyNetworking.unwrapQuotes(
                response.reply.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard !text.isEmpty else { throw AIReplyError.emptyResponse }
            return GeneratedReply(text: text, detectedLanguage: response.detectedLanguage)
        } catch let error as APIError {
            throw Self.map(error)
        }
    }

    /// Backend failures become the closed set the UI already knows how to show.
    /// The quota case keeps its own error so a screen can offer the plans page
    /// instead of a generic "try again".
    static func map(_ error: APIError) -> AIReplyError {
        switch error {
        case .offline:                 return .offline
        case .timedOut, .providerTimeout: return .timedOut
        case .cancelled:               return .cancelled
        case .unauthorized, .accountDisabled: return .authenticationFailed
        case .dailyLimitReached, .rateLimited, .subscriptionExpired, .paymentRequired:
            return .rateLimited
        case .emptyResponse:           return .emptyResponse
        case .invalidRequest:          return .messageTooLong(limit: AIConfiguration.maximumMessageCharacters)
        default:                       return .serviceUnavailable
        }
    }
}
