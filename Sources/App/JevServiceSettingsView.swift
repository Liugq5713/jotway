import SwiftUI

struct JevServiceSettingsView: View {
    let settings: JevSettings
    @State private var apiKey = ""
    @State private var showsDetails = false
    @FocusState private var isEditingKey: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            keyInput
            if let issue = settings.keyIssue {
                Label(issue, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            actions
            if let message = settings.connectionMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            serviceDetails
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { settings.refreshKeyStatus() }
        .onChange(of: isEditingKey) { if isEditingKey { settings.beginEditingAPIKey() } }
        .onDisappear {
            apiKey = ""
            settings.invalidateConnectionTest()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            Text(L10n.text("jev.service"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            ServiceKeyStatus(hasKey: settings.hasAPIKey)
        }
    }

    private var keyInput: some View {
        ServiceKeyField(accessibilityTitle: "Jev API Key", keyURL: URL(string: "https://console.typesafe.ai/")!,
                        hasKey: settings.hasAPIKey, text: Binding(
                            get: { apiKey },
                            set: { apiKey = $0; settings.beginEditingAPIKey() }
                        ), isFocused: $isEditingKey, save: saveKey)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                isEditingKey = false
                settings.testConnection()
            } label: {
                HStack(spacing: 7) {
                    if settings.isTesting {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "bolt.horizontal")
                    }
                    Text(L10n.text(settings.isTesting ? "settings.connection.testing" : "settings.connection.test"))
                }
            }
            .buttonStyle(ServiceSettingsButtonStyle())
            .disabled(settings.isTesting || !settings.hasAPIKey || !apiKey.isEmpty)

            Spacer(minLength: 0)
            if settings.hasAPIKey {
                Button(L10n.text("settings.key.remove"), role: .destructive) {
                    if settings.removeAPIKey() {
                        apiKey = ""
                        isEditingKey = false
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
            }
        }
    }

    private var serviceDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("jev.service.help"))
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup(isExpanded: $showsDetails) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("jev.key.storage_help"))
                    Text(L10n.text("jev.connection.help"))
                    Text(L10n.text("jev.service.confirmation_help"))
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            } label: {
                Text(L10n.text("settings.service.details"))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func saveKey() {
        if settings.saveAPIKey(apiKey) {
            apiKey = ""
            isEditingKey = false
        }
    }
}
