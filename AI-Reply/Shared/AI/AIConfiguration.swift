import Foundation

/// Fixed production configuration shared by the app and keyboard extension.
struct AIConfiguration: Sendable {

    static let productionBaseURL = URL(string: "https://api.meily.kz")!
    static let maxOutputTokens = 180
    static let maximumMessageCharacters = 300
    static let requestTimeout: TimeInterval = 25

    static let shared = AIConfiguration()

    init() {
        LegacyCredentialMigration.runOnce()
    }

    var backendBaseURL: URL? { Self.productionBaseURL }
    var requiresAccount: Bool { true }
    var isReady: Bool { AccountCredentials.isSignedIn }
}
