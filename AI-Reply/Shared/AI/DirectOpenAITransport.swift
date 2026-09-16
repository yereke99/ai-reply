import Foundation

/// Calls the OpenAI Responses API directly from the device.
///
/// THE CREDENTIAL. The key is read from the keychain at call time and is never
/// held in a property, written to a log, encoded into a payload we persist, or
/// included in any error surfaced to the UI. It is entered by the user on the
/// device; no build of this project contains one.
///
/// The trade-off of this mode, stated plainly rather than buried: a key that
/// reaches a device is a key the device's owner can extract, and every request
/// is billed to it with no rate limit but OpenAI's own. That is acceptable for
/// a demo on the developer's own phone and is not acceptable for the App Store,
/// which is what `BackendTransport` exists for.
struct DirectOpenAITransport: ReplyTransport {

    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    private let model: String
    private let maxOutputTokens: Int
    private let session: URLSession

    init(
        model: String = AIConfiguration.shared.model,
        maxOutputTokens: Int = AIConfiguration.maxOutputTokens,
        session: URLSession = ReplyNetworking.makeSession(timeout: AIConfiguration.requestTimeout)
    ) {
        self.model = model
        self.maxOutputTokens = maxOutputTokens
        self.session = session
    }

    // MARK: Wire format

    private struct RequestBody: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        let model: String
        let input: [Message]
        let max_output_tokens: Int
        let temperature: Double
        /// Opts out of server-side conversation retention. Private messages
        /// should not be sitting in anyone's dashboard.
        let store: Bool
    }

    private struct ResponseBody: Decodable {
        struct Output: Decodable {
            struct Content: Decodable {
                let type: String
                let text: String?
            }
            let type: String
            let content: [Content]?
        }
        let output: [Output]?
        let output_text: String?

        var text: String {
            if let output {
                let joined = output
                    .filter { $0.type == "message" }
                    .flatMap { $0.content ?? [] }
                    .filter { $0.type == "output_text" }
                    .compactMap(\.text)
                    .joined()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !joined.isEmpty { return joined }
            }
            return output_text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    // MARK: Call

    func generate(prompt: ReplyPromptBuilder.Prompt) async throws -> GeneratedReply {
        guard let apiKey = SecureCredentialStore.apiKey() else {
            throw AIReplyError.notConfigured
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                model: model,
                input: [
                    .init(role: "developer", content: prompt.developer),
                    .init(role: "user", content: prompt.user)
                ],
                max_output_tokens: maxOutputTokens,
                temperature: 0.7,
                store: false
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
            // The body may quote the prompt back, so it is not read, not logged
            // and not shown. The status code alone decides what the user is told.
            switch http.statusCode {
            case 401, 403: throw AIReplyError.authenticationFailed
            case 429:      throw AIReplyError.rateLimited
            case 408, 504: throw AIReplyError.timedOut
            default:       throw AIReplyError.serviceUnavailable
            }
        }

        guard let decoded = try? JSONDecoder().decode(ResponseBody.self, from: data) else {
            throw AIReplyError.serviceUnavailable
        }

        let text = ReplyNetworking.unwrapQuotes(decoded.text)
        guard !text.isEmpty else { throw AIReplyError.emptyResponse }

        return GeneratedReply(text: text, detectedLanguage: nil)
    }
}
