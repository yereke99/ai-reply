import Combine
import SwiftUI

/// Code entry.
///
/// Растау коды. Демо режимінде сервер кодты жібермейді — 1111 жарайды.
///
/// The screen never claims a message was sent when the backend is running in
/// demo mode: it says plainly that the code is fixed. Pretending otherwise
/// would be the one bug a user cannot work around.
struct VerifyCodeView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AccountModel.self) private var account

    let masked: String
    let demoMode: Bool
    /// Called with `true` when the account was created just now.
    let onVerified: (Bool) -> Void

    @State private var code: String = ""
    @State private var secondsUntilResend = 30
    @FocusState private var isFocused: Bool

    private let codeLength = 4
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                VStack(alignment: .leading, spacing: DS.Spacing.s) {
                    Text("account.code.title").font(.title.weight(.semibold))
                    Text("account.code.subtitle \(masked)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, DS.Spacing.m)

                if demoMode {
                    Label("account.code.demo", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .dsCard()
                }

                codeField

                if let errorKey = account.errorKey {
                    Label(LocalizedStringKey(errorKey), systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await verify() }
                } label: {
                    if account.isBusy {
                        ProgressView().tint(.white)
                    } else {
                        Text("account.code.confirm")
                    }
                }
                .buttonStyle(DSPrimaryButtonStyle())
                .disabled(account.isBusy || code.count < codeLength)

                HStack {
                    Button("account.code.resend") {
                        Task {
                            await account.resendCode(locale: settings.effectiveLanguage.rawValue)
                            secondsUntilResend = 30
                        }
                    }
                    .disabled(secondsUntilResend > 0 || account.isBusy)

                    if secondsUntilResend > 0 {
                        Text(verbatim: "\(secondsUntilResend)s")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("common.back") { account.cancelCodeEntry() }
                }
                .font(.subheadline)
            }
            .padding(DS.Spacing.l)
            .frame(maxWidth: DS.Layout.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color.dsBackground)
        .onReceive(timer) { _ in
            if secondsUntilResend > 0 { secondsUntilResend -= 1 }
        }
        .task { isFocused = true }
    }

    private var codeField: some View {
        TextField("", text: $code)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .font(.system(size: 30, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)
            .kerning(10)
            .focused($isFocused)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous)
                    .fill(Color.dsSurface)
            )
            .onChange(of: code) { _, newValue in
                let filtered = String(newValue.filter(\.isNumber).prefix(codeLength))
                if filtered != newValue { code = filtered }
                // Submitting on the last digit is what everyone expects from a
                // four-digit code; the button stays for accessibility.
                if filtered.count == codeLength && !account.isBusy {
                    Task { await verify() }
                }
            }
    }

    @MainActor
    private func verify() async {
        let isNewUser = await account.verify(code: code)
        if account.isSignedIn {
            onVerified(isNewUser)
        } else {
            code = ""
            isFocused = true
        }
    }
}
