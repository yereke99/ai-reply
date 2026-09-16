import Foundation

/// Where reply generation happens.
enum AITransportMode: String, CaseIterable, Codable, Sendable {
    /// The app calls api.openai.com itself, with a key the user entered on
    /// device. Nothing is hardcoded and nothing ships in the IPA.
    case direct
    /// The app calls our own HTTPS service, which holds the credential. The
    /// right answer for anything beyond a demo: the key never reaches a device
    /// at all, and rate limits, abuse controls and cost accounting live
    /// somewhere the user cannot edit.
    case backend
}

/// Non-secret AI settings, shared between the app and the keyboard.
///
/// Only settings live here. The credential lives in `SecureCredentialStore`
/// and never touches these defaults.
struct AIConfiguration: Sendable {

    /// THE single place a model name appears anywhere in the iOS project.
    /// In backend mode the server's `OPENAI_MODEL` wins and this is unused;
    /// in direct mode this is the default the user can override in Settings.
    static let defaultModel = "gpt-4o-mini"

    /// Output budget, matching the backend's `OPENAI_MAX_OUTPUT_TOKENS`.
    /// Sized for 1-4 short sentences plus headroom, because Cyrillic and
    /// Kazakh tokenize less efficiently than English and a budget tuned on
    /// English alone truncates a Kazakh reply mid-sentence.
    static let maxOutputTokens = 180

    /// Hard cap on the incoming message, in Unicode scalars.
    static let maximumMessageCharacters = 300

    /// Wall-clock budget for one generation. Long enough for a cold model
    /// call, short enough that a stalled network does not leave the keyboard
    /// spinning while the user waits to reply to someone.
    static let requestTimeout: TimeInterval = 25

    /// `UserDefaults` is documented as thread-safe but is not annotated
    /// `Sendable`, so the guarantee has to be asserted here. Every access below
    /// is a plain read or write of a property-list value, which is exactly the
    /// usage that guarantee covers.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
    }

    static let shared = AIConfiguration()

    private enum Key {
        static let mode = "ai.transportMode"
        static let model = "ai.model"
        static let backendURL = "ai.backendBaseURL"
        static let installID = "ai.installIdentifier"
    }

    var mode: AITransportMode {
        guard let raw = defaults.string(forKey: Key.mode),
              let value = AITransportMode(rawValue: raw) else { return .direct }
        return value
    }

    func setMode(_ mode: AITransportMode) {
        defaults.set(mode.rawValue, forKey: Key.mode)
    }

    var model: String {
        let stored = defaults.string(forKey: Key.model)?.trimmingCharacters(in: .whitespaces)
        return (stored?.isEmpty == false ? stored : nil) ?? Self.defaultModel
    }

    func setModel(_ model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == Self.defaultModel {
            defaults.removeObject(forKey: Key.model)
        } else {
            defaults.set(trimmed, forKey: Key.model)
        }
    }

    /// Base URL of our own service, used only in `.backend` mode.
    var backendBaseURL: URL? {
        guard let raw = defaults.string(forKey: Key.backendURL),
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased() else { return nil }
        // HTTPS only in production. http is tolerated for a local address so a
        // developer can point at a laptop, and nowhere else.
        if scheme == "https" { return url }
        if scheme == "http", let host = url.host,
           host == "localhost" || host.hasPrefix("127.") || host.hasPrefix("192.168.") || host.hasPrefix("10.") {
            return url
        }
        return nil
    }

    /// The address exactly as the user typed it, valid or not, so Settings can
    /// show it back to them instead of silently blanking a typo.
    var backendBaseURLString: String {
        defaults.string(forKey: Key.backendURL) ?? ""
    }

    func setBackendBaseURL(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: Key.backendURL)
        } else {
            defaults.set(trimmed, forKey: Key.backendURL)
        }
    }

    /// Random per-install identifier for backend rate limiting.
    ///
    /// Generated locally and never derived from hardware. It is not the IDFV,
    /// not the IDFA, not the device name and not anything that identifies a
    /// person - deleting the app discards it.
    var installIdentifier: String {
        if let existing = defaults.string(forKey: Key.installID) { return existing }
        let created = UUID().uuidString
        defaults.set(created, forKey: Key.installID)
        return created
    }

    /// Whether this configuration expects a signed-in account.
    ///
    /// Only true when the app is actually pointed at our service. A build in
    /// `.direct` mode, or one with no base URL set, keeps working without any
    /// account at all - the sign-in screen is not something an existing user
    /// should meet because the product gained a server.
    var requiresAccount: Bool { mode == .backend && backendBaseURL != nil }

    /// Whether a generation attempt can even be made right now.
    var isReady: Bool {
        switch mode {
        case .direct:  return SecureCredentialStore.hasAPIKey
        case .backend: return backendBaseURL != nil
        }
    }
}
