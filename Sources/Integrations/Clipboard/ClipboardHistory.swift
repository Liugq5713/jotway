import AppKit
import Observation

/// Local history lifecycle. Payloads stay in the store/helper and never enter action input.
@MainActor @Observable
final class ClipboardHistory {
    private(set) var enabled: Bool
    private(set) var entries: [ClipboardEntry] = []
    private(set) var selectedID: String?
    private(set) var errorKey: String?
    private(set) var loading = false
    private(set) var generation = UUID()
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    @ObservationIgnored var resetBaseline: (@MainActor () -> Void)?
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let store: ClipboardHistoryStore
    @ObservationIgnored private let recognize: @Sendable (Data) async throws -> String
    @ObservationIgnored private let idleSeconds: @MainActor () -> Double
    @ObservationIgnored private var query: String?
    @ObservationIgnored private var selectsFirst = false
    @ObservationIgnored private var projectionID = UUID()
    @ObservationIgnored private var prepared = false
    @ObservationIgnored private var paused = false
    @ObservationIgnored private var hasPendingOCR = false
    @ObservationIgnored private var lifecycle: Task<Void, Never>?
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var ocrTask: Task<Void, Never>?
    @ObservationIgnored private var ocrID: String?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    init(preferences: UserDefaults, store: ClipboardHistoryStore? = nil,
         idleSeconds: @escaping @MainActor () -> Double = {
             CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
         }, recognize: @escaping @Sendable (Data) async throws -> String = {
             try await ClipboardTextRecognizer().recognize($0)
         }) {
        self.preferences = preferences
        self.store = store ?? ClipboardHistoryStore(url: StorageLocation.appSupport.appendingPathComponent("Clipboard/clipboard.sqlite"))
        self.idleSeconds = idleSeconds
        self.recognize = recognize
        enabled = preferences.object(forKey: "clipboard.history.enabled") == nil
            ? true : preferences.bool(forKey: "clipboard.history.enabled")
    }

    isolated deinit { captureTask?.cancel(); ocrTask?.cancel(); reloadTask?.cancel() }

    func start() { if enabled { prepare() } }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        let token = generation, previous = lifecycle, store = store
        lifecycle = Task { [weak self] in
            await previous?.value
            do { try await store.begin(token) }
            catch { self?.failStorage(token) }
            guard let self, self.generation == token else { return }
            self.reload()
        }
    }

    func setEnabled(_ value: Bool) {
        guard enabled != value || paused else { return }
        enabled = value
        preferences.set(value, forKey: "clipboard.history.enabled")
        resetBaseline?()
        renew()
        prepared = false
        prepare()
        onChange?()
    }

    private func renew() {
        generation = UUID()
        captureTask?.cancel(); captureTask = nil
        // Keep the slot until the child has exited, even if cancellation is slow.
        ocrTask?.cancel()
        reloadTask?.cancel(); reloadTask = nil
        projectionID = UUID()
        paused = false
        errorKey = nil
    }

    func clear() {
        renew()
        entries = []; selectedID = nil
        resetBaseline?()
        let token = generation, previous = lifecycle, store = store
        prepared = true
        lifecycle = Task { [weak self] in
            await previous?.value
            do { try await store.clear(generation: token) }
            catch { self?.failStorage(token) }
            guard let self, self.generation == token else { return }
            self.reload()
        }
        onChange?()
    }

    func setQuery(_ value: String?) {
        guard query != value else { return }
        query = value
        selectsFirst = value != nil
        projectionID = UUID()
        selectedID = nil
        entries = []
        reloadTask?.cancel(); reloadTask = nil
        loading = value != nil
        if value != nil { prepare(); reload(selectFirst: true) }
    }

    func select(_ id: String) {
        guard entries.contains(where: { $0.id == id }) else { return }
        selectedID = id
        onChange?()
    }

    func move(forward: Bool) {
        guard !entries.isEmpty else { return }
        let index = entries.firstIndex(where: { $0.id == selectedID }) ?? (forward ? -1 : entries.count)
        selectedID = entries[min(entries.count - 1, max(0, index + (forward ? 1 : -1)))].id
        onChange?()
    }

    var canCapture: Bool { enabled && !paused && captureTask == nil }
    func rejectTooLarge() { errorKey = "clipboard.too_large"; onChange?() }

    func capture(_ payload: ClipboardPayload) {
        guard enabled, !paused, captureTask == nil else { return }
        prepare()
        let token = generation, barrier = lifecycle, store = store
        captureTask = Task { [weak self] in
            await barrier?.value
            guard let self, self.generation == token, !Task.isCancelled else { return }
            do { try await store.capture(payload, generation: token) }
            catch let failure as ClipboardFailure where failure == .tooLarge || failure == .invalidImage {
                self.errorKey = failure.key
            } catch { self.failStorage(token) }
            guard self.generation == token else { return }
            self.captureTask = nil
            self.reload()
        }
    }

    /// Called by the shared observer. No payload reads or OCR starts while collection is off.
    func tick() {
        guard enabled, !paused, hasPendingOCR, ocrTask == nil, reloadTask == nil, idleSeconds() >= 2 else { return }
        reload()
    }

    private func reload(selectFirst: Bool = false) {
        guard prepared else { return }
        let token = generation, projection = projectionID, barrier = lifecycle, store = store
        // Lifecycle calls this only after finishing its own database operation.
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            await barrier?.value
            guard !Task.isCancelled, let self, self.generation == token else { return }
            do {
                let rows = try await store.entries()
                guard self.generation == token, !Task.isCancelled else { return }
                if let query = self.query, self.projectionID == projection {
                    self.entries = rows.filter { $0.matches(query) }
                    if let selected = self.selectedID, !self.entries.contains(where: { $0.id == selected }) {
                        self.selectedID = nil
                    } else if self.selectsFirst, self.selectedID == nil { self.selectedID = self.entries.first?.id }
                    self.selectsFirst = false
                    self.loading = false
                }
                if let id = self.ocrID, !rows.contains(where: { $0.id == id }) { self.ocrTask?.cancel() }
                self.hasPendingOCR = rows.contains { $0.isImage && $0.ocrState == "pending" }
                self.scheduleOCR(rows, token: token)
            } catch { self.failStorage(token) }
            guard self.generation == token else { return }
            self.reloadTask = nil
            self.onChange?()
        }
    }

    private func scheduleOCR(_ rows: [ClipboardEntry], token: UUID) {
        guard enabled, !paused, ocrTask == nil, idleSeconds() >= 2,
              let entry = rows.first(where: { $0.isImage && $0.ocrState == "pending" }) else { return }
        ocrID = entry.id
        let store = store, recognize = recognize
        ocrTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.ocrTask = nil; self.ocrID = nil
                self.reload()
            }
            do {
                let payload = try await store.payload(for: entry, generation: token)
                try Task.checkCancellation()
                try await store.updateOCR(entry, state: "processing", generation: token)
                self.reload()
                let text = try await recognize(payload.data)
                try Task.checkCancellation()
                guard self.generation == token, self.enabled else { return }
                try await store.updateOCR(entry, state: text.isEmpty ? "empty" : "ready", text: text, generation: token)
            } catch is CancellationError {
                // Interrupted jobs are made pending by begin() on the next enable/start.
            } catch ClipboardFailure.stale {
                // A corrupt retained payload fails once; an evicted row cannot be recreated.
                guard self.generation == token, self.enabled else { return }
                do { try await store.updateOCR(entry, state: "failed", generation: token) }
                catch ClipboardFailure.stale {}
                catch { self.failStorage(token) }
            } catch {
                guard self.generation == token, self.enabled else { return }
                do { try await store.updateOCR(entry, state: "failed", generation: token) }
                catch { self.failStorage(token) }
            }
        }
    }

    func restore(_ entry: ClipboardEntry, through service: ClipboardService,
                 isCurrent: @escaping @MainActor () -> Bool) async throws {
        let token = generation, barrier = lifecycle
        await barrier?.value
        let payload = try await store.payload(for: entry, generation: token)
        guard generation == token, isCurrent(), entries.contains(where: { $0.id == entry.id && $0.digest == entry.digest }) else {
            throw ClipboardFailure.stale
        }
        let marker = UUID().uuidString, item = NSPasteboardItem()
        guard item.setData(payload.data, forType: .init(payload.type)),
              item.setString(marker, forType: ClipboardService.restoreType) else { throw ClipboardFailure.copyFailed }
        service.pasteboard.clearContents()
        guard service.pasteboard.writeObjects([item]) else { throw ClipboardFailure.copyFailed }
        service.recordRestore(changeCount: service.pasteboard.changeCount, token: marker)
    }

    private func failStorage(_ token: UUID) {
        guard generation == token else { return }
        paused = true; loading = false
        errorKey = ClipboardFailure.unavailable.key
        ocrTask?.cancel()
        onChange?()
    }
}
