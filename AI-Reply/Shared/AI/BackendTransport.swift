import Foundation

/// Calls our own HTTPS service, which holds the OpenAI credential.
///
/// This is the production shape: the key never reaches a device, the model is
/// configured once server-side, and rate limiting, abuse controls and cost
/// accounting live somewhere a user cannot edit. The matching server is in
/// `backend/` in this repository.
///
/// The device holds only a signed, expiring client token, obtained by
/// exchanging a random per-install identifier. That token is stored in the
/// keychain, not in App Group defaults.
struct BackendTransport: ReplyTransport {

    private let baseURL: URL
    private let session: URLSession
    private let context: RequestContext

    /// The structured fields the service needs alongside the prompt. The
    /// service builds its own prompt from these; sending both keeps the two
    /// transports interchangeable from the caller's point of view.
    struct RequestContext: Sendable {
        var message: String
        var templateID: String
        /// The APP's language code. Named `keyboard_language` on the wire for
        /// compatibility with the deployed service; it is used there for
        /// logging and template naming only, never to choose the reply's
        /// language - that follows the incoming message.
        var keyboardLanguage: String
        var profileDescription: String
        var profileRole: String
        var preferredTone: ReplyTone
        var profileBusiness: BusinessContext
        var templateName: String
        var templateRelationship: String
        var templateTone: ReplyTone
        var templateInstructions: String
        var templateReplyLength: ReplyLength
        var templateEmojiPolicy: EmojiPolicy
        var templateBusiness: BusinessContext?
        var templateWorkingHoursBehaviour: WorkingHoursBehaviour
        var business: WorkingHours.Context?
    }

    init(
        baseURL: URL,
        context: RequestContext,
        session: URLSession = ReplyNetworking.makeSession(timeout: AIConfiguration.requestTimeout)
    ) {
        self.baseURL = baseURL
        self.context = context
        self.session = session
    }

    // MARK: Wire format

    /// Deliberately minimal. No device identifier, no phone number, no
    /// contacts, no chat history, no location, no advertising id, no device
    /// model, no OS version. Only what writing this one reply requires.
    private struct GenerateRequest: Encodable {
        /// What the user offers. Fields the user left blank are omitted
        /// rather than sent as empty strings, so the server never has to
        /// distinguish "not answered" from "answered with nothing".
        struct Business: Encodable {
            let offering: String?
            let summary: String?
            let rules: [String]?

            init?(_ context: BusinessContext?) {
                guard let context, !context.isEmpty else { return nil }
                let offering = context.offering.trimmingCharacters(in: .whitespacesAndNewlines)
                let summary = context.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                let rules = context.cleanRules
                self.offering = offering.isEmpty ? nil : offering
                self.summary = summary.isEmpty ? nil : summary
                self.rules = rules.isEmpty ? nil : rules
            }
        }
        struct Profile: Encodable {
            let description: String
            let role: String?
            let preferred_tone: String
            let business: Business?
        }
        struct Template: Encodable {
            let name: String
            let relationship: String
            let tone: String
            let instructions: String
            let reply_length: String
            let emoji_policy: String
            let working_hours_behaviour: String
            let business: Business?
        }
        struct WorkingHoursBlock: Encodable {
            let enabled: Bool
            let is_within_working_hours: Bool
            let current_local_time: String
            let next_working_period: String?
            let weekly_schedule: String?
        }
        let message: String
        let template_id: String
        let keyboard_language: String
        let profile: Profile
        let template: Template
        let business_context: WorkingHoursBlock?
    }

    private struct GenerateResponse: Decodable {
        let reply: String
        let detected_language: String?
    }

    private struct RegisterRequest: Encodable { let install_id: String }
    private struct RegisterResponse: Decodable { let token: String }

    // MARK: Call

    func generate(prompt: ReplyPromptBuilder.Prompt) async throws -> GeneratedReply {
        var token = SecureCredentialStore.backendToken()
        if token == nil {
            token = try await register()
        }

        do {
            return try await post(token: token!)
        } catch AIReplyError.authenticationFailed {
            // The token expired or the server's signing secret rotated. One
            // silent re-registration, then give up rather than loop.
            let fresh = try await register()
            return try await post(token: fresh)
        }
    }

    private func register() async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/auth/register"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RegisterRequest(install_id: AIConfiguration.shared.installIdentifier)
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ReplyNetworking.mapURLError(error)
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(RegisterResponse.self, from: data) else {
            throw AIReplyError.serviceUnavailable
        }

        SecureCredentialStore.setBackendToken(decoded.token)
        return decoded.token
    }

    private func post(token: String) async throws -> GeneratedReply {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/reply/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let business = context.business.map {
            GenerateRequest.WorkingHoursBlock(
                enabled: $0.isEnabled,
                is_within_working_hours: $0.isWithinWorkingHours,
                current_local_time: $0.currentLocalTime,
                next_working_period: $0.nextWorkingPeriod,
                weekly_schedule: $0.weeklySchedule
            )
        }

        request.httpBody = try JSONEncoder().encode(
            GenerateRequest(
                message: context.message,
                template_id: context.templateID,
                keyboard_language: context.keyboardLanguage,
                profile: .init(
                    description: context.profileDescription,
                    role: context.profileRole.isEmpty ? nil : context.profileRole,
                    preferred_tone: context.preferredTone.rawValue,
                    business: .init(context.profileBusiness)
                ),
                template: .init(
                    name: context.templateName,
                    relationship: context.templateRelationship,
                    tone: context.templateTone.rawValue,
                    instructions: context.templateInstructions,
                    reply_length: context.templateReplyLength.rawValue,
                    emoji_policy: context.templateEmojiPolicy.rawValue,
                    working_hours_behaviour: context.templateWorkingHoursBehaviour.rawValue,
                    business: .init(context.templateBusiness)
                ),
                business_context: business
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ReplyNetworking.mapURLError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AIReplyError.serviceUnavailable
        }

        guard (200..<300).contains(http.statusCode) else {
            switch http.statusCode {
            case 401, 403: throw AIReplyError.authenticationFailed
            case 413:      throw AIReplyError.messageTooLong(limit: AIConfiguration.maximumMessageCharacters)
            case 429:      throw AIReplyError.rateLimited
            case 408, 504: throw AIReplyError.timedOut
            default:       throw AIReplyError.serviceUnavailable
            }
        }

        guard let decoded = try? JSONDecoder().decode(GenerateResponse.self, from: data) else {
            throw AIReplyError.serviceUnavailable
        }

        let text = ReplyNetworking.unwrapQuotes(
            decoded.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !text.isEmpty else { throw AIReplyError.emptyResponse }
        return GeneratedReply(text: text, detectedLanguage: decoded.detected_language)
    }
}
