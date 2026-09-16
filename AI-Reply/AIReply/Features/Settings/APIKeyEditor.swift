import SwiftUI
import UIKit

/// Entry and management of the OpenAI key.
///
/// The key is typed or pasted here and goes straight into the Keychain. It is
/// never held in `@AppStorage`, never written to App Group defaults, never
/// logged, and never displayed again after it is saved - only whether one
/// exists. Typing a 164-character key on a phone is unpleasant, so Paste is the
/// prominent action.
struct APIKeyEditor: View {

    /// Called after a successful save, so onboarding can advance.
    var onSaved: (() -> Void)?

    @State private var entry: String = ""
    @State private var hasKey: Bool = SecureCredentialStore.hasAPIKey
    @State private var message: LocalizedStringKey?
    @State private var messageIsError = false

    var body: some View {
        Group {
            if hasKey {
                LabeledContent {
                    Label("settings.ai.key.set", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                        .font(.footnote)
                } label: {
                    Text("settings.ai.key")
                }

                Button("settings.ai.key.remove", role: .destructive) {
                    SecureCredentialStore.deleteAPIKey()
                    hasKey = SecureCredentialStore.hasAPIKey
                    entry = ""
                    message = nil
                }
            } else {
                SecureField("onboarding.key.placeholder", text: $entry)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(save)

                Button {
                    paste()
                } label: {
                    Label("onboarding.key.paste", systemImage: "doc.on.clipboard")
                }

                Button("common.save", action: save)
                    .disabled(entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(messageIsError ? Color.red : Color.green)
            }
        }
    }

    private func paste() {
        guard UIPasteboard.general.hasStrings,
              let value = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            show("onboarding.key.clipboardEmpty", isError: true)
            return
        }
        entry = value
        save()
    }

    private func save() {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        // A shape check, not a validity check. Whether the key actually works is
        // answered by the first request, and reporting that honestly beats
        // pretending this can tell.
        guard trimmed.hasPrefix("sk-"), trimmed.count > 20 else {
            show("onboarding.key.invalid", isError: true)
            return
        }
        guard SecureCredentialStore.setAPIKey(trimmed) else {
            show("onboarding.key.saveFailed", isError: true)
            return
        }
        entry = ""
        hasKey = true
        show("onboarding.key.saved", isError: false)
        onSaved?()
    }

    private func show(_ key: LocalizedStringKey, isError: Bool) {
        message = key
        messageIsError = isError
    }
}
