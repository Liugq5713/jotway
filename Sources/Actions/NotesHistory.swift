import AppKit
import Foundation
import Observation

@MainActor @Observable
final class NotesHistory {
    private let preferences: UserDefaults
    let models: ModelConfiguration
    private let checkPermission: @MainActor () -> Bool
    let index: NotesIndex
    let reader: AppleNotesReader
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    @ObservationIgnored var onAuthorized: (@MainActor () -> Void)?
    @ObservationIgnored var onPermissionDenied: (@MainActor () -> Void)?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var activationTask: Task<Void, Never>?
    @ObservationIgnored private var refreshPending = false
    @ObservationIgnored private var testTask: Task<Void, Never>?
    private(set) var generation = 0
    private(set) var enabled: Bool
    private(set) var started: Bool
    private(set) var paused: Bool
    private(set) var hasPermission = false
    private(set) var authorizing = false
    private(set) var selectedFolders: Set<String>
    private(set) var allFolders: Bool
    private(set) var hasKey = false
    private(set) var status = NotesIndex.Status()
    private(set) var syncing = false
    private(set) var cancelling = false
    private(set) var clearing = false
    private(set) var syncProgress = NotesSyncProgress()
    private(set) var syncStartedAt: Date?
    private(set) var message: String?
    private(set) var testMessage: String?
    private(set) var testing = false
    private(set) var availableFolders: [AppleNotes.Destination] = []

    init(preferences: UserDefaults, models suppliedModels: ModelConfiguration? = nil, keys: APIKeyStore = .shared, index: NotesIndex? = nil,
         reader: AppleNotesReader = .init(),
         checkPermission: @escaping @MainActor () -> Bool = { AppleNotes.authorizationStatus() == 0 },
         embeddingTransport: @escaping NotesEmbeddingClient.Transport = NotesEmbeddingClient.send) {
        let models = suppliedModels ?? ModelConfiguration(preferences: preferences, keys: keys, embeddingTransport: embeddingTransport)
        self.models = models
        self.checkPermission = checkPermission
        self.preferences = preferences
        self.index = index ?? NotesIndex(profile: models.embeddingProfile)
        self.reader = reader
        enabled = preferences.object(forKey: "notesHistory.enabled") == nil || preferences.bool(forKey: "notesHistory.enabled")
        started = preferences.bool(forKey: "notesHistory.started")
        // The previous Clear Index action explicitly saved started=false. Keep it paused.
        paused = preferences.object(forKey: "notesHistory.paused") == nil
            ? preferences.object(forKey: "notesHistory.started") != nil && !preferences.bool(forKey: "notesHistory.started")
            : preferences.bool(forKey: "notesHistory.paused")
        allFolders = preferences.object(forKey: "notesHistory.allFolders") == nil || preferences.bool(forKey: "notesHistory.allFolders")
        selectedFolders = Set(preferences.stringArray(forKey: "notesHistory.folders") ?? [])
        hasKey = (try? models.loadKey(.notesEmbedding)) != nil
        // Passive preparation never requests permission; all reads reuse an existing grant.
        timer = Task { [weak self] in
            self?.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(600)) } catch { return }
                self?.refresh()
            }
        }
        activationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification).map({ _ in () }) {
                guard !Task.isCancelled else { return }
                self?.refreshAvailability()
            }
        }
        if started { reloadStatus() }
        observeModels()
    }

    private func observeModels() {
        withObservationTracking { _ = models.version(.embedding) } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.invalidate()
                self.hasKey = (try? self.models.loadKey(.notesEmbedding)) != nil
                self.observeModels()
            }
        }
    }

    deinit { timer?.cancel(); activationTask?.cancel(); syncTask?.cancel(); testTask?.cancel() }

    private func invalidate() {
        generation &+= 1
        refreshPending = false
        syncTask?.cancel()
        cancelling = syncing
        testTask?.cancel()
        testing = false
        testMessage = nil
        onChange?()
    }

    func editingKey() { invalidate() }

    func saveEndpoint(_ value: String) -> Bool {
        do {
            try models.setEmbeddingEndpoint(value)
            invalidate()
            message = nil
            return true
        } catch {
            message = Self.safeMessage(error)
            return false
        }
    }

    func saveKey(_ value: String) {
        invalidate()
        do {
            try models.saveKey(value.trimmingCharacters(in: .whitespacesAndNewlines), for: .notesEmbedding)
            hasKey = true
            message = nil
            refresh()
        } catch { message = L10n.text("notes.history.error.credentials") }
    }

    func removeKey() {
        invalidate()
        do { try models.removeKey(for: .notesEmbedding); hasKey = false; message = nil }
        catch { message = L10n.text("notes.history.error.credentials") }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        preferences.set(value, forKey: "notesHistory.enabled")
        invalidate()
        if value { resumeIndexing() }
    }

    private func reloadStatus() {
        let expected = generation
        let scope = allFolders ? nil : selectedFolders
        Task { [weak self, index] in
            guard let state = try? await index.status(folders: scope), self?.generation == expected else { return }
            self?.status = state
            self?.onChange?()
        }
    }

    func setAllFolders(_ value: Bool) {
        allFolders = value
        preferences.set(value, forKey: "notesHistory.allFolders")
        invalidate()
        if started { reloadStatus() }
        refresh()
    }

    func selectFolder(_ id: String, selected: Bool) {
        if selected { selectedFolders.insert(id) } else { selectedFolders.remove(id) }
        preferences.set(selectedFolders.sorted(), forKey: "notesHistory.folders")
        invalidate()
        if started { reloadStatus() }
        refresh()
    }

    func loadFolders() async {
        guard !authorizing else { return }
        authorizing = true
        defer { authorizing = false }
        let expected = generation
        do {
            let folders = try await reader.folders(allowAuthorization: true)
            guard generation == expected else { return }
            availableFolders = folders
            hasPermission = true
            onAuthorized?()
            refresh()
        } catch { report(error) }
    }

    func testConnection() {
        testTask?.cancel()
        let expected = generation
        guard let client = client(requiresEnabled: false) else { return }
        testing = true
        testMessage = nil
        testTask = Task { [weak self] in
            do {
                _ = try await client.embed(["A quiet morning in the garden."], type: .query)
                guard let self, generation == expected else { return }
                testMessage = L10n.text("notes.history.test.success")
            } catch {
                guard let self, generation == expected else { return }
                testMessage = Self.safeMessage(error)
            }
            self?.testing = false
        }
    }

    private func client(requiresEnabled: Bool = true) -> ModelEmbeddingInvocation? {
        guard (!requiresEnabled || enabled), models.embeddingAvailable else { return nil }
        let expected = generation
        return try? models.embedding(validate: { [weak self] in
            try Task.checkCancellation()
            try await MainActor.run {
                guard let self, self.generation == expected, self.models.embeddingAvailable,
                      !requiresEnabled || (self.enabled && self.hasPermission) else { throw NotesHistoryError.stale }
            }
        })
    }

    func snapshot() -> NotesRetriever? {
        guard enabled, started, hasPermission, !clearing, let client = client() else { return nil }
        return NotesRetriever(index: index, client: client,
                              folders: allFolders ? nil : selectedFolders, version: status.version)
    }

    /// A just-confirmed Notes revision has invalidated its old vectors before this refresh.
    /// Freeze the actual database version instead of the UI's asynchronously refreshed status.
    func freshSnapshot() async throws -> NotesRetriever? {
        let expected = generation
        guard let value = snapshot() else { return nil }
        let version = try await index.status().version
        guard generation == expected else { throw NotesHistoryError.stale }
        return NotesRetriever(index: value.index, client: value.client, folders: value.folders, version: version)
    }

    func validate(version: Int, generation: Int) async throws {
        try Task.checkCancellation()
        guard self.generation == generation else { throw NotesHistoryError.stale }
        guard try await index.status().version == version else { throw NotesHistoryError.stale }
        guard self.generation == generation else { throw NotesHistoryError.stale }
    }

    private func updatePermission() -> Bool {
        let granted = checkPermission()
        if hasPermission && !granted { invalidate() }
        hasPermission = granted
        return granted
    }

    func refreshAvailability() {
        let previouslyGranted = hasPermission
        guard updatePermission() else { return }
        if !started || !previouslyGranted { refresh() }
    }

    func resumeIndexing() {
        paused = false
        preferences.set(false, forKey: "notesHistory.paused")
        refresh()
    }

    func refresh() {
        guard updatePermission(), enabled, models.embeddingAvailable, !paused, !clearing, let client = client() else { return }
        guard allFolders || !selectedFolders.isEmpty else { message = L10n.text("notes.history.choose_scope"); return }
        guard !syncing else {
            if cancelling { refreshPending = true }
            return
        }
        if !started {
            started = true
            preferences.set(true, forKey: "notesHistory.started")
            onChange?()
        }
        let expected = generation
        let scope = allFolders ? nil : selectedFolders
        syncing = true
        cancelling = false
        syncProgress = NotesSyncProgress()
        syncStartedAt = .now
        message = nil
        syncTask = Task { [weak self, reader, index] in
            do {
                try await NotesSync.run(reader: reader, index: index, client: client, scope: scope,
                                        allowAuthorization: false) { [weak self] progress in
                    guard let self, generation == expected else { return }
                    if progress.stage == .metadata { onAuthorized?() }
                    syncProgress = progress
                    if progress.indexUpdated, let state = try? await index.status(folders: scope), generation == expected {
                        status = state
                        onChange?()
                    }
                }
            } catch {
                if let self, generation == expected { report(error) }
            }
            guard let self else { return }
            syncing = false
            cancelling = false
            syncStartedAt = nil
            syncTask = nil
            // A cancellation can arrive after a committed batch but before its progress callback.
            if !clearing { reloadStatus() }
            if refreshPending {
                refreshPending = false
                refresh()
            }
        }
    }

    func cancelSync() {
        paused = true
        preferences.set(true, forKey: "notesHistory.paused")
        invalidate()
        message = L10n.text("notes.history.cancelled")
    }

    func clear() {
        guard !clearing else { return }
        paused = true
        preferences.set(true, forKey: "notesHistory.paused")
        started = false
        preferences.set(false, forKey: "notesHistory.started")
        invalidate()
        clearing = true
        let profile = models.embeddingProfile
        Task { [weak self, index] in
            do {
                try await index.clear(rebuildingWith: profile)
                let state = try await index.status()
                self?.status = state
                self?.message = L10n.text("notes.history.cleared")
            } catch { self?.report(error) }
            self?.clearing = false
            self?.onChange?()
        }
    }

    func inspect(_ text: String) async throws -> NotesRetrievalResult {
        guard let retriever = snapshot() else { throw NotesHistoryError.unavailable }
        return try await retriever.search(text)
    }

    private func report(_ error: Error) {
        if error is CancellationError { return }
        message = Self.safeMessage(error)
        if let failure = error as? ActionFailure, [-1743, -1744].contains(failure.osStatus) {
            hasPermission = false
            invalidate()
            onPermissionDenied?()
        }
    }

    static func safeMessage(_ error: Error) -> String {
        if let error = error as? NotesHistoryError { return error.localizedDescription }
        if let error = error as? APIKeyStore.Failure { return error.localizedDescription }
        if let error = error as? ActionFailure, [-1743, -1744].contains(error.osStatus) {
            return L10n.text("notes.history.error.permission")
        }
        if error is CancellationError { return L10n.text("notes.history.cancelled") }
        return L10n.text("notes.history.error.unavailable")
    }
}

/// Runs on the cooperative pool. At most one sync is owned by NotesHistory; every completed
/// batch persists its checkpoint, and restart reuses unchanged notes and content hashes.
enum NotesSync {
    static func run(reader: AppleNotesReader, index: NotesIndex, client: ModelEmbeddingInvocation,
                    scope: Set<String>?, allowAuthorization: Bool,
                    progress: @escaping @MainActor @Sendable (NotesSyncProgress) async -> Void) async throws {
        await progress(.init())
        try await client.validate()
        try await index.validateProfile(client.profile)
        let folders = try await reader.folders(allowAuthorization: allowAuthorization) { count in
            await progress(.init(stage: .folders, folderCount: count))
        }
            .filter { scope?.contains($0.id) ?? true }
        guard !folders.isEmpty else { throw NotesHistoryError.unavailable }
        if let scope, !scope.isSubset(of: Set(folders.map(\.id))) { throw NotesHistoryError.unavailable }
        var sources: [NotesSource] = []
        var seen: [String: Set<String>] = [:]
        // Finish metadata enumeration before any deletion. A failed/partial account read aborts reconciliation.
        for (offset, folder) in folders.enumerated() {
            try await client.validate()
            let alreadyScanned = sources.count
            await progress(.init(stage: .metadata, folder: offset + 1, folderCount: folders.count, scanned: alreadyScanned))
            let values = try await reader.metadata(folderID: folder.id) { scanned, _ in
                await progress(.init(stage: .metadata, folder: offset + 1, folderCount: folders.count,
                                     scanned: alreadyScanned + scanned))
            }
            seen[folder.id] = Set(values.map(\.id))
            sources += values
        }
        var batch: [NotesIndexedSource] = []
        var completed = 0
        var failed = false
        await progress(.init(stage: .checking, total: sources.count))
        for source in sources {
            try Task.checkCancellation()
            try await client.validate()
            if try await !index.isCurrent(source) {
                let entry: NotesIndexedSource
                if source.locked {
                    entry = .init(source: source, state: "locked", bodyHash: "", attachments: 0, chunks: [], vectors: [])
                } else {
                    do {
                        await progress(.init(stage: .reading, completed: completed, total: sources.count))
                        let body = try await reader.body(noteID: source.id)
                        let original = try await index.originalText(noteID: source.id, body: body)
                        let chunks = try NotesChunk.splitOriginal(original)
                        var vectors: [[Float]] = []
                        var localCache: [String: [Float]] = [:]
                        // Bound batches to 20. Reuse by hash without ever collapsing source identity.
                        for start in stride(from: 0, to: chunks.count, by: 20) {
                            try await client.validate()
                            let group = Array(chunks[start..<min(start + 20, chunks.count)])
                            var missing: [NotesChunk] = []
                            for chunk in group where localCache[chunk.hash] == nil {
                                if let cached = try await index.cachedVector(hash: chunk.hash) { localCache[chunk.hash] = cached }
                                else if !missing.contains(where: { $0.hash == chunk.hash }) { missing.append(chunk) }
                            }
                            if !missing.isEmpty {
                                await progress(.init(stage: .embedding, completed: completed, total: sources.count,
                                    fragmentsCompleted: start, fragmentCount: chunks.count))
                                let embedded = try await client.embed(missing.map(\.text), type: .document)
                                for (chunk, vector) in zip(missing, embedded) { localCache[chunk.hash] = vector }
                            }
                            vectors += group.map { localCache[$0.hash]! }
                        }
                        let state = chunks.isEmpty ? (body.text.isEmpty && body.html.isEmpty ? "pending" : "empty") : "ready"
                        entry = .init(source: source, state: state, bodyHash: NotesChunk.hash(body.text),
                                      attachments: body.attachments, chunks: chunks, vectors: vectors)
                    } catch is CancellationError { throw CancellationError() }
                    catch NotesHistoryError.stale { throw NotesHistoryError.stale }
                    catch NotesHistoryError.authentication { throw NotesHistoryError.authentication }
                    catch {
                        try Task.checkCancellation()
                        if let failure = error as? ActionFailure, [-1743, -1744].contains(failure.osStatus) { throw failure }
                        failed = true
                        let state = (error as? NotesHistoryError) == .ambiguous ? "ambiguous"
                            : (error is NotesHistoryError ? "failed" : "unreadable")
                        entry = .init(source: source, state: state,
                                      bodyHash: "", attachments: 0, chunks: [], vectors: [])
                    }
                }
                batch.append(entry)
            }
            completed += 1
            var published = false
            if batch.count >= 4 || completed == sources.count {
                try await client.validate()
                if !batch.isEmpty {
                    await progress(.init(stage: .saving, completed: completed, total: sources.count))
                    try await index.publish(batch, checkpoint: source.id)
                    batch.removeAll(keepingCapacity: true)
                    published = true
                }
            }
            await progress(.init(stage: .checking, completed: completed, total: sources.count, indexUpdated: published))
        }
        try await client.validate()
        await progress(.init(stage: .finishing, completed: completed, total: sources.count))
        try await index.reconcile(seen, successful: !failed)
        await progress(.init(stage: .finishing, completed: completed, total: sources.count, indexUpdated: true))
    }
}
