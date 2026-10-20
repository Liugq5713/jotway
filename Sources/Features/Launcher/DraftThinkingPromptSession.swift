import Foundation
import Observation

@MainActor @Observable
final class DraftThinkingPromptSession {
    enum Display: Equatable {
        case closed, loading, ready(DraftThinkingPromptGenerator.Response), empty, failed(RuntimeLog.Code), hostedFailure(HostedAI.Problem)
        var isOpen: Bool { self != .closed }
    }
    struct Context: Equatable {
        let draftID: UUID
        let revision: Int
        let text: String
        let panelSessionID: UUID
        let modeGeneration: UUID
        let fastVersion: String
        let prompt: InstantInsightPrompt.Snapshot?
        let manualBlockReason: String?
        let automaticBlocked: Bool
        var identity: Identity { .init(draftID: draftID, revision: revision) }
    }
    struct Identity: Equatable { let draftID: UUID; let revision: Int }
    private struct Request {
        let id: UUID
        let context: Context
        let automatic: Bool
    }
    private(set) var display: Display = .closed
    private(set) var blockReason: String?
    @ObservationIgnored private var context: Context?
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var suppressed: Identity?
    @ObservationIgnored private var consumed: Identity?
    @ObservationIgnored private var candidate: Identity?
    @ObservationIgnored private var settled = false
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var request: Request?
    @ObservationIgnored private let factory: @MainActor () throws -> ModelTextInvocation
    @ObservationIgnored private let currentVersion: @MainActor () -> String
    @ObservationIgnored private let currentPromptVersion: @MainActor () -> String?
    @ObservationIgnored private let uiLanguage: @MainActor () -> DraftThinkingPromptGenerator.UILanguage
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let timeout: Duration

    init(factory: @escaping @MainActor () throws -> ModelTextInvocation,
         currentVersion: @escaping @MainActor () -> String,
         currentPromptVersion: @escaping @MainActor () -> String? = { InstantInsightPrompt().snapshot?.version },
         uiLanguage: @escaping @MainActor () -> DraftThinkingPromptGenerator.UILanguage = {
             .init(rawValue: AppLocalization.shared.languageCode) ?? .english
         },
         debounce: Duration = .seconds(1), timeout: Duration = .seconds(20)) {
        self.factory = factory
        self.currentVersion = currentVersion
        self.currentPromptVersion = currentPromptVersion
        self.uiLanguage = uiLanguage
        self.debounce = debounce
        self.timeout = timeout
    }

    isolated deinit { timer?.cancel(); task?.cancel() }

    /// Context refreshes are not edits. Only changed text/scope or newly available work arms a timer.
    func update(_ next: Context, automaticEnabled: Bool) {
        let previous = context
        let scopeChanged = previous.map {
            $0.draftID != next.draftID || $0.panelSessionID != next.panelSessionID
                || $0.modeGeneration != next.modeGeneration || $0.fastVersion != next.fastVersion
        } ?? true
        let enableChanged = enabled != automaticEnabled
        let promptChanged = previous.map { $0.prompt?.version != next.prompt?.version } ?? false
        context = next
        blockReason = next.manualBlockReason
        enabled = automaticEnabled
        if scopeChanged { invalidate(); consumed = nil }
        if previous?.identity != next.identity { suppressed = nil }
        if enableChanged {
            cancelCandidate()
            consumed = nil
            if enabled { suppressed = nil }
            else if request?.automatic == true { invalidate() }
        }
        if promptChanged {
            // Saving a new preference invalidates both sources without rearming this text.
            // Do not clear the user's close suppression or fold the prompt into draft identity.
            invalidate()
            consumed = next.identity
            return
        }
        // Protection cancels auto work; user-visible manual responses survive ordinary typing/IME.
        if next.manualBlockReason != nil || next.automaticBlocked {
            cancelCandidate()
            if request?.automatic == true { invalidate(); consumed = nil }
            return
        }
        scheduleIfNeeded()
    }

    func invalidate() {
        if request != nil { consumed = nil }
        cancelCandidate()
        request = nil
        task?.cancel(); task = nil
        display = .closed
    }

    func closeByUser() {
        suppressed = context?.identity
        invalidate()
    }

    func requestManually() {
        guard let context, context.manualBlockReason == nil, request == nil else { return }
        suppressed = nil
        cancelCandidate()
        start(context, automatic: false)
    }

    private func cancelCandidate() {
        timer?.cancel(); timer = nil
        candidate = nil; settled = false
    }

    private func scheduleIfNeeded() {
        guard enabled, let context, context.manualBlockReason == nil, !context.automaticBlocked,
              suppressed != context.identity, consumed != context.identity else { return }
        guard candidate != context.identity else {
            if settled, request == nil { start(context, automatic: true) }
            return
        }
        cancelCandidate()
        let identity = context.identity
        candidate = identity
        timer = Task { [weak self, debounce] in
            do { try await Task.sleep(for: debounce) } catch { return }
            guard let self, !Task.isCancelled, self.candidate == identity else { return }
            self.timer = nil; self.settled = true
            self.scheduleIfNeeded()
        }
    }

    static func failureDisplay(_ error: Error) -> Display {
        if let problem = HostedAI.problem(error) { return .hostedFailure(problem) }
        return .failed(RuntimeLog.code(error))
    }

    private func start(_ snapshot: Context, automatic: Bool) {
        guard request == nil, let prompt = snapshot.prompt else { return }
        cancelCandidate()
        consumed = snapshot.identity
        let operation = Request(id: UUID(), context: snapshot, automatic: automatic)
        request = operation
        // Automatic checks stay invisible until a useful response is available.
        display = automatic ? .closed : .loading
        // Freeze immediately; queueing within the invocation is inside this logical deadline.
        let deadline = ContinuousClock.now.advanced(by: timeout)
        let language = uiLanguage()
        let invocation: ModelTextInvocation
        do {
            _ = try DraftThinkingPromptGenerator.request(for: snapshot.text, prompt: prompt, uiLanguage: language)
            invocation = try factory()
        } catch {
            request = nil
            display = automatic ? .closed : Self.failureDisplay(error)
            return
        }
        task = Task { [weak self] in
            let result: Display
            do {
                let value = try await DraftThinkingPromptGenerator(invocation: invocation)
                    .generate(snapshot.text, prompt: prompt, uiLanguage: language, until: deadline, requestID: operation.id)
                result = value.map(Display.ready) ?? .empty
            } catch { result = Self.failureDisplay(error) }
            guard !Task.isCancelled, let self, self.request?.id == operation.id else { return }
            self.task = nil; self.request = nil
            guard self.currentPromptVersion() == prompt.version else {
                self.invalidate()
                self.consumed = self.context?.identity
                return
            }
            guard let current = self.context, current.draftID == snapshot.draftID,
                  current.panelSessionID == snapshot.panelSessionID,
                  current.modeGeneration == snapshot.modeGeneration,
                  self.currentVersion() == snapshot.fastVersion else { self.invalidate(); return }
            if !automatic || (current.identity == snapshot.identity && !current.automaticBlocked
                              && current.manualBlockReason == nil && self.enabled) {
                if automatic {
                    if case .ready = result { self.display = result }
                    else { self.display = .closed }
                } else {
                    self.display = result
                }
            } else {
                // An obsolete automatic outcome never becomes the new draft's result/error.
                self.display = .closed
            }
            self.scheduleIfNeeded()
        }
    }
}
