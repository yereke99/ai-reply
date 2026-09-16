import Foundation

/// Every call the app makes to the AI Reply backend.
///
/// Барлық сұраныс осы жерден өтеді: қайталанатын желі коды жоқ.
///
/// The service holds no state of its own. Tokens belong to `AccountSession`,
/// and the base URL to `AIConfiguration`, so a screen only has to say what it
/// wants, not how authentication works.
struct AccountService: Sendable {

    private let session: AccountSession

    init(session: AccountSession = .shared) {
        self.session = session
    }

    private func client() throws -> APIClient {
        guard let baseURL = AIConfiguration.shared.backendBaseURL else {
            throw APIError.invalidRequest
        }
        return APIClient(baseURL: baseURL)
    }

    // MARK: Public endpoints

    /// Countries, limits and whether the demo OTP is on. Called before sign-in.
    func serverConfig() async throws -> AccountAPI.ServerConfig {
        try await client().get("api/v1/config")
    }

    func plans() async throws -> [AccountAPI.Plan] {
        let list: AccountAPI.PlanList = try await client().get("api/v1/plans")
        return list.plans
    }

    // MARK: Sign-in

    /// Asks for a code. The server decides how it is delivered - in demo mode
    /// nothing is sent at all and `demoMode` comes back true.
    func requestCode(identifier: String, locale: String) async throws -> AccountAPI.Challenge {
        struct Request: Encodable {
            let identifier: String
            let locale: String
        }
        return try await client().post("api/v1/auth/request-otp",
                                       body: Request(identifier: identifier, locale: locale))
    }

    /// Verifies the code and stores the resulting session.
    @discardableResult
    func verifyCode(identifier: String, code: String) async throws -> AccountAPI.Session {
        struct Request: Encodable {
            let identifier: String
            let code: String
            let device: DeviceDescriptor
        }
        let result: AccountAPI.Session = try await client().post(
            "api/v1/auth/verify-otp",
            body: Request(identifier: identifier, code: code, device: .current)
        )
        await session.adopt(result)
        return result
    }

    func signOut() async {
        await session.signOut()
    }

    // MARK: Authenticated endpoints

    func account() async throws -> AccountAPI.Account {
        try await session.authenticated { token in
            try await client().get("api/v1/me", token: token)
        }
    }

    func usage() async throws -> AccountAPI.Usage {
        try await session.authenticated { token in
            try await client().get("api/v1/me/usage", token: token)
        }
    }

    func subscription() async throws -> AccountAPI.Subscription {
        try await session.authenticated { token in
            try await client().get("api/v1/me/subscription", token: token)
        }
    }

    /// Sends only the fields that changed - every property is optional on the
    /// wire, so an empty edit is a no-op rather than an accidental wipe.
    struct ProfileUpdate: Encodable, Sendable {
        var display_name: String?
        var role: String?
        var description: String?
        var preferred_tone: String?
        var business_offering: String?
        var business_summary: String?
        var business_rules: [String]?
        var locale: String?
        var timezone: String?
        var onboarding_completed: Bool?
    }

    @discardableResult
    func updateProfile(_ update: ProfileUpdate) async throws -> AccountAPI.Profile {
        try await session.authenticated { token in
            try await client().patch("api/v1/me", body: update, token: token)
        }
    }

    /// Registers this device so a push token has somewhere to live later.
    func registerDevice(pushToken: String? = nil) async throws {
        struct Request: Encodable {
            let device_id: String
            let platform: String
            let app_version: String
            let os_version: String
            let locale: String
            let push_token: String?
            let push_enabled: Bool
        }
        let descriptor = DeviceDescriptor.current
        let request = Request(
            device_id: descriptor.device_id,
            platform: descriptor.platform,
            app_version: descriptor.app_version,
            os_version: descriptor.os_version,
            locale: descriptor.locale,
            push_token: pushToken,
            push_enabled: pushToken != nil
        )
        let _: APIClient.Empty = try await session.authenticated { token in
            try await client().post("api/v1/devices", body: request, token: token)
        }
    }

    // MARK: Subscription changes (demo payment adapter)

    struct CheckoutResult: Decodable, Sendable {
        let paymentID: String
        let provider: String
        let status: String
        let demo: Bool

        enum CodingKeys: String, CodingKey {
            case paymentID = "payment_id"
            case provider, status, demo
        }
    }

    func startCheckout(planID: String) async throws -> CheckoutResult {
        struct Request: Encodable { let plan_id: String }
        return try await session.authenticated { token in
            try await client().post("api/v1/payments/checkout",
                                    body: Request(plan_id: planID), token: token)
        }
    }

    /// Confirms a payment. With the demo adapter this is what actually moves
    /// the account onto the chosen plan; with a real acquirer the confirmation
    /// arrives from the provider instead and this call just reads the result.
    @discardableResult
    func confirmCheckout(paymentID: String) async throws -> AccountAPI.Usage {
        struct Response: Decodable, Sendable {
            let subscription: AccountAPI.Subscription
            let usage: AccountAPI.Usage
        }
        let response: Response = try await session.authenticated { token in
            try await client().post("api/v1/payments/\(paymentID)/confirm",
                                    body: APIClient.EmptyBody(), token: token)
        }
        return response.usage
    }
}

extension APIClient {
    /// A body for endpoints that take none but still expect JSON.
    struct EmptyBody: Encodable, Sendable {}
}
