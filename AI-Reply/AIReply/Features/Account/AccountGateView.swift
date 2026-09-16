import SwiftUI

/// Decides whether the app shows its normal content or the sign-in flow.
///
/// Тіркелгі қажет болса — кіру экраны, әйтпесе қосымша әдеттегідей ашылады.
///
/// The gate is deliberately conditional. A build pointed at no backend, or a
/// user who still generates with their own key, never sees a sign-in screen:
/// the product they installed keeps working exactly as it did. Only a build
/// configured for our service asks for an account, because only there does an
/// account mean anything.
struct AccountGateView<Content: View>: View {

    @Environment(AccountModel.self) private var account

    @ViewBuilder var content: Content

    @State private var isCompletingRegistration = false

    var body: some View {
        Group {
            if !AIConfiguration.shared.requiresAccount {
                content
            } else if isCompletingRegistration {
                RegistrationStepView { isCompletingRegistration = false }
            } else {
                switch account.phase {
                case .signedOut:
                    SignInView()
                case let .awaitingCode(_, masked, demoMode):
                    VerifyCodeView(masked: masked, demoMode: demoMode) { isNewUser in
                        isCompletingRegistration = isNewUser
                    }
                case .signedIn:
                    content
                }
            }
        }
        .animation(.default, value: account.phase)
        .task {
            guard AIConfiguration.shared.requiresAccount else { return }
            await account.refresh()
        }
    }
}
