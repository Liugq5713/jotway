import SwiftUI

struct IntentRulesSettingsView: View {
    let appState: AppState
    @State private var newPhrase = ""
    @State private var newActionID = ""
    @FocusState private var isEditingPhrase: Bool

    private var rules: [IntentRule] { appState.intentRules }
    private var availableActions: [ActionDescriptor] {
        _ = appState.actionRegistry.revision
        return appState.actionRegistry.executionSnapshots().map(\.descriptor)
    }
    private var selectedAction: ActionDescriptor? {
        availableActions.first { $0.id == newActionID }
    }
    private var canAddRule: Bool {
        !newPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedAction != nil
    }

    var body: some View {
        rulesSection
            .onChange(of: availableActions.map(\.id), initial: true) { _, ids in
                if !ids.contains(newActionID) { newActionID = ids.first ?? "" }
            }
    }

    private var rulesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !rules.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(rules) { rule in ruleRow(rule) }
                    }
                }
                ruleEditor
                Text(L10n.text(availableActions.isEmpty ? "jev.rules.no_actions_help" : "jev.rules.help"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var ruleEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(L10n.text("jev.rules.starts_with"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize()
                TextField(L10n.text("jev.rules.phrase"), text: $newPhrase,
                          prompt: Text(L10n.text("jev.rules.phrase_example")))
                    .textFieldStyle(.plain)
                    .labelsHidden()
                    .font(.system(size: 13))
                    .accessibilityLabel(L10n.text("jev.rules.phrase"))
                    .accessibilityIdentifier("intent-rule-phrase")
                    .focused($isEditingPhrase)
                    .onSubmit(addRule)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isEditingPhrase ? Color.accentColor.opacity(0.65) : .primary.opacity(0.1),
                                  lineWidth: isEditingPhrase ? 1.5 : 1)
                    .allowsHitTesting(false)
            }
            HStack(spacing: 12) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.callout).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                targetMenu
                Button(action: addRule) {
                    Label(L10n.text("jev.rules.add"), systemImage: "plus")
                }
                .buttonStyle(ServiceSettingsButtonStyle(prominent: true))
                .disabled(!canAddRule)
                .accessibilityIdentifier("intent-rule-add")
            }
        }
    }

    private var targetMenu: some View {
        Menu {
            Picker(L10n.text("jev.rules.target_action"), selection: $newActionID) {
                ForEach(availableActions, id: \.id) { action in
                    Label(action.localizedTitle, systemImage: action.systemImageName).tag(action.id)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 8) {
                if let action = selectedAction {
                    Image(systemName: action.systemImageName)
                        .foregroundStyle(action.tint.color)
                        .accessibilityHidden(true)
                    Text(action.localizedTitle)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L10n.text("jev.rules.no_actions"))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.08))
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(availableActions.isEmpty)
        .accessibilityLabel(L10n.text("jev.rules.target_action"))
        .accessibilityValue(selectedAction?.localizedTitle ?? L10n.text("jev.rules.no_actions"))
        .accessibilityIdentifier("intent-rule-target")
    }

    private func ruleRow(_ rule: IntentRule) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(rule.phrase)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .help(rule.phrase)
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right").accessibilityHidden(true)
                    Text(actionTitle(rule.actionID))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(role: .destructive) { appState.removeIntentRule(id: rule.id) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .help(L10n.text("jev.rules.delete"))
            .accessibilityLabel(L10n.text("jev.rules.delete_phrase", rule.phrase))
            .accessibilityIdentifier("intent-rule-delete-\(rule.id)")
        }
        .padding(12)
        .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            Text(L10n.text("jev.rules.section"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if !rules.isEmpty {
                Text(rules.count, format: .number)
                    .font(.caption.weight(.medium)).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.primary.opacity(0.04), in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }

    private func addRule() {
        guard canAddRule, let action = selectedAction else { return }
        appState.addIntentRule(phrase: newPhrase, actionID: action.id)
        newPhrase = ""
    }

    private func actionTitle(_ id: String) -> String {
        appState.actionRegistry.descriptor(for: id)?.localizedTitle ?? id
    }
}
