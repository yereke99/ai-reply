import SwiftUI

/// One communication profile: who this is, how to sound, what they are told,
/// and what must never be promised.
///
/// The sections adapt to the relationship, because the questions genuinely
/// differ. A Friend template shows name, tone, emoji and free notes - asking
/// what you sell before someone can set up a casual template would be a worse
/// product, not a more capable one. Client, Business, Work and custom templates
/// additionally get business context, their own optional working hours, and
/// rules.
///
/// Nothing on this screen mentions prompts, tokens or models. The user
/// describes their situation; `ReplyPromptBuilder` is what turns it into
/// context.
struct TemplateEditorView: View {

    let templateID: String

    @Environment(ReplyConfigurationModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ReplyTemplate?
    @State private var isDictating = false
    @State private var isConfirmingDelete = false
    @State private var suggestion: VoiceConfigurationParser.Suggestion?

    var body: some View {
        Form {
            if let binding = draftBinding {
                basicSection(binding)
                if binding.wrappedValue.relationship.usesBusinessContext {
                    businessSection(binding)
                    hoursSection(binding)
                    rulesSection(binding)
                }
                styleSection(binding)
                notesSection(binding)

                if !binding.wrappedValue.isBuiltIn {
                    Section {
                        Button("templates.delete", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if draft == nil {
                var loaded = model.configuration.template(id: templateID)
                // A template saved before business context existed gets its
                // container here, so the editor can write into it.
                if loaded?.relationship.usesBusinessContext == true { loaded?.ensureBusinessContext() }
                draft = loaded
            }
        }
        .onDisappear(perform: save)
        .sheet(isPresented: $isDictating) {
            DictationSheet(language: settings.effectiveLanguage) { transcript in
                acceptDictation(transcript)
            }
        }
        .sheet(item: $suggestion) { value in
            VoiceSuggestionSheet(
                suggestion: value,
                existingHours: draft?.workingHoursOverride ?? model.profile.workingHours
            ) { confirmed in
                apply(confirmed)
            }
        }
        .confirmationDialog("templates.delete.confirm", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("common.delete", role: .destructive) {
                if let draft {
                    model.delete(draft)
                    // Cleared so `onDisappear` cannot resurrect what was just
                    // deleted by saving a stale copy.
                    self.draft = nil
                }
                dismiss()
            }
            Button("common.cancel", role: .cancel) {}
        }
    }

    // MARK: Sections

    private func basicSection(_ template: Binding<ReplyTemplate>) -> some View {
        Section {
            TextField("templates.name", text: nameBinding(template))
                .autocorrectionDisabled()
            LabeledContent {
                Text(template.wrappedValue.relationship.titleKey)
                    .foregroundStyle(.secondary)
            } label: {
                Text("templates.relationship")
            }
            Toggle("templates.visible", isOn: template.isVisible)
        } header: {
            Text("templates.section.basic")
        }
    }

    private func businessSection(_ template: Binding<ReplyTemplate>) -> some View {
        Section {
            TextField("templates.offering.placeholder", text: businessOffering(template), axis: .vertical)
            TextField("templates.summary.placeholder", text: businessSummary(template), axis: .vertical)
                .lineLimit(2...5)
        } header: {
            Text("templates.section.business")
        } footer: {
            Text("templates.section.business.footer")
        }
    }

    /// Per-template hours, off by default. When off the profile's schedule
    /// applies, which is what almost everyone wants; turning it on is for the
    /// case where client hours and work hours genuinely differ.
    private func hoursSection(_ template: Binding<ReplyTemplate>) -> some View {
        Section {
            Toggle("templates.hours.override", isOn: overrideBinding(template))
            if let override = template.wrappedValue.workingHoursOverride, override.isEnabled {
                QuickHoursEditor(hours: overrideHoursBinding(template))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Picker("templates.hours", selection: template.workingHoursBehaviour) {
                ForEach(WorkingHoursBehaviour.allCases) { Text($0.titleKey).tag($0) }
            }
        } header: {
            Text("templates.section.hours")
        } footer: {
            Text("templates.section.hours.footer")
        }
    }

    private func rulesSection(_ template: Binding<ReplyTemplate>) -> some View {
        RulesEditor(rules: businessBinding(template), footerKey: "templates.rules.footer")
    }

    private func styleSection(_ template: Binding<ReplyTemplate>) -> some View {
        Section {
            Picker("templates.tone", selection: template.tone) {
                ForEach(ReplyTone.allCases) { Text($0.titleKey).tag($0) }
            }
            Picker("templates.length", selection: template.replyLength) {
                ForEach(ReplyLength.allCases) { Text($0.titleKey).tag($0) }
            }
            Picker("templates.emoji", selection: template.emojiPolicy) {
                ForEach(EmojiPolicy.allCases) { Text($0.titleKey).tag($0) }
            }
        } header: {
            Text("templates.section.style")
        }
    }

    private func notesSection(_ template: Binding<ReplyTemplate>) -> some View {
        Section {
            ZStack(alignment: .topLeading) {
                if template.wrappedValue.instructions.isEmpty {
                    Text("templates.instructions.placeholder")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: instructionsBinding(template))
                    .frame(minHeight: 110)
            }

            HStack {
                Text(counterText(template.wrappedValue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button {
                    isDictating = true
                } label: {
                    Label("profile.dictate", systemImage: "mic.fill").font(.subheadline)
                }
            }
        } header: {
            Text("templates.instructions")
        } footer: {
            Text("templates.instructions.footer")
        }
    }

    // MARK: Voice

    /// The dictated sentence is appended to the notes VERBATIM. Structured
    /// values are only ever suggested on top of it, so nothing the user said is
    /// replaced by the app's interpretation of it.
    private func acceptDictation(_ transcript: String) {
        guard var current = draft else { return }
        let addition = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !addition.isEmpty else { return }

        let separator = current.instructions.isEmpty ? "" : " "
        current.setInstructions(current.instructions + separator + addition)
        draft = current

        let parsed = VoiceConfigurationParser.parse(addition, language: settings.effectiveLanguage)
        if !parsed.isEmpty { suggestion = parsed }
    }

    private func apply(_ confirmed: VoiceConfigurationParser.Suggestion) {
        guard var current = draft else { return }
        if let updated = confirmed.workingHours(basedOn: current.workingHoursOverride ?? model.profile.workingHours) {
            current.workingHoursOverride = updated
        }
        if !confirmed.rules.isEmpty {
            current.ensureBusinessContext()
            for rule in confirmed.rules { current.business?.addRule(rule) }
        }
        draft = current
    }

    // MARK: Saving

    private func save() {
        guard var draft else { return }
        // A blank name means "use the default": the localized built-in name,
        // or the generic custom label for a user-created template.
        if (draft.customName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.customName = draft.isBuiltIn
                ? nil
                : ReplyTemplate.builtInName(.custom, language: settings.effectiveLanguage.keyboardLanguage)
        }
        // An empty business container is stored as nothing rather than as a set
        // of empty strings, so `effectiveBusiness` stays a meaningful test.
        if draft.business?.isEmpty == true { draft.business = nil }
        model.update(draft)
    }

    private var title: String {
        draft?.displayName(appLanguage: settings.effectiveLanguage) ?? ""
    }

    private func counterText(_ template: ReplyTemplate) -> String {
        String(
            format: settings.localized("profile.counter"),
            template.instructions.unicodeScalars.count,
            ReplyTemplate.maximumInstructionCharacters
        )
    }

    // MARK: Bindings

    /// Writes `customName` directly rather than through `setName`, so deleting
    /// the last character leaves an empty field instead of snapping the old
    /// name back under the user's cursor. The empty case is repaired once, when
    /// the screen closes.
    private func nameBinding(_ template: Binding<ReplyTemplate>) -> Binding<String> {
        Binding(
            get: { template.wrappedValue.customName ?? "" },
            set: { template.wrappedValue.customName = String($0.prefix(ReplyTemplate.maximumNameCharacters)) }
        )
    }

    /// Routed through `setInstructions` so the length cap applies as the user
    /// types rather than truncating silently on save.
    private func instructionsBinding(_ template: Binding<ReplyTemplate>) -> Binding<String> {
        Binding(
            get: { template.wrappedValue.instructions },
            set: { template.wrappedValue.setInstructions($0) }
        )
    }

    private func businessBinding(_ template: Binding<ReplyTemplate>) -> Binding<BusinessContext> {
        Binding(
            get: { template.wrappedValue.business ?? .empty },
            set: { template.wrappedValue.business = $0 }
        )
    }

    private func businessOffering(_ template: Binding<ReplyTemplate>) -> Binding<String> {
        Binding(
            get: { template.wrappedValue.business?.offering ?? "" },
            set: { value in
                var context = template.wrappedValue.business ?? .empty
                context.setOffering(value)
                template.wrappedValue.business = context
            }
        )
    }

    private func businessSummary(_ template: Binding<ReplyTemplate>) -> Binding<String> {
        Binding(
            get: { template.wrappedValue.business?.summary ?? "" },
            set: { value in
                var context = template.wrappedValue.business ?? .empty
                context.setSummary(value)
                template.wrappedValue.business = context
            }
        )
    }

    private func overrideBinding(_ template: Binding<ReplyTemplate>) -> Binding<Bool> {
        Binding(
            get: { template.wrappedValue.workingHoursOverride?.isEnabled ?? false },
            set: { isOn in
                if isOn {
                    var hours = template.wrappedValue.workingHoursOverride ?? model.profile.workingHours
                    hours.isEnabled = true
                    template.wrappedValue.workingHoursOverride = hours
                } else {
                    // Dropped entirely rather than disabled, so "off" means
                    // exactly one thing: follow the profile.
                    template.wrappedValue.workingHoursOverride = nil
                }
            }
        )
    }

    private func overrideHoursBinding(_ template: Binding<ReplyTemplate>) -> Binding<WorkingHours> {
        Binding(
            get: { template.wrappedValue.workingHoursOverride ?? model.profile.workingHours },
            set: { template.wrappedValue.workingHoursOverride = $0 }
        )
    }

    /// Non-optional binding onto the loaded draft, so the body does not need to
    /// unwrap the optional for every field.
    private var draftBinding: Binding<ReplyTemplate>? {
        guard draft != nil else { return nil }
        return Binding(
            get: { draft ?? .builtIn(.custom, sortIndex: 0) },
            set: { draft = $0 }
        )
    }
}
