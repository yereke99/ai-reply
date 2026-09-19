import SwiftUI

/// The short profile step a brand-new account goes through.
///
/// Жаңа тіркелгі: ең қажетті екі-үш сұрақ қана.
///
/// Deliberately three fields. Everything else the product can personalise -
/// templates, working hours, business rules - already has its own screen and is
/// better filled in later by someone who has seen a reply first.
struct RegistrationStepView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AccountModel.self) private var account
    @Environment(ReplyConfigurationModel.self) private var model

    let onFinished: () -> Void

    @State private var role: String = ""
    @State private var descriptionText: String = ""
    @State private var tone: ReplyTone = .natural

    var body: some View {
        AuthScreen {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                VStack(alignment: .leading, spacing: DS.Spacing.s) {
                    Text("registration.title").font(.title.weight(.semibold))
                    Text("registration.subtitle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, DS.Spacing.m)

                DSSection(title: "profile.role") {
                    TextField("profile.role.placeholder", text: $role)
                        .textInputAutocapitalization(.sentences)
                        .padding(DS.Spacing.s)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous)
                                .fill(Color.dsSurface)
                        )
                }

                DSSection(title: "profile.description") {
                    TextField("profile.description.footer", text: $descriptionText, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(DS.Spacing.s)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous)
                                .fill(Color.dsSurface)
                        )
                }

                DSSection(title: "profile.tone") { TonePicker(selection: $tone) }

                if let errorKey = account.errorKey {
                    Label(LocalizedStringKey(errorKey), systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await save() }
                } label: {
                    if account.isBusy {
                        ProgressView().tint(.white)
                    } else {
                        Text("registration.finish")
                    }
                }
                .buttonStyle(DSPrimaryButtonStyle())
                .disabled(account.isBusy)

                Button("registration.skip") { onFinished() }
                    .buttonStyle(DSSecondaryButtonStyle())
                    .disabled(account.isBusy)
            }
        }
        .onAppear {
            // Pre-fill from whatever the local profile already knows, so a user
            // who set this up before signing in does not type it twice.
            let profile = model.profile
            if role.isEmpty { role = profile.role }
            if descriptionText.isEmpty { descriptionText = profile.descriptionText }
            tone = profile.preferredTone
        }
    }

    @MainActor
    private func save() async {
        // The local profile is what the prompt builder reads; the server copy is
        // what a future device restores from. Both are written, once.
        model.updateProfile { profile in
            profile.role = role
            profile.descriptionText = descriptionText
            profile.preferredTone = tone
        }
        let saved = await account.completeRegistration(
            displayName: "",
            role: role,
            description: descriptionText,
            tone: tone.rawValue,
            locale: settings.effectiveLanguage.rawValue
        )
        if saved { onFinished() }
    }
}
