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
        .onAppear { configuration.registry.requestAvailabilityRefresh() }
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

    var body: some View {
        // The editable preferences live in UserDefaults; the module revision drives their UI refresh.
        let _ = module.configurationRevision
        Form {
            StorageDestinationSection(destination: module.destination, failure: module.repairFailure,
                label: L10n.text("action.notes.destination_label"),
                defaultLocation: L10n.text("action.notes.default_location"), privacyPane: "Automation",
                name: { $0.name }, authorize: { try await module.authorizeAndSetDefaultDestination() },
                load: { try await module.loadDestinations() }, save: { try module.setDestination($0) })
            Section(L10n.text("action.notes.ai_supplements")) {
                settingRow(L10n.text("action.notes.supplement_help")) {
                    Toggle(L10n.text("action.notes.supplement_toggle"), isOn: Binding(
                        get: { module.isAISupplementEnabled }, set: { module.setAISupplementEnabled($0) }))
                        .accessibilityIdentifier("notes-ai-supplement-toggle")
                }
                if module.hasLegacyRewritePrompt {
                    Text(L10n.text("action.notes.legacy_rewrite_help"))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("notes-legacy-rewrite-notice")
                }
                if module.isAISupplementEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("action.notes.supplement_preferences"))
                            .font(.body.weight(.medium))
                        InstructionEditor(title: L10n.text("action.notes.supplement_preferences"), saved: module.supplementPrompt,
                            defaultValue: AINotesSupplementProcessor.localizedDefaultPreference,
                            explanation: L10n.text("action.notes.supplement_preferences_help"),
                            compactFooter: true,
                            onSave: { module.setSupplementPrompt($0) })
                    }
                }
            }
            Section(L10n.text("action.notes.tags")) {
                settingRow(L10n.text("action.notes.fixed_tag_help")) {
                    TextField(L10n.text("action.notes.fixed_tag"), text: Binding(
                        get: { module.notesTag }, set: { module.setNotesTag($0) }))
                        .accessibilityIdentifier("notes-fixed-tag")
                }
                settingRow(module.isAISupplementEnabled ? L10n.text("action.notes.ai_tags_help")
                                                        : L10n.text("action.notes.ai_tags_requires_supplements")) {
                    Toggle(L10n.text("action.notes.ai_tags"), isOn: Binding(
                        get: { module.isAITagsEnabled }, set: { module.setAITagsEnabled($0) }))
                        .disabled(!module.isAISupplementEnabled)
                        .accessibilityIdentifier("notes-ai-tags-toggle")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct AppleRemindersSettingsView: View {
    let module: AppleRemindersModule
    var body: some View {
        Form {
            StorageDestinationSection(destination: module.destination, failure: module.repairFailure,
                label: L10n.text("action.reminders.destination_label"),
                defaultLocation: L10n.text("action.reminders.default_location"), privacyPane: "Reminders",
                name: { $0.name }, authorize: { try await module.authorizeAndSetDefaultDestination() },
                load: { try await module.loadDestinations() }, save: { try module.setDestination($0) })
            Section(L10n.text("action.settings.time_rules")) {
                Text(L10n.text("action.reminders.time_help"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
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
    }
}

struct AppleCalendarSettingsView: View {
    let module: AppleCalendarModule
    var body: some View {
        Form {
            StorageDestinationSection(destination: module.destination, failure: module.repairFailure,
                label: L10n.text("action.calendar.destination_label"),
                defaultLocation: L10n.text("action.calendar.default_location"), privacyPane: "Calendars",
                name: { $0.name }, authorize: { try await module.authorizeAndSetDefaultDestination() },
                load: { try await module.loadDestinations() }, save: { try module.setDestination($0) })
            Section(L10n.text("action.settings.time_rules")) {
                Text(L10n.text("action.calendar.time_help"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
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
    }
}

/// Shared presentation only; each module owns authorization, defaults, and typed persistence.
private struct StorageDestinationSection<Destination: Identifiable>: View where Destination.ID == String {
    let destination: Destination?
    let failure: ActionFailure?
    let label: String
    let defaultLocation: String
    let privacyPane: String
    let name: (Destination) -> String
    let authorize: @MainActor () async throws -> Void
    let load: @MainActor () async throws -> [Destination]
    let save: @MainActor (Destination) throws -> Void
    @State private var showsPicker = false
    @State private var task: Task<Void, Never>?
    @State private var status: DestinationSetupStatus?

    var body: some View {
        Section(L10n.text("action.settings.destination")) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(destination.map(name) ?? defaultLocation).font(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.text(destination == nil ? "action.settings.authorize_help" : "action.settings.destination_help"))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if task != nil { ProgressView().controlSize(.small) }
                if destination == nil || failure != nil {
                    Button(L10n.text(failure == nil ? "action.setup.authorize" : "action.setup.retry_authorization"), action: requestAuthorization)
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel(L10n.text("action.setup.authorize_app", label))
                        .accessibilityIdentifier("authorize-\(privacyPane.lowercased())")
                        .disabled(task != nil)
                } else {
                    Button(L10n.text("common.change")) { showsPicker = true }
                        .accessibilityLabel(L10n.text("action.settings.choose_destination", label))
                }
            }
            .padding(.vertical, 4)
            if let message = status?.text ?? failure?.localizedDescription {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if failure != nil {
                privacySettingsLink(pane: privacyPane)
            }
        }
        .sheet(isPresented: $showsPicker) {
            StorageDestinationPicker(destination: destination, name: name, load: load, save: save)
        }
        .onDisappear {
            task?.cancel()
            task = nil
            status = nil
        }
    }

    private func requestAuthorization() {
        guard task == nil else { return }
        status = .key("action.setup.authorizing")
        task = Task { @MainActor in
            defer { task = nil }
            do {
                try await authorize()
                try Task.checkCancellation()
                status = nil
            } catch {
                guard !Task.isCancelled else { return }
                status = .failure(ActionFailure.presentation(for: error))
            }
        }
    }
}

private struct StorageDestinationPicker<Destination: Identifiable>: View where Destination.ID == String {
    let destination: Destination?
    let name: (Destination) -> String
    let load: @MainActor () async throws -> [Destination]
    let save: @MainActor (Destination) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var destinations: [Destination] = []
    @State private var selectedID = ""
    @State private var isBusy = true
    @State private var status: DestinationSetupStatus?
    @State private var reloadID = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("action.settings.destination")).font(.headline)
            if !destinations.isEmpty {
                Picker(L10n.text("action.setup.save_to"), selection: $selectedID) {
                    ForEach(destinations) { Text(name($0)).tag($0.id) }
                }
                .disabled(isBusy)
            }
            if let status {
                Text(status.text).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(L10n.text("action.setup.reload")) { reloadID += 1 }
                    .disabled(isBusy)
                if isBusy { ProgressView().controlSize(.small) }
                Spacer()
                Button(L10n.text("common.cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.text("common.save"), action: saveSelection)
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || !destinations.contains(where: { $0.id == selectedID }))
            }
        }
        .padding(24).frame(width: 440)
        .task(id: reloadID) {
            isBusy = true
            destinations = []
            status = nil
            defer { isBusy = false }
            do {
                let values = try await load()
                try Task.checkCancellation()
                destinations = values
                selectedID = values.first(where: { $0.id == selectedID })?.id
                    ?? values.first(where: { $0.id == destination?.id })?.id
                    ?? values.first?.id ?? ""
            } catch {
                guard !Task.isCancelled else { return }
                status = .failure(ActionFailure.presentation(for: error))
            }
        }
    }

    private func saveSelection() {
        guard let value = destinations.first(where: { $0.id == selectedID }) else { return }
        do {
            try save(value)
            dismiss()
        } catch { status = .failure(ActionFailure.presentation(for: error)) }
    }
}

@MainActor
private func privacySettingsLink(pane: String) -> some View {
    Group {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_" + pane) {
            Link(L10n.text("action.setup.open_settings"), destination: url)
        }
    }
}

/// Also owned by the setup window, so closing it cancels before SwiftUI tears down.
@MainActor
final class AppleNotesSetupLifetime {
    private(set) var isActive = true
    var task: Task<Void, Never>?

    func invalidate() {
        isActive = false
        task?.cancel()
        task = nil
    }
}

struct AppleNotesSetupView: View {
    let module: AppleNotesModule
    let onFinish: @MainActor (ActionSetupResult) -> Void
    @State private var isBusy = false
    @State private var status: DestinationSetupStatus?
    @State private var isActive = false
    @State private var lifetime: AppleNotesSetupLifetime

    init(module: AppleNotesModule, lifetime: AppleNotesSetupLifetime = AppleNotesSetupLifetime(),
         onFinish: @escaping @MainActor (ActionSetupResult) -> Void) {
        self.module = module
        self.onFinish = onFinish
        _lifetime = State(initialValue: lifetime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("action.notes.setup.title")).font(.headline)
            Text(L10n.text("action.notes.setup.explanation")).font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text(module.destination?.name ?? L10n.text("action.notes.default_location"))
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            if let message = status?.text ?? module.repairFailure?.localizedDescription {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("notes-setup-status")
            }
            if module.repairFailure != nil {
                privacySettingsLink(pane: "Automation")
            }
            HStack {
                if isBusy { ProgressView().controlSize(.small) }
                Spacer()
                Button(L10n.text("common.cancel")) { finish(.cancelled) }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.text(module.repairFailure == nil ? "action.setup.authorize" : "action.setup.retry_authorization"), action: authorize)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("notes-setup-authorize")
                    .disabled(isBusy)
            }
        }
        .padding(24).frame(width: 440)
        .onAppear { isActive = true }
        .onDisappear { invalidate() }
    }

    private func authorize() {
        guard isActive, lifetime.isActive, !isBusy else { return }
        isBusy = true
        status = .key("action.setup.authorizing")
        lifetime.task = Task { @MainActor in
            do {
                try await module.authorizeAndSetDefaultDestination()
                guard isActive, lifetime.isActive, !Task.isCancelled else { return }
                finish(.completed)
            } catch {
                guard isActive, lifetime.isActive, !Task.isCancelled else { return }
                status = .failure(ActionFailure.presentation(for: error))
                lifetime.task = nil
                isBusy = false
            }
        }
    }

    private func finish(_ result: ActionSetupResult) {
        guard isActive, lifetime.isActive else { return }
        invalidate()
        onFinish(result)
    }

    private func invalidate() {
        isActive = false
        lifetime.invalidate()
        isBusy = false
    }
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
