import SwiftUI

struct NotesHistorySettingsView: View {
    let history: NotesHistory
    @State private var key = ""
    @State private var endpoint = ""
    @FocusState private var keyFocused: Bool
    @State private var query = ""
    @State private var result: NotesRetrievalResult?
    private var hits: [NotesHistoryHit] { result?.hits ?? [] }
    @State private var searchMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var searching = false

    var body: some View {
        Section(L10n.text("notes.history.title")) {
            Toggle(L10n.text("notes.history.enable"), isOn: Binding(get: { history.enabled }, set: { history.setEnabled($0) }))
            Text(L10n.text("notes.history.privacy")).font(.caption).foregroundStyle(.secondary)
            if !history.hasPermission {
                Button(L10n.text("notes.history.authorize")) { Task { await history.loadFolders() } }
                    .disabled(history.authorizing)
                if history.authorizing { ProgressView().controlSize(.small) }
            }
            if history.paused { Text(L10n.text("notes.history.paused")).font(.caption) }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.text("notes.history.service")).font(.headline)
                    Spacer()
                    ServiceKeyStatus(hasKey: history.hasKey)
                }
                TextField(L10n.text("notes.history.endpoint"), text: $endpoint)
                    .textFieldStyle(.roundedBorder)
                Text(L10n.text("notes.history.endpoint_help")).font(.caption).foregroundStyle(.secondary)
                Button(L10n.text("notes.history.save_endpoint")) {
                    if history.saveEndpoint(endpoint) { endpoint = history.models.embeddingProfile.endpoint }
                }
                .disabled(endpoint.trimmingCharacters(in: .whitespacesAndNewlines) == history.models.embeddingProfile.endpoint)
                ServiceKeyField(accessibilityTitle: L10n.text("notes.history.service"),
                    keyURL: URL(string: "https://bailian.console.aliyun.com/")!, hasKey: history.hasKey,
                    text: $key, isFocused: $keyFocused, save: saveKey)
                HStack {
                    Button(L10n.text("settings.key.remove")) { history.removeKey(); key = "" }
                        .disabled(!history.hasKey)
                    Button(L10n.text("notes.history.test")) { history.testConnection() }
                        .disabled(!history.models.embeddingAvailable || history.testing || !key.isEmpty
                            || endpoint.trimmingCharacters(in: .whitespacesAndNewlines) != history.models.embeddingProfile.endpoint)
                    if history.testing { ProgressView().controlSize(.small) }
                }.buttonStyle(ServiceSettingsButtonStyle())
                if let message = history.testMessage { Text(message).font(.caption) }
                DisclosureGroup(L10n.text("notes.history.details")) {
                    Text(history.models.embeddingProfile.model).textSelection(.enabled)
                    Text(history.models.embeddingProfile.endpoint).font(.caption).textSelection(.enabled)
                    Text(L10n.text("notes.history.key_storage")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle(L10n.text("notes.history.all_folders"), isOn: Binding(get: { history.allFolders }, set: { history.setAllFolders($0) }))
            if !history.allFolders {
                Button(L10n.text("notes.history.load_folders")) { Task { await history.loadFolders() } }
                Text(L10n.text("notes.history.scope_count", history.selectedFolders.count)).font(.caption)
                ForEach(history.availableFolders) { folder in
                    Toggle(folder.name, isOn: Binding(get: { history.selectedFolders.contains(folder.id) },
                        set: { history.selectFolder(folder.id, selected: $0) }))
                }
                ForEach(history.selectedFolders.subtracting(Set(history.availableFolders.map(\.id))).sorted(), id: \.self) { id in
                    HStack {
                        Text(L10n.text("notes.history.saved_folder", id)).font(.caption)
                        Button(L10n.text("notes.history.remove_scope")) { history.selectFolder(id, selected: false) }
                    }
                }
            }
            HStack {
                Button(L10n.text(history.paused ? "notes.history.resume" : "notes.history.refresh")) { history.resumeIndexing() }
                    .disabled(!history.enabled || !history.models.embeddingAvailable || !history.hasPermission || history.syncing || history.clearing)
                if history.syncing {
                    Button(L10n.text("notes.history.cancel")) { history.cancelSync() }
                        .disabled(history.cancelling)
                }
                Button(L10n.text("notes.history.clear"), role: .destructive) { history.clear() }
                    .disabled(history.clearing)
            }
            if history.syncing {
                VStack(alignment: .leading, spacing: 8) {
                    if history.cancelling {
                        ProgressView(L10n.text("notes.history.cancelling"))
                    } else {
                        Text(history.syncProgress.description).font(.caption)
                        if let total = history.syncProgress.total, total > 0 {
                            ProgressView(value: Double(history.syncProgress.completed), total: Double(total))
                            Text(L10n.text("notes.history.progress", history.syncProgress.completed, total)).font(.caption)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                    if let start = history.syncStartedAt {
                        TimelineView(.periodic(from: start, by: 1)) { context in
                            Text(L10n.text("notes.history.elapsed", max(0, Int(context.date.timeIntervalSince(start)))))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text(L10n.text("notes.history.searchable", history.status.searchable)).font(.caption)
            ForEach(history.status.states.keys.filter { $0 != "ready" }.sorted(), id: \.self) { state in
                Text(L10n.text("notes.history.state.\(state)") + ": \(history.status.states[state] ?? 0)").font(.caption)
            }
            Text(L10n.text("notes.history.attachments", history.status.attachments)).font(.caption)
            if let date = history.status.lastSuccess {
                Text(L10n.text("notes.history.last_sync", date.formatted())).font(.caption)
            }
            if let message = history.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        Section(L10n.text("notes.history.search")) {
            TextField(L10n.text("notes.history.query"), text: $query).onSubmit(search)
            Button(L10n.text("notes.history.search_button"), action: search)
                .disabled(!history.enabled || !history.models.embeddingAvailable || !history.started || searching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if searching { ProgressView().controlSize(.small) }
            if let message = searchMessage { Text(message).font(.caption) }
            if let result {
                Text(L10n.text("notes.history.candidates", result.counts.candidateCount)).font(.caption)
                Text(L10n.text("notes.history.coverage", result.coverage.searchable,
                               result.coverage.pending, result.coverage.failed)).font(.caption)
                if result.coverage.isIncomplete {
                    Text(L10n.text("notes.history.partial_results")).font(.caption).foregroundStyle(.secondary)
                }
                Text(L10n.text("notes.history.candidate_help")).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(hits) { hit in
                VStack(alignment: .leading, spacing: 6) {
                    Text(hit.title).font(.headline)
                    Text(L10n.text("notes.history.modified", hit.modified.formatted())).font(.caption).foregroundStyle(.secondary)
                    Text(hit.text).textSelection(.enabled)
                    Button(L10n.text("notes.history.open")) {
                        Task {
                            do { try await history.reader.open(noteID: hit.noteID) }
                            catch { searchMessage = NotesHistory.safeMessage(error) }
                        }
                    }
                }
            }
        }
        .onAppear {
            endpoint = history.models.embeddingProfile.endpoint
            history.refreshAvailability()
        }
        .onChange(of: key) { if !key.isEmpty { history.editingKey() } }
        .onChange(of: query) { invalidateSearch() }
        .onChange(of: history.generation) { invalidateSearch() }
        .onChange(of: history.status.version) { invalidateSearch() }
        .onDisappear { key = ""; invalidateSearch() }
    }

    private func saveKey() {
        let value = key
        key = ""
        keyFocused = false
        history.saveKey(value)
    }

    private func invalidateSearch() {
        searchTask?.cancel()
        result = nil
        searching = false
        searchMessage = nil
    }

    private func search() {
        invalidateSearch()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        searching = true
        searchTask = Task {
            do {
                let result = try await history.inspect(text)
                try Task.checkCancellation()
                self.result = result
                searchMessage = result.hits.isEmpty ? L10n.text("notes.history.no_hits") : nil
            } catch {
                if Task.isCancelled { return }
                searchMessage = NotesHistory.safeMessage(error)
            }
            searching = false
        }
    }
}
