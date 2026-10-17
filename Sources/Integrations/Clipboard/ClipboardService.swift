import AppKit

/// One observation source for recent quotes, source attribution and history restores.
/// Until history is enabled, observing a change never reads the clipboard payload.
@MainActor
final class ClipboardService {
    struct Foreground: Equatable, Sendable {
        let bundle: String?
        let pid: pid_t
    }
    struct QuoteClaim {
        let text: String
        let generation: UUID
        let changeCount: Int
    }
    static let restoreType = NSPasteboard.PasteboardType("com.liuguangqi.jotway.clipboard-restore")
    let pasteboard: NSPasteboard
    let history: ClipboardHistory
    let sourceSettings: BrowserSourceSettings
    private let foreground: @MainActor () -> Foreground
    private let readSource: @Sendable (pid_t) async -> BrowserSource?
    private var lastChangeCount: Int
    private var lastCheckedAt: Date
    private var changedAt: Date?
    private var generation = UUID()
    private var source: BrowserSource?
    private var sourcePID: pid_t?
    private var reading = false
    private var restore: (version: Int, token: String)?
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?

    init(pasteboard: NSPasteboard = .general, sourceSettings: BrowserSourceSettings,
         history: ClipboardHistory? = nil, preferences: UserDefaults = .standard,
         at date: Date = Date(), foreground: @escaping @MainActor () -> Foreground = {
             let app = NSWorkspace.shared.frontmostApplication
             return .init(bundle: app?.bundleIdentifier, pid: app?.processIdentifier ?? 0)
         }, readSource: @escaping @Sendable (pid_t) async -> BrowserSource? = { await ChromeSourceReader().read(processID: $0) }) {
        self.history = history ?? ClipboardHistory(preferences: preferences)
        self.pasteboard = pasteboard
        self.sourceSettings = sourceSettings
        self.foreground = foreground
        self.readSource = readSource
        lastChangeCount = pasteboard.changeCount
        lastCheckedAt = date
        self.history.resetBaseline = { [weak self] in
            guard let self else { return }
            self.lastChangeCount = self.pasteboard.changeCount
            self.changedAt = nil
            self.invalidateSource()
        }
        observeSettings()
    }

    func start() {
        guard timer == nil else { return }
        history.start()
        sourceSettings.refreshPermission()
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.observe() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.activated(processID: app.processIdentifier) }
        }
    }

    isolated deinit {
        timer?.invalidate()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }

    private func observeSettings() {
        withObservationTracking { _ = sourceSettings.enabled; _ = sourceSettings.permissionGranted } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.invalidateSource()
                self?.observeSettings()
            }
        }
    }

    private func invalidateSource() {
        generation = UUID()
        source = nil
        sourcePID = nil
    }

    func activated(processID: pid_t) {
        if let sourcePID, processID != sourcePID, processID != ProcessInfo.processInfo.processIdentifier {
            invalidateSource()
        }
    }

    func observe(at date: Date = Date()) {
        defer { lastCheckedAt = date; history.tick() }
        if let changedAt, !(0...1).contains(date.timeIntervalSince(changedAt)) {
            self.changedAt = nil
            invalidateSource()
        }
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        invalidateSource()
        changedAt = (0...1).contains(date.timeIntervalSince(lastCheckedAt)) ? lastCheckedAt : nil
        if let restore, restore.version == count {
            changedAt = nil
            return
        }
        restore = nil
        if history.canCapture, let payload = capturePayload(expectedCount: count) { history.capture(payload) }
        let app = foreground()
        guard changedAt != nil, sourceSettings.enabled, sourceSettings.permissionGranted,
              app.bundle == ChromeSourceReader.bundleIdentifier, !reading else { return }
        sourcePID = app.pid
        let token = generation
        let read = readSource
        reading = true
        Task { [weak self] in
            let value = await read(app.pid)
            guard let self else { return }
            self.reading = false
            let current = self.foreground()
            guard token == self.generation, self.pasteboard.changeCount == count,
                  self.sourceSettings.enabled, self.sourceSettings.permissionGranted,
                  current.pid == app.pid || current.pid == ProcessInfo.processInfo.processIdentifier else { return }
            self.source = value
        }
    }

    /// Snapshot only the first eligible item, preferring original image representations.
    func capturePayload(expectedCount: Int) -> ClipboardPayload? {
        let excluded = ["org.nspasteboard.TransientType", "org.nspasteboard.ConcealedType", "org.nspasteboard.AutoGeneratedType"]
            .map { NSPasteboard.PasteboardType($0) }
        guard pasteboard.changeCount == expectedCount,
              !excluded.contains(where: { pasteboard.types?.contains($0) == true }) else { return nil }
        for item in pasteboard.pasteboardItems ?? [] {
            guard !item.types.contains(.fileURL), !excluded.contains(where: item.types.contains) else { continue }
            for type in [NSPasteboard.PasteboardType.png, .tiff, .string] where item.types.contains(type) {
                guard let data = item.data(forType: type), pasteboard.changeCount == expectedCount else { return nil }
                let limit = type == .string ? ClipboardHistoryStore.textLimit : ClipboardHistoryStore.imageLimit
                guard data.count <= limit else { history.rejectTooLarge(); return nil }
                if type == .string, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                return ClipboardPayload(type: type.rawValue, data: data)
            }
        }
        return nil
    }

    func claimQuote(at date: Date = Date()) -> QuoteClaim? {
        observe(at: date)
        defer { changedAt = nil }
        guard let changedAt, (0...1).contains(date.timeIntervalSince(changedAt)) else { return nil }
        let count = pasteboard.changeCount
        guard count == lastChangeCount, pasteboard.types?.contains(.string) == true,
              let text = pasteboard.string(forType: .string), pasteboard.changeCount == count,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let quote = text.trimmingCharacters(in: .newlines)
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { "> \($0)" }.joined(separator: "\n") + "\n\n"
        return .init(text: quote, generation: generation, changeCount: count)
    }

    func quote(_ claim: QuoteClaim) -> String {
        guard claim.generation == generation, claim.changeCount == pasteboard.changeCount,
              sourceSettings.enabled, sourceSettings.permissionGranted, let source else { return claim.text }
        return claim.text + L10n.text("browser_source.attribution", source.title) + "\n" + source.url + "\n\n"
    }

    func finishQuote(_ claim: QuoteClaim) -> String {
        let value = quote(claim)
        if claim.generation == generation { invalidateSource() }
        return value
    }

    func isCurrent(_ claim: QuoteClaim) -> Bool { pasteboard.changeCount == claim.changeCount }

    func resolve(_ claim: QuoteClaim, until deadline: ContinuousClock.Instant = .now.advanced(by: .milliseconds(150))) async -> String {
        let clock = ContinuousClock()
        while reading && source == nil && claim.generation == generation && clock.now < deadline && !Task.isCancelled {
            try? await Task.sleep(for: min(.milliseconds(5), clock.now.duration(to: deadline)))
        }
        let value = Task.isCancelled ? claim.text : quote(claim)
        // A claim has one adoption opportunity. A late read must never enrich it later.
        if claim.generation == generation { invalidateSource() }
        return value
    }

    func recordRestore(changeCount: Int, token: String) {
        restore = (changeCount, token)
        changedAt = nil
        invalidateSource()
    }
}
