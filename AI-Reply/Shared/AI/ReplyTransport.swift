import Foundation

/// One generated reply.
struct GeneratedReply: Equatable, Sendable {
    let text: String
    /// Advisory. The model chooses the language; this only reports what came
    /// back, and nothing depends on it being right.
    let detectedLanguage: String?
}

/// What a reply source has to be able to do.
///
/// Two implementations ship: `DirectOpenAITransport`, which calls OpenAI from
/// the device, and `BackendTransport`, which calls our own service. The
/// keyboard and the app know only this protocol, so moving between them is a
/// configuration change rather than a rewrite.
protocol ReplyTransport: Sendable {
    func generate(prompt: ReplyPromptBuilder.Prompt) async throws -> GeneratedReply
}

/// Shared URLSession configuration.
enum ReplyNetworking {
    static func makeSession(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout + 5
        configuration.waitsForConnectivity = false
        // Nothing about a private message belongs in a URL cache or a cookie
        // jar, and an ephemeral configuration keeps neither on disk.
        configuration.urlCache = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }

    /// Maps transport-level failures onto the closed error set.
    static func mapURLError(_ error: Error) -> AIReplyError {
        if error is CancellationError { return .cancelled }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return .serviceUnavailable }
        switch nsError.code {
        case NSURLErrorCancelled:
            return .cancelled
        case NSURLErrorTimedOut:
            return .timedOut
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorDataNotAllowed,
             NSURLErrorInternationalRoamingOff:
            return .offline
        default:
            return .serviceUnavailable
        }
    }

    /// Removes a wrapper the model sometimes puts around a one-line answer.
    ///
    /// Conservative on purpose: only a matched pair enclosing the WHOLE reply is
    /// removed, so a quotation inside a real sentence survives untouched.
    static func unwrapQuotes(_ text: String) -> String {
        let pairs: [(Character, Character)] = [("\"", "\""), ("\u{201C}", "\u{201D}"), ("\u{00AB}", "\u{00BB}")]
        for (open, close) in pairs where text.count > 2 && text.first == open && text.last == close {
            let inner = text.dropFirst().dropLast()
            if !inner.contains(close) {
                return String(inner).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }
}
