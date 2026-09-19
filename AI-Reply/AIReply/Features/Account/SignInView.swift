import SwiftUI

struct SignInView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AccountModel.self) private var account

    private enum Method: String, CaseIterable {
        case phone, email
    }

    private enum Field: Hashable {
        case phone, email
    }

    @State private var method: Method = .phone
    @State private var country: AccountAPI.Country?
    @State private var digits = ""
    @State private var email = ""
    @FocusState private var focusedField: Field?

    var body: some View {
        AuthScreen {
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
                    focusedField = nil
                    Task { await submit() }
                } label: {
                    if account.isBusy { ProgressView().tint(.white) }
                    else { Text("account.continue") }
                }
                .buttonStyle(.dsPrimary)
                .disabled(account.isBusy || !isComplete)

                Text("account.legal.footer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            await account.loadServerConfig()
            if country == nil { country = defaultCountry }
        }
        .onChange(of: method) { _, value in
            focusedField = value == .phone ? .phone : .email
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            AppMarkView(size: 56)
            Text("account.signIn.title").font(.title.weight(.semibold))
            Text("account.signIn.subtitle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var phoneField: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: 0) {
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
                    .frame(minHeight: 54)
                }
                .disabled(account.countries.isEmpty)

                Divider().frame(height: 30)

                TextField("account.phone.placeholder", text: phoneBinding)
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .focused($focusedField, equals: .phone)
                    .padding(.horizontal, DS.Spacing.s)
                    .frame(minHeight: 54)
            }
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous)
                    .fill(Color.dsSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous)
                    .stroke(focusedField == .phone ? Color.accentColor : Color.clear, lineWidth: 2)
            )

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
            .focused($focusedField, equals: .email)
            .padding(.horizontal, DS.Spacing.m)
            .frame(minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous)
                    .fill(Color.dsSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous)
                    .stroke(focusedField == .email ? Color.accentColor : Color.clear, lineWidth: 2)
            )
    }

    private var phoneBinding: Binding<String> {
        Binding(
            get: { formattedPhone(digits) },
            set: { digits = String($0.filter(\.isNumber).prefix(12)) }
        )
    }

    private func formattedPhone(_ value: String) -> String {
        var remaining = Array(value)
        let sizes = [3, 3, 2, 2, 2]
        var groups: [String] = []
        for size in sizes where !remaining.isEmpty {
            groups.append(String(remaining.prefix(size)))
            remaining.removeFirst(min(size, remaining.count))
        }
        return groups.joined(separator: " ")
    }

    private var defaultCountry: AccountAPI.Country? {
        let regionCode = Locale.current.region?.identifier
        return account.countries.first { $0.iso == regionCode }
            ?? account.countries.first { $0.iso == "KZ" }
            ?? account.countries.first
    }

    private var identifier: String {
        method == .phone
            ? (country?.dialCode ?? "+") + digits
            : email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isComplete: Bool {
        method == .phone
            ? digits.count >= 6 && country != nil
            : email.contains("@") && email.count >= 6
    }

    @MainActor
    private func submit() async {
        await account.requestCode(identifier: identifier, locale: settings.effectiveLanguage.rawValue)
    }
}
