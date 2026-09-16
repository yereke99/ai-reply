import SwiftUI

/// Chooses where replies are generated: this device's own key, or our service.
///
/// Жауап қайда жасалады: құрылғыдағы кілт пе, әлде біздің сервер ме.
///
/// The switch is here rather than hidden behind a build flag because both modes
/// are real products. Direct mode is what an individual with their own API key
/// wants; service mode is what everyone else wants, and the only one where an
/// account, a plan and a quota mean anything.
struct ServiceModeEditor: View {

    @Binding var mode: AITransportMode

    @State private var urlText: String = AIConfiguration.shared.backendBaseURLString
    @State private var isURLValid: Bool = AIConfiguration.shared.backendBaseURL != nil

    var body: some View {
        Section {
            Picker("settings.service.mode", selection: $mode) {
                Text("settings.service.direct").tag(AITransportMode.direct)
                Text("settings.service.backend").tag(AITransportMode.backend)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: mode) { _, newValue in
                AIConfiguration.shared.setMode(newValue)
            }

            if mode == .backend {
                TextField("settings.service.url.placeholder", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit(save)
                    .onChange(of: urlText) { _, _ in isURLValid = true }

                if !isURLValid {
                    Label("settings.service.url.invalid", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("settings.service")
        } footer: {
            Text("settings.service.footer")
        }
        .onDisappear(perform: save)
    }

    /// Stores the address and reports whether it was usable. HTTPS is required
    /// everywhere except a local address, which is what makes a laptop usable
    /// during development without weakening anything in the field.
    private func save() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        AIConfiguration.shared.setBackendBaseURL(trimmed)
        isURLValid = trimmed.isEmpty || AIConfiguration.shared.backendBaseURL != nil
    }
}
