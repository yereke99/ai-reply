import SwiftUI

/// The account block inside Settings.
///
/// Баптаулардағы тіркелгі бөлімі: тариф, квота, шығу.
///
/// Shows what the user needs to recognise their account and nothing more: the
/// masked identifier the server sent back, the current plan, what is left
/// today, and the way out.
struct AccountSettingsSection: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AccountModel.self) private var account

    @State private var isConfirmingSignOut = false

    var body: some View {
        Section {
            if account.isSignedIn {
                LabeledContent {
                    Text(verbatim: account.displayIdentifier)
                        .foregroundStyle(.secondary)
                } label: {
                    Label("settings.account.identifier", systemImage: "person.crop.circle")
                }

                NavigationLink {
                    SubscriptionView()
                } label: {
                    LabeledContent {
                        Text(verbatim: planSummary)
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("settings.account.plan", systemImage: "creditcard")
                    }
                }

                Button(role: .destructive) {
                    isConfirmingSignOut = true
                } label: {
                    Label("settings.account.signOut", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .confirmationDialog("settings.account.signOut.confirm",
                                    isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
                    Button("settings.account.signOut", role: .destructive) {
                        Task { await account.signOut() }
                    }
                    Button("common.cancel", role: .cancel) {}
                }
            } else {
                Label("settings.account.signedOut", systemImage: "person.crop.circle.badge.questionmark")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("settings.account")
        } footer: {
            Text("settings.account.footer")
        }
        .task { await account.refresh() }
    }

    private var planSummary: String {
        guard let plan = account.subscription?.plan else { return "" }
        let name = plan.localizedName(settings.effectiveLanguage.rawValue)
        guard account.usage.dailyLimit > 0 else { return name }
        return "\(name) · \(account.usage.remainingToday)/\(account.usage.dailyLimit)"
    }
}
