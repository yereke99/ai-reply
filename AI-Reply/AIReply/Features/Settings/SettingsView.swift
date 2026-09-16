import SwiftUI

struct SettingsView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(ReplyConfigurationModel.self) private var model

    @State private var model_name: String = AIConfiguration.shared.model

    var body: some View {
        Form {
            Section {
                NavigationLink { ProfileEditorView() } label: {
                    Label("home.profile.edit", systemImage: "person.text.rectangle")
                }
                NavigationLink { TemplateListView() } label: {
                    Label("home.profile.templates", systemImage: "text.bubble")
                }
                NavigationLink { WorkingHoursView() } label: {
                    Label("home.profile.hours", systemImage: "clock")
                }
            } header: {
                Text("home.profile.title")
            }

            Section {
                NavigationLink { KeyboardSetupView() } label: {
                    Label("settings.setup.guide", systemImage: "keyboard")
                }
            } header: {
                Text("settings.setup")
            } footer: {
                Text("settings.setup.footer")
            }

            Section {
                APIKeyEditor()
            } header: {
                Text("settings.ai")
            } footer: {
                Text("settings.ai.key.footer")
            }

            Section {
                TextField("settings.ai.model", text: $model_name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { AIConfiguration.shared.setModel(model_name) }
                if model_name != AIConfiguration.defaultModel {
                    Button("settings.ai.reset") {
                        model_name = AIConfiguration.defaultModel
                        AIConfiguration.shared.setModel(model_name)
                    }
                }
            } header: {
                Text("settings.ai.model")
            } footer: {
                Text("settings.ai.model.footer")
            }

            Section("settings.appearance") {
                Picker("settings.appearance", selection: appearanceBinding) {
                    ForEach(AppearancePreference.allCases, id: \.rawValue) { option in
                        Text(option.titleKey).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section {
                Picker("settings.language", selection: languageBinding) {
                    Text("common.system").tag(AppLanguage?.none)
                    ForEach(AppLanguage.allCases) { language in
                        // Always shown in its own language: a Kazakh speaker
                        // looking for Kazakh should see "Қазақша".
                        Text(language.nativeName).tag(AppLanguage?.some(language))
                    }
                }
            } header: {
                Text("settings.language")
            } footer: {
                Text("settings.language.footer")
            }

            Section {
                Text("settings.privacy.body")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("settings.privacy.title")
            }

            Section {
                Button("settings.setup.restart") { model.restartOnboarding() }
            } footer: {
                Text("settings.setup.restart.footer")
            }

            if !AppGroup.isAvailable || !model.isPersistent {
                Section {
                    Label("settings.storage.unavailable", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Color.orange)
                }
            }
        }
        .navigationTitle("settings.title")
        .navigationBarTitleDisplayMode(.inline)
        // Committed on the way out as well as on submit, so a model typed
        // without pressing return is not silently discarded.
        .onDisappear { AIConfiguration.shared.setModel(model_name) }
    }

    private var appearanceBinding: Binding<AppearancePreference> {
        Binding(get: { settings.appearance }, set: { settings.setAppearance($0) })
    }

    private var languageBinding: Binding<AppLanguage?> {
        Binding(get: { settings.language }, set: { settings.setLanguage($0) })
    }
}
