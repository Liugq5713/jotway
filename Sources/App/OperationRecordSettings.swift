import SwiftUI
import AppKit

/// Capture controls do not expose a content browser; exports are an explicit user action.
struct OperationRecordSettings: View {
    let appState: AppState
    @State private var status: OperationRecorder.Status?
    @State private var busy = false
    @State private var confirmsClear = false
    @State private var confirmsDisable = false
    @State private var messageKey: String?
    @State private var exportedURL: URL?

    var body: some View {
        Section {
            settingRow(L10n.text("operations.scope")) {
                Toggle(L10n.text("operations.enabled"), isOn: Binding(
                    get: { status?.enabled ?? appState.operationRecordingEnabled },
                    set: { enabled in
                        if enabled { run { try await appState.setOperationRecordingEnabled(true) } }
                        else { confirmsDisable = true }
                    }))
                    .disabled(busy)
                    .accessibilityIdentifier("operation-recording-enabled")
            }
            settingRow(L10n.text("operations.retention_help")) {
                Stepper(L10n.text("operations.retention", status?.retentionDays ?? appState.operationRetentionDays),
                    value: Binding(get: { status?.retentionDays ?? appState.operationRetentionDays },
                        set: { days in run { try await appState.setOperationRetentionDays(days) } }),
                    in: 1...3650)
                    .disabled(busy)
                    .accessibilityIdentifier("operation-recording-retention")
            }
            if let status {
                if status.countsAvailable {
                    settingRow(L10n.text("operations.size_help")) {
                        LabeledContent(L10n.text("operations.size"), value:
                            ByteCountFormatter.string(fromByteCount: status.storedBytes, countStyle: .file))
                        Text(L10n.text("operations.counts", status.inputCount, status.attemptCount, status.eventCount))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text(L10n.text("operations.unavailable"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(integrityMessage(status.integrity))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("operation-recording-integrity")
                if status.pendingCount > 0 {
                    Text(L10n.text("operations.pending", status.pendingCount))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button(L10n.text("operations.export"), action: chooseExport)
                    .accessibilityIdentifier("operation-recording-export")
                Spacer(minLength: 8)
                Button(L10n.text("operations.clear"), role: .destructive) { confirmsClear = true }
                    .accessibilityIdentifier("operation-recording-clear")
            }
            .disabled(busy)
            if busy { ProgressView().controlSize(.small) }
            if let messageKey {
                Text(L10n.text(messageKey)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if let exportedURL {
                Button(L10n.text("operations.show_export")) {
                    NSWorkspace.shared.activateFileViewerSelecting([exportedURL])
                }
            }
        } header: { Text(L10n.text("operations.title")) }
        .task {
            while !Task.isCancelled {
                status = await appState.operationRecorder.status()
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
            }
        }
        .confirmationDialog(L10n.text("operations.clear_title"), isPresented: $confirmsClear, titleVisibility: .visible) {
            Button(L10n.text("operations.delete"), role: .destructive) {
                run(success: "operations.cleared") { try await appState.operationRecorder.clear() }
            }
            Button(L10n.text("common.cancel"), role: .cancel) {}
        } message: { Text(L10n.text("operations.delete_help")) }
        .confirmationDialog(L10n.text("operations.disable_title"), isPresented: $confirmsDisable, titleVisibility: .visible) {
            Button(L10n.text("operations.disable"), role: .destructive) {
                run { try await appState.setOperationRecordingEnabled(false) }
            }
            Button(L10n.text("common.cancel"), role: .cancel) {}
        } message: { Text(L10n.text("operations.delete_help")) }
    }

    private func integrityMessage(_ value: OperationRecorder.Integrity) -> String {
        switch value {
        case .complete: L10n.text("operations.integrity.complete")
        case .incomplete: L10n.text("operations.integrity.incomplete")
        case .unknown: L10n.text("operations.integrity.unknown")
        }
    }

    private func run(success: String? = nil, _ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        messageKey = nil
        Task { @MainActor in
            do {
                try await operation()
                messageKey = success
            } catch {
                messageKey = "operations.failed"
            }
            status = await appState.operationRecorder.status()
            busy = false
        }
    }

    private func chooseExport() {
        guard !busy else { return }
        busy = true
        messageKey = nil
        let panel = NSOpenPanel()
        panel.title = L10n.text("operations.export_title")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let directory = panel.url else { busy = false; return }
            let stamp = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
            let destination = directory.appendingPathComponent("Jotway-operations-\(stamp)-\(UUID().uuidString.prefix(8))", isDirectory: true)
            Task { @MainActor in
                do {
                    exportedURL = try await appState.operationRecorder.export(to: destination)
                    messageKey = "operations.exported"
                } catch { messageKey = "operations.failed" }
                status = await appState.operationRecorder.status()
                busy = false
            }
        }
    }
}
