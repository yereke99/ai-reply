import SwiftUI

/// Phone or e-mail entry: the first screen a new user sees.
///
/// Кіру экраны: телефон нөмірі немесе пошта.
///
/// The country list comes from the server (`/api/v1/config`), so adding a
/// country is a backend change, not an app release. Validation is left to the
/// server too - the field accepts what the user types and the server answers
/// with a precise error, which is the only rule that cannot be bypassed.
struct SignInView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AccountModel.self) private var account

    /// Which identifier the user is entering.
    private enum Method: String, CaseIterable {
        case phone, email
    }

    @State private var method: Method = .phone
    @State private var country: AccountAPI.Country?
    @State private var digits: String = ""
    @State private var email: String = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                header

                Picker("account.method", selection: $method) {
                    Text("account.method.phone").tag(Method.phone)
                    Text("account.method.email").tag(Method.email)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if method == .phone { phoneField } else { emailField }

                if let errorKey = account.errorKey {
                    Label(LocalizedStringKey(errorKey), systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await submit() }
                } label: {
                    if account.isBusy {
                        ProgressView().tint(.white)
                    } else {
                        Text("account.continue")
                    }
                }
                .buttonStyle(DSPrimaryButtonStyle())
                .disabled(account.isBusy || !isComplete)

                Text("account.legal.footer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(DS.Spacing.l)
            .frame(maxWidth: DS.Layout.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color.dsBackground)
        .task {
            await account.loadServerConfig()
            if country == nil { country = defaultCountry }
            isFieldFocused = true
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            AppMarkView(size: 56)
            Text("account.signIn.title")
                .font(.title.weight(.semibold))
            Text("account.signIn.subtitle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, DS.Spacing.m)
    }

    private var phoneField: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.s) {
                Menu {
                    ForEach(account.countries) { option in
                        Button {
                            country = option
                        } label: {
                            Text(verbatim: "\(option.flag) \(option.name) \(option.dialCode)")
                        }
                    }
                } label: {
                    HStack(spacing: DS.Spacing.xxs) {
                        Text(verbatim: country.map { "\($0.flag) \($0.dialCode)" } ?? "+…")
                            .font(.body.weight(.medium))
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .padding(.horizontal, DS.Spacing.s)
                    .frame(height: DS.Layout.minimumTouchTarget)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous)
                            .fill(Color.dsSurface)
                    )
                }
                .disabled(account.countries.isEmpty)

                TextField("account.phone.placeholder", text: $digits)
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .focused($isFieldFocused)
                    .padding(.horizontal, DS.Spacing.s)
                    .frame(height: DS.Layout.minimumTouchTarget)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous)
                            .fill(Color.dsSurface)
                    )
                    .onChange(of: digits) { _, newValue in
                        // Keep only digits: a pasted "+7 (701) 123-45-67" should
                        // not become an error the user has to decipher.
                        let filtered = newValue.filter(\.isNumber)
                        if filtered != newValue { digits = filtered }
                    }
            }

            if let example = country?.example {
                Text(verbatim: example)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emailField: some View {
        TextField("account.email.placeholder", text: $email)
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($isFieldFocused)
            .padding(.horizontal, DS.Spacing.s)
            .frame(height: DS.Layout.minimumTouchTarget)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous)
                    .fill(Color.dsSurface)
            )
    }

    // MARK: Logic

    /// Falls back to Kazakhstan, then to whatever the server listed first.
    private var defaultCountry: AccountAPI.Country? {
        let regionCode = Locale.current.region?.identifier
        return account.countries.first { $0.iso == regionCode }
            ?? account.countries.first { $0.iso == "KZ" }
            ?? account.countries.first
    }

    private var identifier: String {
        switch method {
        case .phone: return (country?.dialCode ?? "+") + digits
        case .email: return email.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private var isComplete: Bool {
        switch method {
        case .phone: return digits.count >= 6 && country != nil
        case .email: return email.contains("@") && email.count >= 6
        }
    }

    @MainActor
    private func submit() async {
        await account.requestCode(identifier: identifier,
                                  locale: settings.effectiveLanguage.rawValue)
    }
}
