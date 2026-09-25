import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RuntimeLogSettings: View {
    private enum Message {
        case key(String)
        case exported(incomplete: Bool)

        var text: String {
            switch self {
            case .key(let key): L10n.text(key)
            case .exported(let incomplete): L10n.text(incomplete ? "logs.exported_incomplete" : "logs.exported")
            }
        }
    }

    @State private var status = RuntimeLog.Status()
    @State private var message: Message?
    @State private var busy = false
    @State private var confirmsClear = false
    @State private var exportTask: Task<Void, Never>?
    @State private var isExpanded = false

    var body: some View {
        Section {
            DisclosureGroup(L10n.text("logs.title"), isExpanded: $isExpanded) {
                settingRow(L10n.text("logs.retention_help")) {
                    LabeledContent(L10n.text("logs.space_used"), value: ByteCountFormatter.string(fromByteCount: Int64(status.bytes), countStyle: .file))
                }
                if status.unavailable {
                    Text(L10n.text("logs.unavailable"))
                        .font(.caption).foregroundStyle(.secondary)
                } else if status.files == 0 {
                    Text(L10n.text("logs.empty")).font(.caption).foregroundStyle(.secondary)
                }
                if status.incomplete {
                    Text(L10n.text("logs.incomplete", status.dropped))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button(L10n.text("logs.open_folder")) {
                        busy = true
                        Task { @MainActor in
                            await refresh()
                            if status.unavailable { message = .key("logs.open_unavailable") }
                            else { message = NSWorkspace.shared.open(RuntimeLog.shared.directory)
                                ? (status.files == 0 ? .key("logs.empty_sentence") : nil) : .key("logs.open_failed") }
                            busy = false
                        }
                    }.disabled(busy)
                    Button(L10n.text("logs.export"), action: chooseExport).disabled(busy || status.files == 0)
                    Spacer(minLength: 8)
                    Button(L10n.text("logs.clear"), role: .destructive) { confirmsClear = true }.disabled(busy || status.files == 0)
                }
                if exportTask != nil {
                    HStack {
                        ProgressView().controlSize(.small)
                        Button(L10n.text("logs.cancel_export")) { exportTask?.cancel() }
                    }
                }
                if let message { Text(message.text).font(.caption).foregroundStyle(.secondary) }
            }
        } header: {
            Text(L10n.text("logs.diagnostics"))
        } footer: {
            Text(L10n.text("logs.diagnostics_help"))
        }
        .task {
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
            }
        }
        .confirmationDialog(L10n.text("logs.clear_confirmation"), isPresented: $confirmsClear, titleVisibility: .visible) {
            Button(L10n.text("logs.clear_action"), role: .destructive) {
                busy = true
                Task { @MainActor in
                    do { try await RuntimeLog.shared.clear(); message = .key("logs.cleared") }
                    catch { message = .key("logs.clear_failed") }
                    await refresh()
                    busy = false
                }
            }
            Button(L10n.text("common.cancel"), role: .cancel) {}
        } message: { Text(L10n.text("logs.clear_help")) }
    }

    @MainActor private func refresh() async { status = await RuntimeLog.shared.status() }

    private func chooseExport() {
        busy = true
        message = nil
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = L10n.text("logs.filename",
            Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                busy = false
                message = .key("logs.export_location_cancelled")
                return
            }
            exportTask = Task { @MainActor in
                do {
                    let incomplete = try await RuntimeLog.shared.export(to: url)
                    message = .exported(incomplete: incomplete)
                } catch is CancellationError { message = .key("logs.export_cancelled") }
                catch RuntimeLog.Failure.empty { message = .key("logs.nothing_to_export") }
                catch { message = .key("logs.export_failed") }
                await refresh()
                busy = false
                exportTask = nil
            }
        }
    }
}
