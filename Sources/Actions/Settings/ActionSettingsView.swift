import SwiftUI

extension ActionTint {
    var color: Color {
        switch self {
        case .orange: .orange
        case .teal: .teal
        case .red: .red
        case .green: .green
        case .blue: .blue
        }
    }
}

struct ActionSettingsView: View {
    let configuration: ActionConfiguration
    @Binding var selectedActionID: String?
    @State private var notice: String?

    var body: some View {
        Group {
            if let selectedActionID, let settings = configuration.registry.settings(for: selectedActionID) {
                settings.makeView()
            } else {
                Form {
                    if let notice {
                        Section { Text(notice).font(.caption).foregroundStyle(.secondary) }
                    }
                    ForEach(groups, id: \.self) { group in
                        Section(group.localizedTitle) {
                            ForEach(entries.filter { $0.descriptor.settingsGroup == group }) { entry in
                                actionRow(entry)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .onChange(of: configuration.registry.revision) {
            guard let id = selectedActionID,
                  configuration.registry.settingsEntry(for: id) == nil else { return }
            selectedActionID = nil
            notice = L10n.text("actions.removed_notice")
        }
        .onAppear { configuration.registry.refreshAvailability() }
    }

    private var entries: [ActionSettingsEntry] { configuration.registry.settingsEntries() }
    private var groups: [ActionSettingsGroup] {
        Array(Set(entries.map(\.descriptor.settingsGroup))).sorted {
            $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order
        }
    }

    @ViewBuilder
    private func actionRow(_ entry: ActionSettingsEntry) -> some View {
        let content = HStack(spacing: 12) {
            actionTile(entry.descriptor)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.descriptor.localizedSettingsName).font(.body.weight(.medium))
                Text(entry.state.summary)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if entry.id == configuration.registry.fallbackActionID {
                Text(L10n.text("actions.default_destination")).font(.caption).foregroundStyle(.secondary)
            }
            if case .userToggle = entry.descriptor.enablementPolicy {
                Toggle(L10n.text("actions.enable", entry.descriptor.localizedSettingsName), isOn: Binding(
                    get: { configuration.isActionEnabled(entry.id) },
                    set: { configuration.setActionEnabled($0, for: entry.id) }))
                    .labelsHidden()
                    .accessibilityLabel(L10n.text("actions.enable", entry.descriptor.localizedSettingsName))
                    .accessibilityIdentifier("action-enable-toggle-\(entry.id)")
            }
            if entry.hasSettings {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        if entry.hasSettings {
            Button { selectedActionID = entry.id } label: { content }
                .buttonStyle(.plain)
                .accessibilityHint(L10n.text("actions.settings_hint"))
                .accessibilityIdentifier("action-card-\(entry.id)")
        } else {
            content.accessibilityIdentifier("action-card-\(entry.id)")
        }
    }

    private func actionTile(_ descriptor: ActionDescriptor) -> some View {
        Image(systemName: descriptor.systemImageName)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(descriptor.tint.color)
            .frame(width: 36, height: 36)
            .background(descriptor.tint.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct AppleNotesSettingsView: View {
    let module: AppleNotesModule
    @State private var showsSetup = false

    var body: some View {
        Form {
            destinationSection(name: module.destination?.name, label: L10n.text("action.notes.destination_label")) { showsSetup = true }
            Section(L10n.text("action.settings.ai_rewrite")) {
                settingRow(L10n.text("action.notes.rewrite_help")) {
                    Toggle(L10n.text("action.settings.rewrite_toggle"), isOn: Binding(
                        get: { module.isAIRewriteEnabled }, set: { module.setAIRewriteEnabled($0) }))
                        .accessibilityIdentifier("ai-rewrite-toggle-\(module.descriptor.id)")
                }
                if module.isAIRewriteEnabled {
                    InstructionEditor(title: L10n.text("action.settings.rewrite_style"), saved: module.rewritePrompt,
                        defaultValue: AITextProcessor.localizedDefaultStyle,
                        explanation: L10n.text("action.notes.rewrite_style_help"),
                        onSave: { module.setRewritePrompt($0) })
                }
            }
            Section(L10n.text("action.notes.tags")) {
                settingRow(L10n.text("action.notes.fixed_tag_help")) {
                    TextField(L10n.text("action.notes.fixed_tag"), text: Binding(
                        get: { module.notesTag }, set: { module.setNotesTag($0) }))
                        .accessibilityIdentifier("notes-fixed-tag")
                }
                settingRow(module.isAIRewriteEnabled ? L10n.text("action.notes.ai_tags_help")
                                                     : L10n.text("action.notes.ai_tags_requires_rewrite")) {
                    Toggle(L10n.text("action.notes.ai_tags"), isOn: Binding(
                        get: { module.isAITagsEnabled }, set: { module.setAITagsEnabled($0) }))
                        .disabled(!module.isAIRewriteEnabled)
                        .accessibilityIdentifier("notes-ai-tags-toggle")
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showsSetup) { AppleNotesSetupView(module: module) }
    }
}

struct AppleRemindersSettingsView: View {
    let module: AppleRemindersModule
    @State private var showsSetup = false
    var body: some View {
        Form {
            destinationSection(name: module.destination?.name, label: L10n.text("action.reminders.destination_label")) { showsSetup = true }
            Section(L10n.text("action.settings.ai_rewrite")) {
                settingRow(L10n.text("action.reminders.rewrite_help")) {
                    Toggle(L10n.text("action.settings.rewrite_toggle"), isOn: Binding(
                        get: { module.isAIRewriteEnabled }, set: { module.setAIRewriteEnabled($0) }))
                        .accessibilityIdentifier("ai-rewrite-toggle-\(module.descriptor.id)")
                }
                if module.isAIRewriteEnabled {
                    InstructionEditor(title: L10n.text("action.settings.rewrite_style"), saved: module.rewritePrompt,
                        defaultValue: AITextProcessor.localizedDefaultStyle,
                        explanation: L10n.text("action.settings.rewrite_time_help"),
                        onSave: { module.setRewritePrompt($0) })
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showsSetup) { AppleRemindersSetupView(module: module) }
    }
}

struct AppleCalendarSettingsView: View {
    let module: AppleCalendarModule
    @State private var showsSetup = false
    var body: some View {
        Form {
            destinationSection(name: module.destination?.name, label: L10n.text("action.calendar.destination_label")) { showsSetup = true }
            Section(L10n.text("action.settings.ai_rewrite")) {
                settingRow(L10n.text("action.calendar.rewrite_help")) {
                    Toggle(L10n.text("action.settings.rewrite_toggle"), isOn: Binding(
                        get: { module.isAIRewriteEnabled }, set: { module.setAIRewriteEnabled($0) }))
                        .accessibilityIdentifier("ai-rewrite-toggle-\(module.descriptor.id)")
                }
                if module.isAIRewriteEnabled {
                    InstructionEditor(title: L10n.text("action.settings.rewrite_style"), saved: module.rewritePrompt,
                        defaultValue: AITextProcessor.localizedDefaultStyle,
                        explanation: L10n.text("action.settings.rewrite_time_help"),
                        onSave: { module.setRewritePrompt($0) })
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showsSetup) { AppleCalendarSetupView(module: module) }
    }
}

@MainActor
private func destinationSection(name: String?, label: String, show: @escaping @MainActor () -> Void) -> some View {
    Section(L10n.text("action.settings.destination")) {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name ?? L10n.text("action.state.no_destination")).font(.body.weight(.medium))
                Text(L10n.text("action.settings.destination_help")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button(name == nil ? L10n.text("common.choose") : L10n.text("common.change"), action: show)
                .accessibilityLabel(L10n.text("action.settings.choose_destination", label))
        }
        .padding(.vertical, 4)
    }
}

private struct AppleNotesSetupView: View {
    let module: AppleNotesModule
    @Environment(\.dismiss) private var dismiss
    @State private var destinations: [AppleNotes.Destination] = []
    @State private var selectedID = ""
    @State private var isBusy = false
    @State private var status: DestinationSetupStatus?
    var body: some View {
        destinationSetup(title: L10n.text("action.notes.setup.title"), explanation: L10n.text("action.notes.setup.explanation"),
            permission: L10n.text("action.notes.setup.permission"), pickerLabel: L10n.text("action.setup.save_to"),
            values: destinations.map { ($0.id, $0.name) }, selectedID: $selectedID, isBusy: isBusy,
            message: status?.text ?? L10n.text("action.notes.setup.test_help"),
            reload: load, verify: verify, dismiss: { dismiss() })
        .task { load() }
    }
    private func load() { run(messageKey: "action.notes.setup.loading") {
        let values = try await module.loadDestinations(); destinations = values
        selectedID = values.first(where: { $0.id == module.destination?.id })?.id ?? values[0].id
        status = .key("action.setup.choose_then_verify")
    } }
    private func verify() { guard let value = destinations.first(where: { $0.id == selectedID }) else { return }
        run(messageKey: "action.notes.setup.verifying") { try await module.verifyAndSetDestination(value); dismiss() } }
    private func run(messageKey: String, _ work: @escaping @MainActor () async throws -> Void) {
        isBusy = true; status = .key(messageKey)
        Task { defer { isBusy = false }; do { try await work() } catch { status = .failure(ActionFailure.presentation(for: error)) } }
    }
}

private struct AppleRemindersSetupView: View {
    let module: AppleRemindersModule
    @Environment(\.dismiss) private var dismiss
    @State private var destinations: [AppleReminders.Destination] = []
    @State private var selectedID = ""
    @State private var isBusy = false
    @State private var status: DestinationSetupStatus?
    var body: some View {
        destinationSetup(title: L10n.text("action.reminders.setup.title"), explanation: L10n.text("action.reminders.setup.explanation"),
            permission: L10n.text("action.reminders.setup.permission"), pickerLabel: L10n.text("action.setup.save_to"),
            values: destinations.map { ($0.id, $0.name) }, selectedID: $selectedID, isBusy: isBusy,
            message: status?.text ?? L10n.text("action.reminders.setup.test_help"),
            reload: load, verify: verify, dismiss: { dismiss() })
        .task { load() }
    }
    private func load() { run(messageKey: "action.reminders.setup.loading") {
        let values = try await module.loadDestinations(); destinations = values
        selectedID = values.first(where: { $0.id == module.destination?.id })?.id ?? values[0].id
        status = .key("action.setup.choose_then_verify")
    } }
    private func verify() { guard let value = destinations.first(where: { $0.id == selectedID }) else { return }
        run(messageKey: "action.reminders.setup.verifying") { try await module.verifyAndSetDestination(value); dismiss() } }
    private func run(messageKey: String, _ work: @escaping @MainActor () async throws -> Void) {
        isBusy = true; status = .key(messageKey)
        Task { defer { isBusy = false }; do { try await work() } catch { status = .failure(ActionFailure.presentation(for: error)) } }
    }
}

private struct AppleCalendarSetupView: View {
    let module: AppleCalendarModule
    @Environment(\.dismiss) private var dismiss
    @State private var destinations: [AppleCalendar.Destination] = []
    @State private var selectedID = ""
    @State private var isBusy = false
    @State private var status: DestinationSetupStatus?
    var body: some View {
        destinationSetup(title: L10n.text("action.calendar.setup.title"), explanation: L10n.text("action.calendar.setup.explanation"),
            permission: L10n.text("action.calendar.setup.permission"), pickerLabel: L10n.text("action.setup.save_to"),
            values: destinations.map { ($0.id, $0.name) }, selectedID: $selectedID, isBusy: isBusy,
            message: status?.text ?? L10n.text("action.calendar.setup.test_help"),
            reload: load, verify: verify, dismiss: { dismiss() })
        .task { load() }
    }
    private func load() { run(messageKey: "action.calendar.setup.loading") {
        let values = try await module.loadDestinations(); destinations = values
        selectedID = values.first(where: { $0.id == module.destination?.id })?.id ?? values[0].id
        status = .key("action.setup.choose_then_verify")
    } }
    private func verify() { guard let value = destinations.first(where: { $0.id == selectedID }) else { return }
        run(messageKey: "action.calendar.setup.verifying") { try await module.verifyAndSetDestination(value); dismiss() } }
    private func run(messageKey: String, _ work: @escaping @MainActor () async throws -> Void) {
        isBusy = true; status = .key(messageKey)
        Task { defer { isBusy = false }; do { try await work() } catch { status = .failure(ActionFailure.presentation(for: error)) } }
    }
}

@MainActor
private func destinationSetup(title: String, explanation: String, permission: String, pickerLabel: String,
                              values: [(String, String)], selectedID: Binding<String>, isBusy: Bool,
                              message: String, reload: @escaping () -> Void, verify: @escaping () -> Void,
                              dismiss: @escaping () -> Void) -> some View {
    VStack(alignment: .leading, spacing: 16) {
        Text(title).font(.headline)
        Text(explanation).font(.callout)
        VStack(alignment: .leading, spacing: 8) {
            Text(permission)
            if !values.isEmpty {
                Picker(pickerLabel, selection: selectedID) {
                    ForEach(values, id: \.0) { Text($0.1).tag($0.0) }
                }
            }
            Button(L10n.text("action.setup.reload"), action: reload)
        }
        .font(.callout).disabled(isBusy)
        Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        HStack {
            if isBusy { ProgressView().controlSize(.small) }
            Spacer()
            Button(L10n.text("common.close"), action: dismiss).keyboardShortcut(.cancelAction)
            Button(L10n.text("action.setup.verify_finish"), action: verify).buttonStyle(.borderedProminent)
                .disabled(isBusy || selectedID.wrappedValue.isEmpty)
        }
    }
    .padding(24).frame(width: 440)
}

private enum DestinationSetupStatus {
    case key(String)
    case failure(ActionFailure)

    var text: String {
        switch self {
        case .key(let key): L10n.text(key)
        case .failure(let failure): failure.localizedDescription
        }
    }
}
