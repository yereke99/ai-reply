import SwiftUI

/// The template list: reorder, hide, edit, create and delete.
struct TemplateListView: View {

    @Environment(ReplyConfigurationModel.self) private var model
    @Environment(AppSettings.self) private var settings

    @State private var isAddingTemplate = false
    @State private var newTemplateName = ""

    var body: some View {
        List {
            Section {
                ForEach(model.templates) { template in
                    NavigationLink {
                        TemplateEditorView(templateID: template.id)
                    } label: {
                        row(for: template)
                    }
                }
                .onMove { source, destination in
                    model.move(fromOffsets: source, toOffset: destination)
                }
                .onDelete { offsets in
                    // Built-ins are filtered out here as well as refused by the
                    // model, so a swipe can never even appear to delete one.
                    for index in offsets {
                        let template = model.templates[index]
                        if !template.isBuiltIn { model.delete(template) }
                    }
                }
            } header: {
                Text("templates.title")
            } footer: {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text("templates.reorder")
                    Text("templates.builtIn.footer")
                }
            }

            Section {
                Button {
                    newTemplateName = ""
                    isAddingTemplate = true
                } label: {
                    Label("templates.add", systemImage: "plus")
                }
            }
        }
        .navigationTitle("templates.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .alert("templates.add", isPresented: $isAddingTemplate) {
            TextField("templates.name", text: $newTemplateName)
                .autocorrectionDisabled()
            Button("common.cancel", role: .cancel) {}
            Button("common.add") {
                let name = newTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                model.addCustomTemplate(named: name)
            }
        } message: {
            Text("templates.add.prompt")
        }
    }

    private func row(for template: ReplyTemplate) -> some View {
        HStack(spacing: DS.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(template.displayName(appLanguage: settings.effectiveLanguage))
                    .font(.body)
                HStack(spacing: DS.Spacing.xxs) {
                    Text(template.tone.titleKey)
                    if !template.isVisible {
                        Text("·")
                        Text("templates.hidden")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if !template.isVisible {
                Image(systemName: "eye.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
