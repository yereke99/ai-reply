import Foundation

/// Every way generating a reply can fail, as a value the UI localizes.
///
/// Deliberately closed and deliberately coarse. The user needs to know what to
/// do next; they do not need an HTTP status, a JSON body or an upstream error
/// string, and showing them one would leak detail that has no business on a
/// keyboard above WhatsApp.
enum AIReplyError: Error, Equatable, Sendable {
    /// Nothing was copied, or the copied value held no text.
    case noSourceMessage
    /// The copied message is longer than the 300-character limit.
    case messageTooLong(limit: Int)
    /// The keyboard cannot read the clipboard without Full Access.
    case fullAccessRequired
    /// No API key entered (direct mode) or no service URL set (backend mode).
    case notConfigured
    /// Device is offline.
    case offline
    /// The request exceeded its time budget.
    case timedOut
    /// The user or the keyboard cancelled before a reply arrived.
    case cancelled
    /// Credential rejected: the key is wrong, revoked or out of quota.
    case authenticationFailed
    /// Too many requests, ours or OpenAI's.
    case rateLimited
    /// The service answered, but not with a usable reply.
    case emptyResponse
    /// Anything else: a 5xx, a malformed payload, an unreachable host.
    case serviceUnavailable
}
