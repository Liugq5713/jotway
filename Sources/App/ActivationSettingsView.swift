import SwiftUI

struct ActivationSettingsView: View {
    let models: ModelConfiguration
    @State private var code = ""
    @State private var issue: String?
    @State private var changingCode = false
    @State private var activating = false
    @State private var operation: Task<Void, Never>?
    private var account: HostedAIState { models.hostedAI }

    var body: some View {
        Section(L10n.text("settings.activation.title")) {
            if models.hasActivationCode {
                HStack {
                    Label(statusTitle, systemImage: statusSymbol)
                        .foregroundStyle(account.status == .active ? Color.green : Color.secondary)
                    Spacer()
                    if account.isRefreshing { ProgressView().controlSize(.small) }
                }
                if let value = account.account {
                    if !value.label.isEmpty { Text(value.label).foregroundStyle(.secondary) }
                    LabeledContent(L10n.text("settings.activation.remaining"), value: value.quota.available.formatted())
                    if value.quota.held > 0 {
                        Text(L10n.text("settings.activation.held", value.quota.held.formatted()))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(L10n.text("settings.activation.remove_help")).font(.caption).foregroundStyle(.secondary)
                if let problem = account.problem {
                    Text(problem.message).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button(L10n.text("settings.activation.refresh")) { refresh() }
                        .disabled(account.isRefreshing || activating)
                    Button(L10n.text(changingCode ? "settings.activation.cancel_change" : "settings.activation.change")) {
                        changingCode.toggle(); code = ""; issue = nil
                    }.disabled(activating)
                    Button(L10n.text("settings.activation.remove"), role: .destructive) {
                        operation?.cancel()
                        do {
                            try models.removeActivationCode()
                            issue = nil; code = ""; changingCode = false
                        } catch { issue = L10n.text("credentials.inaccessible") }
                    }.disabled(activating)
                }
            }
            if !models.hasActivationCode || changingCode {
                SecureField(L10n.text(models.hasActivationCode ? "settings.activation.replacement" : "settings.activation.code"), text: $code)
                    .onSubmit { activate() }
                    .disabled(activating)
                    .accessibilityIdentifier("hosted-ai-code")
                Button(L10n.text(activating ? "settings.activation.checking" : "settings.activation.activate")) { activate() }
                    .disabled(activating || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("hosted-ai-activate")
                Text(L10n.text("settings.activation.help")).font(.caption).foregroundStyle(.secondary)
            } else if account.status == .active {
                Text(L10n.text("settings.activation.next_step")).font(.caption).foregroundStyle(.secondary)
            }
            Text(L10n.text("settings.activation.privacy")).font(.caption).foregroundStyle(.secondary)
            if let issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }
        .task { if models.hasActivationCode { await models.refreshHostedAccount() } }
        .onDisappear { operation?.cancel(); operation = nil; activating = false; code = ""; changingCode = false }
    }

    private var statusTitle: String {
        let key: String
        switch account.status {
        case .active: key = "settings.activation.active"
        case .unverified: key = "settings.activation.unverified_status"
        case .invalid: key = "settings.activation.invalid_status"
        case .disabled: key = "settings.activation.disabled_status"
        case .noCredits: key = account.account?.quota.available == 0 ? "settings.activation.no_credits_status" : "settings.activation.low_credits_status"
        case .unavailable: key = "settings.activation.unavailable_status"
        }
        return L10n.text(key)
    }
    private var statusSymbol: String {
        switch account.status {
        case .active: "checkmark.circle.fill"
        case .unverified, .unavailable: "questionmark.circle"
        case .invalid, .disabled, .noCredits: "exclamationmark.circle"
        }
    }
    private func refresh() {
        operation?.cancel()
        operation = Task { @MainActor in await models.refreshHostedAccount() }
    }
    private func activate() {
        guard !activating, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        operation?.cancel(); issue = nil; activating = true
        let enteredCode = code
        operation = Task { @MainActor in
            do {
                try await models.activateHostedAI(enteredCode)
                guard !Task.isCancelled else { return }
                code = ""; changingCode = false
            } catch {
                guard !Task.isCancelled else { return }
                issue = HostedAI.problem(error)?.message ?? L10n.text("credentials.inaccessible")
            }
            guard !Task.isCancelled else { return }
            activating = false; operation = nil
        }
    }
}
