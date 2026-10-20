import Foundation
import Observation

enum LauncherEvent {
    case toggleMode
    case inputChanged(String)
    case panelPrepared(quote: String?)
    case panelPresented
    case selectedTextPermissionNotice(String)
    case selectedTextPermissionRecovered
    case panelDismissed
    case panelVisibilityChanged(Bool)
    case compositionChanged(Bool)
    case confirm(IntentRecognition.ConfirmationSource)
    case cycleTarget(forward: Bool)
    case selectTarget(String, trigger: OperationSelectionTrigger = .button)
    case toggleTargetMenu
    case useAutomatic(trigger: OperationSelectionTrigger = .button)
    case candidateMenuChanged(Bool)
    case selectTemplate(InputTemplate)
    case templateFillingChanged(Bool)
    case clipboardSelect(String)
    case clipboardMove(forward: Bool)
    case codexRecentTaskOpened
    case toggleReview(NotesReviewPeriod)
    case closeReview
    case requestThinkingPrompt
    case closeThinkingPrompt
    case thinkingSettingsOpened
    case automaticThinkingPreferenceChanged
    case thinkingPreferencesChanged
    case toggleRecentDocuments
    case navigateRecentDocument(older: Bool)
    case recentDocumentDateChanged
    case selectRecentDocument(String)
    case retryRecentDocument
    case closeRecentDocument
    case dismissTemplateMenu
    case readingGettingStartedChanged(Bool)
    case externalFocusChanged
    case refreshConfiguration
    case refreshTemplates
    case externalAvailabilityChanged
    case preserveDraft
    case captureBeforeTermination
    case cancel
    case preloadApplications
    case cancelApplicationPreload
    case restoreFailedSubmission
    case actionSetupFinished(UUID, ActionSetupResult)
}

enum LauncherEffect {
    case changeMode(LauncherMode)
    case replaceEditor(String, LauncherSession.ReplacementReason)
    case insertTemplate(TemplateExpansion, expected: ActionInput.Identity)
    case endTemplateEditing
    case prepareSubmission
    case cancelSubmission
    case hidePanel(submitted: Bool, presentationPolicy: PresentationPolicy)
    case hideForApplicationLaunch
    case showPanel
    case showActionSetup(ActionSetupRequest)
    case closeActionSetup(UUID)
    case restoreEditorAfterSetup
    case restoreEditorAfterRecentDocumentRemoval
    case showCompletionNotice(String, destination: ActionCompletionDestination?)
    case openApplication(URL, dispatched: @MainActor () -> Void, completion: @MainActor (Result<Void, Error>) -> Void)
}

/// 启动器会话：拥有草稿、意图、路由和提交任务，不持有窗口或原生编辑器。
@MainActor
final class LauncherSession {
    enum ReplacementReason { case restoreDraft, newDraft }

    let state = LauncherViewState()
    let catalog: ApplicationCatalog
    let thinkingPrompt: DraftThinkingPromptSession
    private let automaticThinkingEnabled: () -> Bool
    private let thinkingFastVersion: () -> String
    private let thinkingInstructions: () -> InstantInsightPrompt.Snapshot?
    private let aiCapabilityReady: (ModelConfiguration.Capability) -> Bool
    private var thinkingAIReady = false
    private(set) var draft = RecordDraft()
    private(set) var hasPreparedDraft = false
    private(set) var activeSubmissionCount = 0

    /// 窗口 adapter 解释全部原生副作用；replaceEditor 的 Bool 表示原生编辑器是否接受替换。
    var handleEffect: (LauncherEffect) -> Bool = { effect in
        if case .openApplication(_, _, let completion) = effect {
            completion(.failure(NSError(domain: "Jotway.Launcher", code: 1,
                userInfo: [NSLocalizedDescriptionKey: L10n.text("launcher.open_unavailable")])))
        }
        return true
    }

    private let clipboard: ClipboardService?
    private let review: NotesReview?
    private var clipboardConfirmation: UUID? {
        didSet { updateSubmissionTransition() }
    }
    private let registry: ActionRegistry
    private let readTemplates: () -> [InputTemplate]
    private let recentSavedDocuments: RecentSavedDocuments
    private let readSavedDocument: @MainActor @Sendable (String) async throws -> String
    private var recentDocumentTask: Task<Void, Never>?
    private var recentDocumentRequestID: UUID?
    private let recentDocumentNow: () -> Date
    private let recentDocumentTimeZone: () -> TimeZone
    private var recentDocumentDayTask: Task<Void, Never>?
    private(set) var nextRecentDocumentRefresh: Date?
    private let recorder: OperationRecorder
    private let applicationUsage: () -> [String: ApplicationUsage]
    private let recordApplicationOpen: (URL) -> Bool
    private let routeResolver = RouteResolver()
    private var revision = 0
    private var savedRevision = 0
    private var panelSession = 0
    private var acceptsIntentSuggestions = false
    private var isReplacingEditor = false
    private var isSubmitting = false {
        didSet { updateSubmissionTransition() }
    }
    private struct ApplicationEvaluationCache {
        let draftID: UUID
        let revision: Int
        let catalogRevision: Int
        let evaluation: ApplicationMatcher.Evaluation
        let applications: [IntentRecognition.Application]
        let ranks: [String: IntentRecognition.ApplicationRank]
    }
    private var applicationEvaluationCache: ApplicationEvaluationCache?
    private var applicationOpenID: UUID?
    private var applicationNotice: String?
    private var submissions: [UUID: Task<Void, Never>] = [:]
    private var explicitTarget: DraftTargetSelection?
    private var explicitTargetDraftID: UUID?
    private var routingInteractionRevision = 0
    private var draftRoutingStartRevision = 0
    private var draftEditingStartRevision = 0
    private var committedDraftHasContent = false
    private var correctionTargetID: String?
    private var dismissedTemplateText: String?
    private struct PendingActionConfirmation {
        let snapshot: ActionExecutionSnapshot
        let input: ActionInput
        let planID: UUID
        let generation: UUID
        let panelSessionID: UUID
        let source: IntentRecognition.ConfirmationSource
        let decision: RouteDecision
    }
    private var pendingActionConfirmation: PendingActionConfirmation?
    private struct PendingSetup {
        let request: ActionSetupRequest
        let identity: ActionInput.Identity
        let panelSession: Int
        let operationToken: OperationToken?
    }
    private var pendingSetup: PendingSetup?
    private(set) var failedSubmission: FailedSubmission?

    private var operationGeneration: Int64
    private var operationLineageID: String
    private var operationVersion = 0
    private var operationText = ""
    private var operationInput: OperationInput?
    private var capturedOperationToken: OperationToken?
    private var stableInputTask: Task<Void, Never>?
    private var suppressRestoredCapture = false
    private var isRestoringPanel = false
    private var lastAttemptID: String?
    private var firstChoiceEventID: String?
    private var selectionIsInherited = false
    private var thinkingSettingsActive = false
    private var panelIsVisible = false
    private var presentationID = UUID().uuidString
    private var renderedDecision: RouteDecision?
    private var renderedInputIdentity: ActionInput.Identity?
    private struct PresentedRoute {
        let event: OperationEvent
        let token: OperationToken
        let decision: RouteDecision
    }
    private var presentedRoute: PresentedRoute?
    private var lastVisibleToken: OperationToken?
    private var clearedVisibleToken: OperationToken?

    private lazy var actionExecutor: ActionExecutor = {
        let executor = ActionExecutor()
        executor.changed = { [weak self] in self?.preparationChanged($0) }
        return executor
    }()
    private lazy var recognition = IntentRecognition(
        isCurrent: { [weak self] in self?.currentIntentSnapshot == $0 },
        changed: { [weak self] in self?.renderIntentSuggestion() },
        evaluated: { [weak self] in self?.recordLocalRecognition($0, summary: $1, action: $2, reason: $3) })

    init(registry: ActionRegistry, recorder: OperationRecorder,
         catalog: ApplicationCatalog, clipboard: ClipboardService? = nil,
         review: NotesReview? = nil,
         thinkingPromptFactory: @escaping @MainActor () throws -> ModelTextInvocation = {
             throw AIProviderPlugin.Failure(message: "Thinking prompts are not configured", runtimeLogCode: .configuration)
         },
         thinkingFastVersion: @escaping @MainActor () -> String = { "unconfigured" },
         thinkingInstructions: @escaping @MainActor () -> InstantInsightPrompt.Snapshot? = { InstantInsightPrompt().snapshot },
         aiCapabilityReady: @escaping @MainActor (ModelConfiguration.Capability) -> Bool = { _ in false },
         automaticThinkingEnabled: @escaping @MainActor () -> Bool = { false },
         applicationUsage: @escaping () -> [String: ApplicationUsage],
         recordApplicationOpen: @escaping (URL) -> Bool,
         templates: @escaping () -> [InputTemplate] = { InputTemplate.builtIns },
         recentSavedDocuments: RecentSavedDocuments = RecentSavedDocuments(),
         recentDocumentNow: @escaping @MainActor () -> Date = { Date() },
         recentDocumentTimeZone: @escaping @MainActor () -> TimeZone = { .current },
         readSavedDocument: @escaping @MainActor @Sendable (String) async throws -> String = {
             try await AppleNotesReader().body(noteID: $0).text
         }) {
        self.aiCapabilityReady = aiCapabilityReady
        self.thinkingFastVersion = thinkingFastVersion
        self.thinkingInstructions = thinkingInstructions
        self.automaticThinkingEnabled = automaticThinkingEnabled
        self.thinkingPrompt = DraftThinkingPromptSession(factory: thinkingPromptFactory, currentVersion: thinkingFastVersion,
            currentPromptVersion: { thinkingInstructions()?.version })
        state.thinkingPrompt = thinkingPrompt
        self.clipboard = clipboard
        self.review = review
        self.registry = registry
        self.readTemplates = templates
        self.recentDocumentNow = recentDocumentNow
        self.recentDocumentTimeZone = recentDocumentTimeZone
        self.recentSavedDocuments = recentSavedDocuments
        self.readSavedDocument = readSavedDocument
        state.recentDocuments = recentSavedDocuments.documents
        self.recorder = recorder
        self.operationGeneration = recorder.currentGeneration
        self.operationLineageID = recorder.newLineageID()
        self.catalog = catalog
        self.applicationUsage = applicationUsage
        self.recordApplicationOpen = recordApplicationOpen
        refreshRecentDocumentEligibility()
        refreshAIAvailability()
        refreshThinkingPrompt()
        observeAIAvailability()
        clipboard?.history.onChange = { [weak self] in self?.renderIntentSuggestion() }
        review?.onChange = { [weak self] in self?.syncReview() }
        catalog.changed = { [weak self] in
            guard let self else { return }
            self.refresh()
        }
    }

    isolated deinit {
        stableInputTask?.cancel()
        recentDocumentTask?.cancel()
        recentDocumentDayTask?.cancel()
        // 已提交的外部写入不随窗口隐藏或会话释放而取消。
    }

    var draftRevision: Int { revision }
    var hasUnsavedChanges: Bool { revision != savedRevision }

    func send(_ event: LauncherEvent) {
        state.lastEventSucceeded = true
        defer { refreshThinkingPrompt() }
        switch event {
        case .toggleMode: toggleMode()
        case .inputChanged(let text): updateInput(text)
        case .panelPrepared(let quote): state.lastEventSucceeded = prepare(quote: quote)
        case .panelPresented:
            refreshRecentDocumentDate()
            catalog.refreshIfNeeded()
            activate()
        case .selectedTextPermissionNotice(let message):
            state.showSelectedTextPermissionNotice(message)
        case .selectedTextPermissionRecovered:
            state.clearSelectedTextPermissionNotice()
        case .panelDismissed: panelClosed()
        case .panelVisibilityChanged(let visible): recordPanelVisibility(visible)
        case .compositionChanged(let composing):
            state.isComposingText = composing
            if composing {
                stableInputTask?.cancel()
                invalidatePreparation()
                state.canChooseTarget = false
                state.canConfirm = false
                state.intentCanCycle = false
                state.templateCandidates = []
            }
            else { finishCommittedEdit(); trackOperationText(draft.content); refresh() }
        case .confirm(let source): confirm(source)
        case .cycleTarget(let forward): cycleTarget(forward: forward)
        case .selectTarget(let id, let trigger): selectTarget(id: id, trigger: trigger)
        case .toggleTargetMenu:
            guard state.canChooseTarget, !state.isComposingText else { return }
            closeRecentDocument()
            closeReview()
            cancelPendingConfirmation()
            state.isIntentCandidateMenuVisible.toggle()
        case .useAutomatic(let trigger): useAutomatic(trigger: trigger)
        case .candidateMenuChanged(let visible):
            if visible { closeRecentDocument(); closeReview(); cancelPendingConfirmation() }
            state.isIntentCandidateMenuVisible = visible && state.canChooseTarget
            refresh()
        case .selectTemplate(let template): selectTemplate(template)
        case .templateFillingChanged(let active):
            state.isFillingTemplate = active
            if !isReplacingEditor { refresh() }
        case .clipboardSelect(let id):
            guard state.mode == .quickInput, !state.isComposingText else { return }
            clipboard?.history.select(id)
        case .clipboardMove(let forward):
            guard state.mode == .quickInput, !state.isComposingText else { return }
            clipboard?.history.move(forward: forward)
        case .codexRecentTaskOpened:
            guard state.mode == .quickInput else { return }
            state.lastEventSucceeded = clearDraft()
            refresh()
        case .requestThinkingPrompt:
            refreshAIAvailability()
            refreshThinkingPrompt()
            guard thinkingPrompt.blockReason == nil else { return }
            closeRecentDocument()
            closeReview()
            refreshThinkingPrompt()
            thinkingPrompt.requestManually()
        case .closeThinkingPrompt:
            guard !state.isComposingText else { return }
            thinkingPrompt.closeByUser()
        case .thinkingSettingsOpened:
            thinkingPrompt.invalidate()
            // Settings leave the writing surface; resume only on the next panel activation.
            thinkingSettingsActive = true
        case .automaticThinkingPreferenceChanged:
            thinkingSettingsActive = true
        case .thinkingPreferencesChanged:
            break
        case .toggleReview(let period):
            refreshAIAvailability()
            guard state.reviewAIBlockReason == nil else { return }
            guard state.mode == .quickInput, state.modeSwitchBlockReason == nil else { return }
            if state.showsReview, state.reviewPeriod == period { closeReview(); refresh() }
            else {
                closeReview()
                closeRecentDocument()
                cancelPendingConfirmation()
                state.isIntentCandidateMenuVisible = false
                state.templateCandidates = []
                thinkingPrompt.invalidate()
                state.reviewPeriod = period
                state.showsReview = true
                if let review {
                    review.load(period: period, force: false)
                    syncReview()
                } else {
                    state.reviewUnavailableReason = L10n.text("notes.review.unavailable.not_ready")
                }
            }
        case .closeReview:
            guard !state.isComposingText else { return }
            closeReview()
            refresh()
        case .recentDocumentDateChanged:
            refreshRecentDocumentDate()
            refreshThinkingPrompt()
        case .toggleRecentDocuments:
            refreshRecentDocumentDate()
            guard state.canShowRecentDocuments, state.modeSwitchBlockReason == nil else { return }
            if state.selectedRecentDocumentID != nil { closeRecentDocument(); refresh() }
            else if let id = state.recentDocuments.first?.id { showRecentDocument(id) }
        case .navigateRecentDocument(let older):
            refreshRecentDocumentDate()
            guard state.canShowRecentDocuments, state.modeSwitchBlockReason == nil,
                  let position = state.recentDocumentPosition else { return }
            let next = position + (older ? 1 : -1)
            guard state.recentDocuments.indices.contains(next) else { return }
            showRecentDocument(state.recentDocuments[next].id)
        case .selectRecentDocument(let id):
            refreshRecentDocumentDate()
            guard state.canShowRecentDocuments, state.modeSwitchBlockReason == nil,
                  state.recentDocuments.contains(where: { $0.id == id }) else { return }
            if state.selectedRecentDocumentID == id { closeRecentDocument(); refresh() }
            else { showRecentDocument(id) }
        case .retryRecentDocument:
            refreshRecentDocumentDate()
            guard state.canShowRecentDocuments, state.modeSwitchBlockReason == nil,
                  let id = state.selectedRecentDocumentID else { return }
            showRecentDocument(id)
        case .closeRecentDocument:
            guard !state.isComposingText else { return }
            closeRecentDocument()
            refresh()
        case .dismissTemplateMenu:
            dismissedTemplateText = draft.content
            state.templateCandidates = []
            refresh()
        case .readingGettingStartedChanged(let reading):
            state.isReadingGettingStarted = reading
            if reading { suspend() } else { refresh() }
        case .externalFocusChanged: suspend()
        case .refreshConfiguration:
            refreshAIAvailability()
            refresh()
        case .refreshTemplates: refresh()
        case .externalAvailabilityChanged: registry.requestAvailabilityRefresh(invalidate: true)
        case .preserveDraft:
            cancelPendingConfirmation()
            state.lastEventSucceeded = preserveDraft()
        case .captureBeforeTermination:
            thinkingSettingsActive = true
            thinkingPrompt.invalidate()
            guard !state.isComposingText else { return }
            _ = captureOperation(.stableInput, userInitiated: true, allowEmpty: true)
        case .cancel: cancel()
        case .preloadApplications: preloadApplications()
        case .cancelApplicationPreload: cancelApplicationPreload()
        case .restoreFailedSubmission: state.lastEventSucceeded = restoreFailedSubmission()
        case .actionSetupFinished(let id, let result): finishSetup(id: id, result: result)
        }
    }

    private func updateSubmissionTransition() {
        state.isAcceptingSubmission = isSubmitting || clipboardConfirmation != nil
        if state.isAcceptingSubmission { thinkingPrompt.invalidate() }
    }

    private func toggleMode() {
        guard state.modeSwitchBlockReason == nil else {
            state.lastEventSucceeded = false
            return
        }
        let previous = state.mode
        state.mode = previous == .quickInput ? .sticky : .quickInput
        thinkingPrompt.invalidate()
        state.modeGeneration = UUID()
        guard handleEffect(.changeMode(state.mode)) else {
            state.mode = previous
            state.modeGeneration = UUID()
            state.lastEventSucceeded = false
            return
        }
        // Keep draft identity, revision, editor selection and explicit routing intact.
        // A new panel session invalidates preparations from the old panel.
        state.panelSessionID = UUID()
        panelSession += 1
        closeRecentDocument()
        suspend()
        state.isIntentCandidateMenuVisible = false
        dismissedTemplateText = nil
        activate()
    }

    func updateInput(_ text: String) {
        let timing = InputPerformance.begin()
        defer { InputPerformance.end("input", timing) }
        guard !isReplacingEditor else { return }
        // NSTextView supplies a bridged NSString. Materialize it once so the draft,
        // operation state and observable view state reuse the same UTF-8 storage.
        var text = text
        text.makeContiguousUTF8()
        if draft.content != text {
            invalidatePreparation()
            invalidateSetup()
            dismissedTemplateText = nil
            draft.content = text
            revision += 1
            if state.showsReview { closeReview() }   // typing yields the panel back to capture
        }
        if !state.isComposingText { finishCommittedEdit(); trackOperationText(text) }
        synchronizeDraftState()
        refresh()
    }

    /// 开始一次面板展示；草稿始终来自会话，剪贴板内容只是一次输入。
    @discardableResult
    func prepare(quote: String? = nil) -> Bool {
        guard !state.isComposingText else { return false }
        if state.mode == .sticky {
            resumePresentation()
            return true
        }
        invalidatePreparation()
        registry.requestAvailabilityRefresh()
        state.panelSessionID = UUID()
        invalidateSetup()
        var content = draft.content
        if let quote {
            if !content.isEmpty {
                if !content.hasSuffix("\n") { content += "\n" }
                if !content.hasSuffix("\n\n") { content += "\n" }
            }
            content += quote
        }
        guard replaceText(content, reason: .restoreDraft) else { return false }
        panelSession += 1
        hasPreparedDraft = true
        state.hasPreparedDraft = true
        state.message = applicationNotice
        applicationNotice = nil
        activate()
        return true
    }

    func resumePresentation() {
        invalidatePreparation()
        registry.requestAvailabilityRefresh()
        state.panelSessionID = UUID()
        invalidateSetup()
        panelSession += 1
        activate()
    }

    func activate() {
        thinkingSettingsActive = false
        guard pendingSetup == nil else { return }
        acceptsIntentSuggestions = state.mode == .quickInput
        refresh()
    }

    func suspend() {
        _ = handleEffect(.endTemplateEditing)
        clipboardConfirmation = nil
        clipboard?.history.setQuery(nil)
        state.clipboardHistory = nil
        closeReview()
        acceptsIntentSuggestions = false
        state.canChooseTarget = false
        state.canConfirm = false
        state.intentCanCycle = false
        state.templateCandidates = []
        invalidatePreparation()
        recognition.update(nil)
    }

    func panelClosed() {
        thinkingPrompt.invalidate()
        recordPanelVisibility(false)
        closeRecentDocument()
        invalidateSetup()
        suspend()
        actionExecutor.reset()
        state.intentCandidates = []
        state.isIntentCandidateMenuVisible = false
        state.displayedActionTitle = nil
        state.displayedActionIcon = nil
    }

    /// Mirror the review service's observable state into the view state the panel reads.
    private func syncReview() {
        guard state.showsReview, let review, review.period == state.reviewPeriod else { return }
        state.isLoadingReview = review.isLoading
        state.reviewSummary = review.summary
        state.reviewPreview = review.preview
        state.reviewRequestMetadata = review.requestMetadata
        state.reviewFailed = review.failed
        state.reviewCoverageIncomplete = review.coverageIncomplete
        state.reviewUnavailableReason = review.unavailableText
    }

    /// Close only the presentation; the app-owned review keeps running for the next open.
    private func closeReview() {
        guard state.showsReview || state.reviewUnavailableReason != nil || state.reviewSummary != nil
                || state.reviewPreview != nil || state.reviewRequestMetadata != nil || state.isLoadingReview else { return }
        state.showsReview = false
        state.reviewSummary = nil
        state.reviewPreview = nil
        state.reviewRequestMetadata = nil
        state.isLoadingReview = false
        state.reviewFailed = false
        state.reviewCoverageIncomplete = false
        state.reviewUnavailableReason = nil
    }

    func preloadApplications() { catalog.preload() }
    func cancelApplicationPreload() {
        catalog.cancelLoading()
        refresh()
    }

    @discardableResult
    func preserveDraft() -> Bool {
        guard !state.isComposingText else { return false }
        savedRevision = revision
        synchronizeDraftState()
        state.message = nil
        return true
    }

    private func cancel() {
        guard !state.isComposingText else { state.lastEventSucceeded = false; return }
        if state.showsReview {
            closeReview()
            refresh()
            return
        }
        if state.isIntentCandidateMenuVisible {
            state.isIntentCandidateMenuVisible = false
            return
        }
        if thinkingPrompt.display.isOpen {
            thinkingPrompt.closeByUser()
            return
        }
        if state.selectedRecentDocumentID != nil {
            closeRecentDocument()
            refresh()
            return
        }
        if let pendingSetup {
            _ = handleEffect(.closeActionSetup(pendingSetup.request.id))
            finishSetup(id: pendingSetup.request.id, result: .cancelled)
            return
        }
        guard preserveDraft() else {
            state.lastEventSucceeded = false
            return
        }
        suspend()
        _ = handleEffect(.hidePanel(submitted: false, presentationPolicy: .returnToPreviousApplication))
    }

    private var recentDocumentDay: DateInterval? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = recentDocumentTimeZone()
        return calendar.dateInterval(of: .day, for: recentDocumentNow())
    }

    private func refreshRecentDocumentEligibility() {
        let wasAvailable = state.canShowRecentDocuments
        state.recentDocuments = recentSavedDocuments.documents
        let day = recentDocumentDay
        state.canShowRecentDocuments = state.recentDocuments.contains { document in
            guard let day else { return false }
            return document.savedAt >= day.start && document.savedAt < day.end
        }
        let selectionWasRemoved = state.selectedRecentDocumentID != nil && state.selectedRecentDocument == nil
        if !state.canShowRecentDocuments || selectionWasRemoved {
            closeRecentDocument()
            if wasAvailable && !state.canShowRecentDocuments || selectionWasRemoved {
                _ = handleEffect(.restoreEditorAfterRecentDocumentRemoval)
            }
        }
    }

    private func refreshRecentDocumentDate() {
        refreshRecentDocumentEligibility()
        recentDocumentDayTask?.cancel()
        recentDocumentDayTask = nil
        nextRecentDocumentRefresh = nil
        guard panelIsVisible, let midnight = recentDocumentDay?.end else { return }
        nextRecentDocumentRefresh = midnight
        let delay = max(0.05, midnight.timeIntervalSince(recentDocumentNow()))
        recentDocumentDayTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled, let self, self.panelIsVisible else { return }
            self.send(.recentDocumentDateChanged)
        }
    }

    /// Reading a saved document never replaces or submits the current draft.
    private func showRecentDocument(_ id: String) {
        guard state.canShowRecentDocuments, state.recentDocuments.contains(where: { $0.id == id }) else { return }
        thinkingPrompt.invalidate()
        closeReview()
        cancelPendingConfirmation()
        cancelRecentDocumentRead()
        // Keep the lower region open while changing IDs; only the content is replaced.
        state.selectedRecentDocumentID = id
        state.isIntentCandidateMenuVisible = false
        state.isLoadingRecentDocument = true
        let requestID = UUID()
        recentDocumentRequestID = requestID
        refresh()
        recentDocumentTask = Task { [weak self, readSavedDocument] in
            do {
                let text = try await readSavedDocument(id)
                guard !Task.isCancelled, let self, self.recentDocumentRequestID == requestID else { return }
                self.state.recentDocumentText = text
                self.state.isLoadingRecentDocument = false
                self.recentDocumentTask = nil
            } catch {
                guard !Task.isCancelled, let self, self.recentDocumentRequestID == requestID else { return }
                self.state.recentDocumentError = L10n.text("recent_documents.load_failed")
                self.state.isLoadingRecentDocument = false
                self.recentDocumentTask = nil
            }
        }
    }

    private func cancelRecentDocumentRead() {
        recentDocumentRequestID = nil
        recentDocumentTask?.cancel()
        recentDocumentTask = nil
        state.recentDocumentText = nil
        state.recentDocumentError = nil
        state.isLoadingRecentDocument = false
    }

    private func closeRecentDocument() {
        cancelRecentDocumentRead()
        state.selectedRecentDocumentID = nil
    }

    private func observeAIAvailability() {
        withObservationTracking {
            _ = aiCapabilityReady(.fast)
            _ = aiCapabilityReady(.deep)
            _ = thinkingFastVersion()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshAIAvailability()
                self.refreshThinkingPrompt()
                self.observeAIAvailability()
            }
        }
    }

    private func refreshAIAvailability() {
        thinkingAIReady = aiCapabilityReady(.fast)
        state.reviewAIBlockReason = aiCapabilityReady(.deep) ? nil : L10n.text("launcher.ai.requires_configuration")
        if state.reviewAIBlockReason != nil { closeReview() }
    }

    private func refreshThinkingPrompt() {
        let aiReady = thinkingAIReady
        let instructions = thinkingInstructions()
        let empty = draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hardBlocked = !aiReady || instructions == nil || !panelIsVisible || empty || isClipboardInput || thinkingSettingsActive
            || state.isReadingGettingStarted || state.isConfiguringAction || state.isAcceptingSubmission
            || state.isOpeningApplication || pendingActionConfirmation != nil
        let menuBlocked = state.isTemplateMenuVisible || state.isFillingTemplate || state.isIntentCandidateMenuVisible
        if hardBlocked || menuBlocked { thinkingPrompt.invalidate() }
        let reason: String?
        if !aiReady { reason = L10n.text("launcher.ai.requires_configuration") }
        else if instructions == nil { reason = L10n.text("thinking.prompt.invalid") }
        else if let protected = state.modeSwitchBlockReason { reason = protected }
        else if pendingActionConfirmation != nil { reason = L10n.text("launcher.mode.blocked.submission") }
        else if empty { reason = L10n.text("thinking.blocked.empty") }
        else if isClipboardInput { reason = L10n.text("thinking.blocked.clipboard") }
        else if menuBlocked { reason = L10n.text("thinking.blocked.menu") }
        else if !panelIsVisible || thinkingSettingsActive { reason = L10n.text("thinking.blocked.unavailable") }
        else { reason = nil }
        thinkingPrompt.update(.init(draftID: draft.id, revision: revision, text: draft.content,
            panelSessionID: state.panelSessionID, modeGeneration: state.modeGeneration,
            fastVersion: thinkingFastVersion(), prompt: instructions, manualBlockReason: reason,
            automaticBlocked: hardBlocked || menuBlocked || state.isComposingText
                || state.selectedRecentDocumentID != nil || state.showsReview),
            automaticEnabled: automaticThinkingEnabled())
    }

    private func recordSavedDocument(_ id: String) {
        guard NotesSourceLink.url(noteID: id) != nil else { return }
        recentSavedDocuments.record(noteID: id, at: recentDocumentNow())
        refreshRecentDocumentDate()
        if state.selectedRecentDocumentID == id { showRecentDocument(id) }
    }

    func refresh() {
        defer { refreshThinkingPrompt() }
        let timing = InputPerformance.begin()
        defer { InputPerformance.end("refresh", timing) }
        guard !isReplacingEditor else { return }
        guard state.mode == .quickInput else {
            clearStickyAssistance()
            return
        }
        if let pending = pendingActionConfirmation,
           registry.configurationIdentity(for: pending.snapshot.id) != pending.snapshot.configurationIdentity {
            invalidatePreparation()
        }
        if let pendingSetup, !registry.containsModule(id: pendingSetup.request.snapshot.id,
                                                      instance: pendingSetup.request.snapshot.moduleInstance) {
            invalidateSetup()
        }
        state.isIntentRecognitionEnabled = true
        recognition.update(isClipboardInput ? nil : currentIntentSnapshot)
        renderIntentSuggestion()
    }

    private var currentIntentSnapshot: IntentRecognition.Snapshot? {
        guard state.mode == .quickInput, !isClipboardInput, acceptsIntentSuggestions, hasPreparedDraft, !isSubmitting,
              pendingSetup == nil,
              !state.isReadingGettingStarted, !state.isComposingText,
              !state.isOpeningApplication, applicationOpenID == nil,
              !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let available = registry.availableDescriptors
        let defaultActionID = registry.fallbackActionID ?? ""
        let availableActions = available.filter { !$0.requiresExplicitSelection }
            .map { IntentRecognition.ActionTarget(id: $0.id, title: $0.localizedTitle) }
        let matching = currentApplicationEvaluation
        var applications = matching.applications
        if let selected = currentExplicitTarget, selected.kind == .application,
           !applications.contains(where: { $0.id == selected.targetID }),
           let installed = catalog.applications?.first(where: { $0.launcherID == selected.targetID }) {
            applications.append(IntentRecognition.application(installed))
        }
        return .init(draftID: draft.id, revision: revision, panelSession: panelSession,
            registryRevision: registry.revision, text: draft.content,
            applications: applications, applicationRanks: matching.ranks, applicationEvaluation: matching.evaluation,
            availableActions: availableActions,
            defaultActionID: defaultActionID)
    }

    /// One evaluation per draft/catalog revision, shared by recognition, presentation and confirmation.
    private var currentApplicationEvaluation: ApplicationEvaluationCache {
        if let cached = applicationEvaluationCache, cached.draftID == draft.id,
           cached.revision == revision, cached.catalogRevision == catalog.revision { return cached }
        let installed = catalog.applications ?? []
        let usage = applicationUsage()
        let ranks = Dictionary(installed.compactMap { application -> (String, IntentRecognition.ApplicationRank)? in
            guard let value = usage[application.url.path] else { return nil }
            return (application.launcherID, .init(openCount: value.openCount, lastOpenedAt: value.lastOpenedAt))
        }, uniquingKeysWith: { first, _ in first })
        let evaluation = draft.content.utf8.count <= ApplicationMatcher.maximumTextBytes
            ? ApplicationMatcher.evaluate(draft.content, candidates: installed.map {
                .init(id: $0.launcherID, profile: $0.searchProfile)
            }, usage: ranks)
            : .init(resolution: .notApplicable, matches: [], isPureLaunch: false)
        let byID = Dictionary(installed.map { ($0.launcherID, $0) }, uniquingKeysWith: { first, _ in first })
        let applications = evaluation.matches.compactMap { byID[$0.id].map(IntentRecognition.application) }
        let result = ApplicationEvaluationCache(draftID: draft.id, revision: revision, catalogRevision: catalog.revision,
            evaluation: evaluation, applications: applications, ranks: ranks)
        applicationEvaluationCache = result
        return result
    }

    /// 展示、预览和提交每次都消费同一个值类型决策。
    private var routeDecision: RouteDecision {
        if clipboardQuery != nil {
            return .action("clipboard", source: .explicit)
        }
        if let pendingActionConfirmation { return pendingActionConfirmation.decision }
        let snapshot = currentIntentSnapshot
        let selectedID = currentExplicitTarget?.targetID ?? correctionTargetID
        let recognizedID = recognition.suggestion?.targetID
        return routeResolver.resolve(RouteInput(
            draft: draft,
            actions: registry.availableDescriptors,
            explicitTargetID: selectedID,
            recognizedTargetID: recognizedID,
            recognitionIsCurrent: recognition.suggestion?.snapshot == snapshot,
            defaultActionID: registry.fallbackActionID,
            applicationIDs: Set((snapshot?.applications ?? []).map(\.id)),
            setupActions: registry.setupSnapshots().map(\.descriptor),
            defaultSetupActionID: registry.fallbackSetupActionID))
    }

    private func renderIntentSuggestion() {
        defer { refreshThinkingPrompt() }
        guard state.mode == .quickInput else { return }
        guard !state.isComposingText, pendingSetup == nil else { return }
        // The review overlay is modal: hold it steady and skip intent/target/template rendering.
        guard !state.showsReview else { return }
        state.templateCandidates = makeTemplateCandidates()
        if let query = clipboardQuery, let clipboard, hasPreparedDraft, acceptsIntentSuggestions,
           !state.isReadingGettingStarted {
            recognition.update(nil)
            actionExecutor.reset()
            clipboard.history.setQuery(query)
            state.clipboardHistory = clipboard.history
            state.showsCodexRecentTasks = false
            state.intentTitle = L10n.text("clipboard.title")
            state.displayedActionTitle = L10n.text("clipboard.title")
            state.displayedActionIcon = "clipboard"
            state.canChooseTarget = !state.isTemplateMenuVisible
            state.hasExplicitTarget = currentExplicitTarget != nil
            state.intentCanCycle = false
            state.intentDeviated = true
            state.intentIssue = nil
            state.canConfirm = !state.isTemplateMenuVisible && clipboard.history.selectedID != nil && clipboardConfirmation == nil
            state.intentCandidates = makeIntentCandidates().map { IntentCandidate(id: $0.id, title: $0.title, isSelected: $0.id == "clipboard") }
            renderedDecision = routeDecision
            renderedInputIdentity = actionInput().identity
            recordPresentedRoute()
            return
        }
        clipboard?.history.setQuery(nil)
        state.clipboardHistory = nil
        let decision = routeDecision
        let candidates = makeIntentCandidates()
        let routeTargetID = decision.targetID
        let explicitID = currentExplicitTarget?.targetID
        let selectedID = explicitID ?? routeTargetID
        state.intentTitle = selectedID.flatMap(targetTitle) ?? recognition.suggestion?.title
        let interactive = hasPreparedDraft && acceptsIntentSuggestions && !isSubmitting
            && !state.isReadingGettingStarted
        let choosingTemplate = state.isTemplateMenuVisible
        state.showsCodexRecentTasks = explicitID == "codex" && !choosingTemplate
        state.canChooseTarget = interactive && !choosingTemplate
            && (!candidates.isEmpty || explicitID != nil)
        state.intentCanCycle = interactive && !choosingTemplate
            && candidates.contains { $0.id != selectedID }
        state.hasExplicitTarget = explicitID != nil
        state.intentDeviated = state.hasExplicitTarget
        state.canConfirm = interactive && !state.isOpeningApplication && !choosingTemplate
            && !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        state.intentIssue = nil
        state.intentCandidates = candidates.map {
            IntentCandidate(id: $0.id, title: $0.title, isSelected: $0.id == selectedID)
        }
        if !state.canChooseTarget { state.isIntentCandidateMenuVisible = false }
        if choosingTemplate {
            state.displayedActionTitle = nil
            state.displayedActionIcon = nil
            renderedDecision = nil
            renderedInputIdentity = nil
            actionExecutor.reset()
            return
        }
        guard case .empty = decision else {
            render(decision)
            renderedDecision = decision
            renderedInputIdentity = actionInput().identity
            recordPresentedRoute()
            return
        }
        state.displayedActionTitle = explicitID.flatMap(targetTitle)
        state.displayedActionIcon = state.displayedActionTitle == nil ? nil : explicitID.map(targetIcon)
        renderedDecision = decision
        renderedInputIdentity = actionInput().identity
        actionExecutor.reset()
    }

    private func clearStickyAssistance() {
        suspend()
        state.isIntentRecognitionEnabled = false
        state.intentCandidates = []
        state.isIntentCandidateMenuVisible = false
        state.showsCodexRecentTasks = false
        state.displayedActionTitle = nil
        state.displayedActionIcon = nil
        state.intentTitle = nil
        state.intentStatus = nil
        state.intentIssue = nil
        renderedDecision = nil
        renderedInputIdentity = nil
    }

    private func render(_ decision: RouteDecision) {
        switch decision {
        case .action(let id, _):
            guard let descriptor = registry.availableDescriptor(for: id) else {
                state.displayedActionTitle = nil
                state.displayedActionIcon = nil
                actionExecutor.reset()
                return
            }
            state.displayedActionTitle = descriptor.localizedTitle
            state.displayedActionIcon = descriptor.systemImageName
            guard acceptsIntentSuggestions, !isSubmitting else { actionExecutor.reset(); return }
            let input = actionInput()
            guard let configurationIdentity = registry.configurationIdentity(for: id) else {
                actionExecutor.reset()
                return
            }
            let identity = ActionExecutor.Identity(actionID: id, inputIdentity: input.identity,
                configurationIdentity: configurationIdentity, panelSessionID: state.panelSessionID)
            // Repeated renders reuse the existing plan without rebuilding its frozen action.
            guard actionExecutor.current?.identity != identity else { return }
            guard let snapshot = registry.executionSnapshot(for: id) else { actionExecutor.reset(); return }
            actionExecutor.schedule(snapshot: snapshot, input: input, panelSessionID: state.panelSessionID)
        case .application(let id, _):
            let application = currentIntentSnapshot?.applications.first { $0.id == id }
            state.displayedActionTitle = application.map { L10n.text("launcher.open_application", $0.name) }
            state.displayedActionIcon = application == nil ? nil : "app"
            actionExecutor.reset()
        case .setup(let id, _):
            state.displayedActionTitle = registry.setupSnapshot(for: id)?.setup.title
            state.displayedActionIcon = state.displayedActionTitle == nil ? nil : targetIcon(id)
            actionExecutor.reset()
        case .unavailable(let failure, _):
            state.displayedActionTitle = decision.targetID.flatMap(targetTitle)
            state.displayedActionIcon = state.displayedActionTitle == nil ? nil : decision.targetID.map(targetIcon)
            switch failure {
            case .targetUnavailable(let id):
                state.intentIssue = registry.settingsEntry(for: id)?.state.availability.message
                    ?? L10n.text("launcher.target_unavailable")
            case .noDefaultAction: state.intentIssue = L10n.text("launcher.no_default_action")
            }
            actionExecutor.reset()
        case .empty:
            state.displayedActionTitle = nil
            state.displayedActionIcon = nil
            actionExecutor.reset()
        }
    }

    private func makeTemplateCandidates() -> [InputTemplate] {
        guard state.mode == .quickInput, hasPreparedDraft, acceptsIntentSuggestions,
              state.selectedRecentDocumentID == nil,
              !state.isComposingText, !state.isFillingTemplate, !state.isReadingGettingStarted,
              pendingSetup == nil, !isSubmitting, !state.isOpeningApplication,
              dismissedTemplateText != draft.content, !draft.content.contains(where: { $0.isNewline }) else { return [] }
        let query = draft.content.drop(while: { $0.isWhitespace })
        guard query.first == "@" else { return [] }
        let name = String(query.dropFirst())
        return readTemplates().filter { name.isEmpty || $0.name.localizedCaseInsensitiveContains(name) }
    }

    private func selectTemplate(_ template: InputTemplate) {
        guard state.isTemplateMenuVisible, makeTemplateCandidates().contains(template),
              let expansion = try? TemplateExpansion.parse(template.body) else { return }
        let identity = actionInput().identity
        isReplacingEditor = true
        let accepted = handleEffect(.insertTemplate(expansion, expected: identity))
        isReplacingEditor = false
        guard accepted, identity == actionInput().identity else { return }
        updateInput(expansion.text)
    }

    private func makeIntentCandidates() -> [(id: String, title: String)] {
        guard hasPreparedDraft, !state.isReadingGettingStarted, pendingSetup == nil else { return [] }
        let defaultID = registry.fallbackActionID
        var values: [(String, String)] = []
        func append(_ id: String, _ title: String) {
            // 手动切换只开放 Notes 和 Codex；本地应用仍可按草稿自动匹配。
            guard id == "apple-notes" || id == "codex" else { return }
            if !values.contains(where: { $0.0 == id }) { values.append((id, title)) }
        }
        let pinnedApplicationID = currentExplicitTarget?.kind == .application ? currentExplicitTarget?.targetID : nil
        if let suggestion = recognition.suggestion,
           pinnedApplicationID == nil || suggestion.targetID == pinnedApplicationID,
           suggestion.snapshot == currentIntentSnapshot,
           registry.availableDescriptor(for: suggestion.targetID) != nil
            || currentIntentSnapshot?.applications.contains(where: { $0.id == suggestion.targetID }) == true {
            append(suggestion.targetID, suggestion.title)
        }
        for descriptor in registry.availableDescriptors where descriptor.id != defaultID {
            append(descriptor.id, descriptor.localizedTitle)
        }
        if let defaultID, let descriptor = registry.descriptor(for: defaultID) {
            append(defaultID, descriptor.localizedTitle)
        }
        for snapshot in registry.setupSnapshots() {
            append(snapshot.id, snapshot.setup.title)
        }
        if let selected = currentExplicitTarget,
           !values.contains(where: { $0.0 == selected.targetID }) {
            append(selected.targetID, targetTitle(selected.targetID) ?? selected.title)
        }
        return values
    }

    private func targetIcon(_ id: String) -> String {
        if let descriptor = registry.descriptor(for: id) { return descriptor.systemImageName }
        if id.hasPrefix("app_") || currentIntentSnapshot?.applications.contains(where: { $0.id == id }) == true {
            return "app"
        }
        return "square.grid.2x2"
    }

    private func targetTitle(_ id: String) -> String? {
        if let snapshot = registry.setupSnapshot(for: id) { return snapshot.setup.title }
        if let descriptor = registry.descriptor(for: id) { return descriptor.localizedTitle }
        return currentIntentSnapshot?.applications.first(where: { $0.id == id })
            .map { L10n.text("launcher.open_application", $0.name) }
            ?? (currentExplicitTarget?.targetID == id ? currentExplicitTarget?.title : nil)
    }

    func cycleTarget(forward: Bool) {
        guard state.mode == .quickInput, !state.isComposingText, pendingSetup == nil, !isSubmitting,
              !state.isTemplateMenuVisible else { return }
        let candidates = makeIntentCandidates()
        guard !candidates.isEmpty else { return }
        let current = currentExplicitTarget?.targetID ?? routeDecision.targetID
        let nextIndex: Int
        if let index = candidates.firstIndex(where: { $0.id == current }) {
            nextIndex = ((index + (forward ? 1 : -1)) % candidates.count + candidates.count) % candidates.count
        } else {
            nextIndex = forward ? 0 : candidates.count - 1
        }
        selectTarget(id: candidates[nextIndex].id, trigger: .keyboard)
    }

    func selectTarget(id: String, trigger: OperationSelectionTrigger = .button) {
        guard !state.isComposingText, acceptsIntentSuggestions, pendingSetup == nil,
              !isSubmitting, !state.isTemplateMenuVisible,
              let candidate = makeIntentCandidates().first(where: { $0.id == id }) else { return }
        _ = handleEffect(.endTemplateEditing)
        invalidatePreparation()
        let token = captureOperation(.selection, userInitiated: true, allowEmpty: true)
        recordPresentedRoute(token: token)
        routingInteractionRevision += 1
        let kind = selectionTargetKind(id)
        restoreRoutingSelection(.init(targetID: id, title: candidate.title, origin: .userChoice, kind: kind))
        recordSelection(id: id, origin: .userChoice, trigger: trigger, token: token)
        state.isIntentCandidateMenuVisible = false
        renderIntentSuggestion()
    }

    private func useAutomatic(trigger: OperationSelectionTrigger) {
        guard !state.isComposingText, acceptsIntentSuggestions, pendingSetup == nil,
              !isSubmitting, !state.isTemplateMenuVisible,
              currentExplicitTarget != nil else { return }
        _ = handleEffect(.endTemplateEditing)
        invalidatePreparation()
        let token = captureOperation(.selection, userInitiated: true, allowEmpty: true)
        recordPresentedRoute(token: token)
        routingInteractionRevision += 1
        restoreRoutingSelection(nil)
        firstChoiceEventID = nil
        selectionIsInherited = false
        if let token {
            recordEvent(.targetSelected, token: token,
                details: .selection(.init(selectionOrigin: .automatic, trigger: trigger, mode: .automatic)))
        }
        state.isIntentCandidateMenuVisible = false
        refresh()
    }

    func confirm(_ source: IntentRecognition.ConfirmationSource) {
        guard state.mode == .quickInput else { return }
        guard !state.isTemplateMenuVisible else { return }
        if state.isIntentCandidateMenuVisible {
            state.isIntentCandidateMenuVisible = false
            return
        }
        if pendingActionConfirmation != nil { return }
        let enteredDecision = renderedDecision
        let enteredIdentity = renderedInputIdentity
        guard hasPreparedDraft, acceptsIntentSuggestions, !isSubmitting,
              pendingSetup == nil,
              !state.isOpeningApplication, !state.isComposingText,
              !state.isReadingGettingStarted else {
            recordBlockedConfirmation(state.isComposingText ? "composition_active" : pendingSetup != nil ? "setup_active" : "session_unavailable")
            return
        }
        if clipboardQuery != nil { confirmClipboard(source); return }
        if draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recordBlockedConfirmation("empty_input")
            guard preserveDraft() else { return }
            suspend()
            _ = handleEffect(.hidePanel(submitted: false, presentationPolicy: .returnToPreviousApplication))
            return
        }
        registry.refreshAvailability()
        guard let intentSnapshot = currentIntentSnapshot else { return }
        let resolved = routeDecision
        // Refresh can synchronously publish registry changes and render a fallback. Keep the
        // destination the user confirmed before probing, including its action/setup kind.
        guard enteredIdentity == actionInput().identity,
              let enteredDecision, sameDestination(enteredDecision, resolved) else {
            invalidatePreparation()
            refresh()
            state.message = L10n.text("launcher.target_unavailable")
            recordBlockedConfirmation("target_changed")
            return
        }
        switch resolved {
        case .setup(let id, _):
            guard let snapshot = registry.setupSnapshot(for: id) else { return }
            beginSetup(snapshot)
        case .action(let id, _):
            guard let snapshot = registry.executionSnapshot(for: id) else {
                state.message = L10n.text("launcher.action_unavailable")
                recordBlockedConfirmation("target_unavailable")
                return
            }
            confirmAction(snapshot, decision: resolved, source: source)
        case .application(let id, _):
            guard let application = intentSnapshot.applications.first(where: { $0.id == id }) else {
                state.message = L10n.text("launcher.application_unavailable")
                recordBlockedConfirmation("target_unavailable")
                return
            }
            guard canLaunch(application, snapshot: intentSnapshot) else {
                state.message = L10n.text("launcher.application_unavailable")
                recordBlockedConfirmation("target_unavailable")
                return
            }
            let attempt = recordAttempt(targetKind: .application, targetID: id, decision: resolved, source: source)
            _ = recognition.finishSuggestion(confirmed: recognition.suggestion?.targetID == id)
            launchSuggestedApplication(application, snapshot: intentSnapshot, operation: attempt)
        case .unavailable(.targetUnavailable(let id), _):
            state.message = registry.settingsEntry(for: id)?.state.availability.message
                ?? L10n.text("launcher.target_unavailable")
            recordBlockedConfirmation("target_unavailable")
        case .unavailable(.noDefaultAction, _), .empty:
            state.message = L10n.text("launcher.no_default_action")
            recordBlockedConfirmation("no_default_action")
        }
    }

    private var isClipboardInput: Bool {
        return currentExplicitTarget?.targetID == "clipboard"
    }

    private var clipboardQuery: String? {
        guard isClipboardInput, clipboard != nil, registry.availableDescriptor(for: "clipboard") != nil else { return nil }
        return actionInput().text
    }

    private func confirmClipboard(_ source: IntentRecognition.ConfirmationSource) {
        guard clipboardConfirmation == nil, let clipboard,
              let selected = clipboard.history.entries.first(where: { $0.id == clipboard.history.selectedID }) else { return }
        let identity = actionInput().identity, session = state.panelSessionID, confirmation = UUID()
        clipboardConfirmation = confirmation
        state.canConfirm = false
        let decision = RouteDecision.action("clipboard", source: .explicit)
        let attempt = recordAttempt(targetKind: .action, targetID: "clipboard", decision: decision, source: source)
        recordSubmission(attempt, accepted: true)
        Task { [weak self] in
            guard let self else { return }
            defer {
                if self.clipboardConfirmation == confirmation { self.clipboardConfirmation = nil }
                self.refresh()
            }
            do {
                try await clipboard.history.restore(selected, through: clipboard) { [weak self] in
                    guard let self else { return false }
                    return self.clipboardConfirmation == confirmation && self.actionInput().identity == identity
                        && self.state.panelSessionID == session && self.acceptsIntentSuggestions
                        && self.clipboardQuery != nil && !self.state.isComposingText
                        && clipboard.history.selectedID == selected.id
                }
                self.recordExecution(attempt, outcome: .completed)
                guard self.clearDraft() else { return }
                self.suspend()
                _ = self.handleEffect(.hidePanel(submitted: true, presentationPolicy: .returnToPreviousApplication))
            } catch {
                if self.clipboardConfirmation == confirmation {
                    self.state.message = L10n.text((error as? ClipboardFailure)?.key ?? "clipboard.copy_failed")
                }
                self.recordExecution(attempt, outcome: .failed)
            }
        }
    }

    private func sameDestination(_ lhs: RouteDecision, _ rhs: RouteDecision) -> Bool {
        switch (lhs, rhs) {
        case (.action(let a, _), .action(let b, _)),
             (.setup(let a, _), .setup(let b, _)),
             (.application(let a, _), .application(let b, _)):
            return a == b
        case (.unavailable, .unavailable): return lhs == rhs
        default: return false
        }
    }

    private func beginSetup(_ snapshot: ActionSetupSnapshot) {
        guard pendingSetup == nil else { return }
        let request = ActionSetupRequest(id: UUID(), snapshot: snapshot)
        let token = captureOperation(.confirmation, userInitiated: true)
        recordPresentedRoute(token: token)
        pendingSetup = PendingSetup(request: request, identity: actionInput().identity,
                                    panelSession: panelSession, operationToken: token)
        if let token {
            recordEvent(.setupStarted, token: token, targetKind: .setup, targetID: snapshot.id,
                        details: .setup(.init(setupID: request.id.uuidString)))
            recorder.markInflight(token, activityID: request.id.uuidString, active: true)
        }
        state.isConfiguringAction = true
        state.isIntentCandidateMenuVisible = false
        actionExecutor.reset()
        suspend()
        if !handleEffect(.showActionSetup(request)) {
            finishSetup(id: request.id, result: .cancelled)
        }
    }

    private func finishSetup(id: UUID, result: ActionSetupResult) {
        guard let pending = pendingSetup, pending.request.id == id else { return }
        recordSetupFinished(pending, outcome: result == .completed ? .completed : .cancelled)
        pending.request.snapshot.setup.invalidate()
        pendingSetup = nil
        state.isConfiguringAction = false
        guard pending.identity == actionInput().identity, pending.panelSession == panelSession,
              !state.isComposingText,
              registry.containsModule(id: pending.request.snapshot.id,
                                      instance: pending.request.snapshot.moduleInstance) else { return }
        if result == .completed, registry.availableDescriptor(for: pending.request.snapshot.id) != nil {
            let selected = pending.request.snapshot
            routingInteractionRevision += 1
            restoreRoutingSelection(.init(targetID: selected.id, title: selected.descriptor.localizedTitle,
                                          origin: .setupCompletion))
            recordSelection(id: selected.id, origin: .setupCompletion, trigger: .setupCompletion,
                            token: captureOperation(.selection, allowEmpty: true))
        }
        activate()
        isRestoringPanel = true
        _ = handleEffect(.restoreEditorAfterSetup)
        isRestoringPanel = false
    }

    private func invalidateSetup() {
        guard let pending = pendingSetup else { return }
        recordSetupFinished(pending, outcome: .cancelled, reason: "superseded")
        pendingSetup = nil
        state.isConfiguringAction = false
        pending.request.snapshot.setup.invalidate()
        _ = handleEffect(.closeActionSetup(pending.request.id))
    }

    private func submit(_ snapshot: ActionExecutionSnapshot, prepared: PreparedAction, planID: UUID,
                        operation: RecordedAttempt?) {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false; renderIntentSuggestion() }
        let submitted = draft
        let input = actionInput()
        let submittedSelection = currentExplicitTarget
        suspend()
        _ = handleEffect(.prepareSubmission)
        guard clearDraft() else {
            recordSubmission(operation, accepted: false, reason: "editor_rejected_clear")
            _ = handleEffect(.cancelSubmission)
            activate()
            return
        }
        recordSubmission(operation, accepted: true)
        let emptyDraftID = draft.id
        let emptyRevision = revision
        let emptyRoutingRevision = routingInteractionRevision
        let requestID = UUID()
        var log = RuntimeLog.Context()
        log.module = .app
        log.operation = .action
        log.emit(.requestStarted, .init(bytes: input.text.utf8.count, actionID: snapshot.id, attemptID: operation?.attempt.id))
        let execution = RuntimeLog.$current.withValue(log) {
            actionExecutor.executionTask(prepared: prepared, planID: planID, snapshot: snapshot, input: input)
        }
        _ = handleEffect(.hidePanel(submitted: true,
            presentationPolicy: snapshot.descriptor.presentationPolicy))
        activeSubmissionCount += 1
        submissions[requestID] = Task { [weak self] in
            do {
                let outcome = try await execution.value
                if snapshot.id == "apple-notes", outcome.effect == .created, let noteID = outcome.savedNoteID {
                    self?.recordSavedDocument(noteID)
                }
                self?.recordExecution(operation, outcome: outcome.effect)
                if outcome.showsCompletionNotice, let message = outcome.localizedMessage {
                    let destination = outcome.completionDestination
                        ?? snapshot.descriptor.applicationBundleIdentifier.map { .application(bundleIdentifier: $0) }
                    _ = self?.handleEffect(.showCompletionNotice(message,
                        destination: destination))
                } else {
                    self?.applicationNotice = outcome.localizedMessage
                }
                log.emit(.requestFinished, .init(outcome: .success, actionID: snapshot.id, attemptID: operation?.attempt.id))
            } catch {
                let failure = ActionFailure.presentation(for: error)
                self?.recordExecution(operation, outcome: failure.executionOutcome, reason: failure.code.rawValue)
                log.emit(.requestFinished, .init(outcome: .failed, errorCode: failure.code,
                    osStatus: failure.osStatus, actionID: snapshot.id, attemptID: operation?.attempt.id))
                self?.restoreAfterFailure(submitted, emptyDraftID: emptyDraftID,
                    emptyRevision: emptyRevision, emptyRoutingRevision: emptyRoutingRevision,
                    selection: submittedSelection, message: failure.message, operation: operation)
            }
            self?.submissions.removeValue(forKey: requestID)
            self?.activeSubmissionCount -= 1
        }
    }

    private func restoreAfterFailure(_ submitted: RecordDraft,
                                     emptyDraftID: UUID, emptyRevision: Int, emptyRoutingRevision: Int,
                                     selection: DraftTargetSelection?, message: String, operation: RecordedAttempt?) {
        let failed = FailedSubmission(draft: submitted, message: message, selection: selection,
            selectionIsInherited: operation?.selectionIsInherited ?? true,
            operationInput: operation?.token.input, operationGeneration: operation?.token.generation,
            sourceAttemptID: operation?.attempt.id, firstChoiceEventID: operation?.attempt.firstChoiceEventID)
        guard state.mode == .quickInput, !state.isComposingText, draft.id == emptyDraftID, revision == emptyRevision,
              routingInteractionRevision == emptyRoutingRevision else {
            failedSubmission = failed
            state.hasFailedSubmission = true
            state.message = message
            return
        }
        guard replaceText(submitted.content, reason: .restoreDraft) else {
            failedSubmission = failed
            state.hasFailedSubmission = true
            state.message = message
            return
        }
        draft.id = submitted.id
        restoreRoutingSelection(selection)
        restoreOperationInput(operation?.token.input, generation: operation?.token.generation,
                              attemptID: operation?.attempt.id, firstChoiceID: operation?.attempt.firstChoiceEventID,
                              inheritedSelection: operation?.selectionIsInherited ?? true, merged: false)
        savedRevision = revision
        synchronizeDraftState()
        failedSubmission = nil
        state.hasFailedSubmission = false
        applicationNotice = message
        isRestoringPanel = true
        _ = handleEffect(.showPanel)
        isRestoringPanel = false
        state.message = message
    }

    private func canLaunch(_ application: IntentRecognition.Application, snapshot: IntentRecognition.Snapshot) -> Bool {
        currentIntentSnapshot == snapshot && applicationOpenID == nil
            && ApplicationCatalog.isLaunchable(application.url, bundleIdentifier: application.bundleIdentifier)
    }

    private func launchSuggestedApplication(_ application: IntentRecognition.Application,
                                            snapshot: IntentRecognition.Snapshot, operation: RecordedAttempt?) {
        guard canLaunch(application, snapshot: snapshot), preserveDraft() else {
            recordSubmission(operation, accepted: false, reason: "application_unavailable")
            return
        }
        let requestID = UUID()
        let submittedSelection = currentExplicitTarget
        let submittedRoutingRevision = routingInteractionRevision
        let submittedSelectionWasInherited = selectionIsInherited
        applicationOpenID = requestID
        state.isOpeningApplication = true
        suspend()
        _ = handleEffect(.hideForApplicationLaunch)
        var dispatched = false
        var completed = false
        let log = RuntimeLog.Context(module: .app, draftID: snapshot.draftID, operation: .action)
        _ = handleEffect(.openApplication(application.url, dispatched: { [weak self] in
            guard !dispatched, !completed else { return }
            dispatched = true
            log.emit(.requestStarted, .init(bytes: snapshot.text.utf8.count, actionID: application.id,
                                           attemptID: operation?.attempt.id))
            self?.recordSubmission(operation, accepted: true)
            if let self, self.draft.id == snapshot.draftID, self.revision == snapshot.revision,
               self.routingInteractionRevision == submittedRoutingRevision {
                self.restoreRoutingSelection(nil)
                self.selectionIsInherited = false
                self.renderIntentSuggestion()
            }
        }, completion: { [weak self] result in
            guard !completed else { return }
            completed = true
            if dispatched {
                switch result {
                case .success:
                    self?.recordExecution(operation, outcome: .opened)
                    log.emit(.requestFinished, .init(outcome: .success, actionID: application.id,
                                                    attemptID: operation?.attempt.id))
                case .failure(let error):
                    let failure = ActionFailure.presentation(for: error)
                    self?.recordExecution(operation, outcome: failure.executionOutcome, reason: failure.code.rawValue)
                    log.emit(.requestFinished, .init(outcome: .failed, errorCode: failure.code,
                        osStatus: failure.osStatus, actionID: application.id, attemptID: operation?.attempt.id))
                }
            } else {
                self?.recordSubmission(operation, accepted: false, reason: "application_not_dispatched")
            }
            guard let self, self.applicationOpenID == requestID else { return }
            self.applicationOpenID = nil
            guard dispatched else {
                self.state.isOpeningApplication = false
                return
            }
            let ownsRoutingInput = self.draft.id == snapshot.draftID && self.revision == snapshot.revision
                && self.draft.content == snapshot.text && !self.state.isComposingText
                && self.routingInteractionRevision == submittedRoutingRevision
            let ownsInput = ownsRoutingInput && self.panelSession == snapshot.panelSession
            switch result {
            case .failure:
                if ownsRoutingInput {
                    self.restoreRoutingSelection(submittedSelection)
                    if let operation, self.recorder.isCurrent(operation.token) {
                        self.firstChoiceEventID = operation.attempt.firstChoiceEventID
                        self.selectionIsInherited = submittedSelectionWasInherited
                    } else {
                        self.firstChoiceEventID = nil
                        self.selectionIsInherited = submittedSelection != nil
                    }
                    self.applicationNotice = L10n.text("launcher.open_failed_preserved", application.name)
                }
            case .success:
                _ = self.recordApplicationOpen(application.url)
                self.applicationEvaluationCache = nil
                if ownsInput, snapshot.applicationEvaluation?.clearsDraft(for: application.id) == true {
                    if !self.clearDraft(recordOperation: operation.map { self.recorder.isCurrent($0.token) } ?? false) {
                        self.applicationNotice = L10n.text("launcher.opened_clear_failed")
                    }
                }
            }
            self.state.isOpeningApplication = false
            self.refresh()
        }))
        if !dispatched, !completed {
            completed = true
            recordSubmission(operation, accepted: false, reason: "application_not_dispatched")
            applicationOpenID = nil
            state.isOpeningApplication = false
        }
    }

    @discardableResult
    private func clearDraft(recordOperation: Bool = true) -> Bool {
        guard !state.isComposingText else { return false }
        let token = recordOperation ? captureOperation(.clear) : nil
        // 先确认原生编辑器接受替换；失败时不动逻辑草稿。
        guard replaceText("", reason: .newDraft) else { return false }
        if let token { recordEvent(.draftCleared, token: token, details: .clear(.init())) }
        if panelIsVisible { clearedVisibleToken = token ?? lastVisibleToken }
        resetOperationLineage(text: "")
        clearExplicitTarget()
        correctionTargetID = nil
        draft = RecordDraft()
        draftRoutingStartRevision = routingInteractionRevision
        committedDraftHasContent = false
        revision += 1
        draftEditingStartRevision = revision
        savedRevision = revision
        synchronizeDraftState()
        state.message = nil
        state.intentCandidates = []
        state.isIntentCandidateMenuVisible = false
        state.displayedActionTitle = nil
        state.displayedActionIcon = nil
        state.templateCandidates = []
        closeReview()
        return true
    }

    private func replaceText(_ text: String, reason: ReplacementReason) -> Bool {
        guard !state.isComposingText else { return false }
        isReplacingEditor = true
        defer { isReplacingEditor = false }
        guard handleEffect(.replaceEditor(text, reason)) else { return false }
        thinkingPrompt.invalidate()
        if draft.content != text {
            invalidatePreparation()
            dismissedTemplateText = nil
            draft.content = text
            revision += 1
            closeReview()
        }
        committedDraftHasContent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        trackOperationText(text)
        synchronizeDraftState()
        return true
    }

    private func synchronizeDraftState() {
        state.draftContent = draft.content
        state.hasPreparedDraft = hasPreparedDraft
        state.hasUnsavedChanges = hasUnsavedChanges
    }

    // MARK: - Identified preparation and the single confirmation gate

    private func cancelPendingConfirmation() {
        pendingActionConfirmation = nil
        state.isPreparingAction = false
    }

    private func invalidatePreparation() {
        cancelPendingConfirmation()
        actionExecutor.reset()
    }

    private func preparationChanged(_ preparation: ActionExecutor.Preparation?) {
        defer { refreshThinkingPrompt() }
        guard state.mode == .quickInput || preparation == nil else { return }
        state.preparationFailure = nil
        guard let preparation else {
            cancelPendingConfirmation()
            return
        }
        if let pending = pendingActionConfirmation, pending.generation != preparation.generation {
            cancelPendingConfirmation()
        }
        switch preparation.status {
        case .failed(let failure):
            state.preparationFailure = failure.message
            cancelPendingConfirmation()
        case .preparing: break
        case .ready: finishPendingConfirmation()
        }
    }

    private func confirmAction(_ snapshot: ActionExecutionSnapshot, decision: RouteDecision,
                               source: IntentRecognition.ConfirmationSource) {
        let input = actionInput()
        actionExecutor.schedule(snapshot: snapshot, input: input,
            panelSessionID: state.panelSessionID, confirmed: true)
        guard let preparation = actionExecutor.current else {
            recordBlockedConfirmation("preparation_unavailable")
            return
        }
        switch preparation.status {
        case .failed:
            correctionTargetID = snapshot.id
            recordBlockedConfirmation("preparation_failed")
            return
        case .preparing, .ready: break
        }
        guard let plan = preparation.status.plan else { return }
        pendingActionConfirmation = PendingActionConfirmation(snapshot: snapshot, input: input, planID: plan.id,
            generation: preparation.generation, panelSessionID: state.panelSessionID,
            source: source, decision: decision)
        state.isPreparingAction = true
        finishPendingConfirmation()
    }

    private func finishPendingConfirmation() {
        guard let pending = pendingActionConfirmation else { return }
        guard state.mode == .quickInput, acceptsIntentSuggestions, !state.isComposingText, !state.isReadingGettingStarted,
              pending.input.identity == actionInput().identity, pending.input.text == actionInput().text,
              pending.panelSessionID == state.panelSessionID,
              registry.configurationIdentity(for: pending.snapshot.id) == pending.snapshot.configurationIdentity,
              let preparation = actionExecutor.current, preparation.generation == pending.generation,
              let plan = preparation.status.plan, plan.id == pending.planID else {
            invalidatePreparation()
            renderIntentSuggestion()
            return
        }
        guard let prepared = actionExecutor.prepared(planID: pending.planID, snapshot: pending.snapshot,
                input: pending.input, panelSessionID: pending.panelSessionID) else { return }
        let operation = recordAttempt(targetKind: .action, targetID: pending.snapshot.id,
                                      decision: pending.decision, source: pending.source)
        cancelPendingConfirmation()
        _ = recognition.finishSuggestion(confirmed: recognition.suggestion?.targetID == pending.snapshot.id)
        submit(pending.snapshot, prepared: prepared, planID: pending.planID, operation: operation)
    }

    // MARK: - Local operation facts

    private struct RecordedAttempt {
        let token: OperationToken
        let attempt: OperationAttempt
        let startedAt: UInt64
        let selectionIsInherited: Bool
    }

    private func resetOperationLineage(text: String) {
        stableInputTask?.cancel()
        operationGeneration = recorder.currentGeneration
        operationLineageID = recorder.newLineageID()
        operationVersion = 0
        operationText = text
        operationInput = nil
        capturedOperationToken = nil
        firstChoiceEventID = nil
        lastAttemptID = nil
        selectionIsInherited = currentExplicitTarget != nil
        presentedRoute = nil
        suppressRestoredCapture = false
    }

    private func synchronizeOperationGeneration(userInitiated: Bool = false) {
        if operationGeneration != recorder.currentGeneration {
            resetOperationLineage(text: operationText)
            // An old timer, model result, or setup callback is not a new user action.
            suppressRestoredCapture = true
        }
        if recorder.isRetired(lineageID: operationLineageID) {
            if userInitiated { resetOperationLineage(text: operationText) }
            else { suppressRestoredCapture = true }
        }
    }

    /// Revision belongs to editing/execution. Operation versions count only committed body changes.
    private func trackOperationText(_ text: String) {
        synchronizeOperationGeneration(userInitiated: text != operationText)
        guard text != operationText else { return }
        operationText = text
        operationVersion += 1
        operationInput = nil
        capturedOperationToken = nil
        presentedRoute = nil
        firstChoiceEventID = nil
        lastAttemptID = nil
        selectionIsInherited = currentExplicitTarget != nil
        suppressRestoredCapture = false
        stableInputTask?.cancel()
        guard !text.isEmpty else { return }
        stableInputTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard let self, !Task.isCancelled, !self.state.isComposingText else { return }
            self.stableInputTask = nil
            self.recordPresentedRoute(token: self.captureOperation(.stableInput))
        }
    }

    private func operationContext() -> OperationContext? {
        let actions = registry.settingsEntries().map { entry -> OperationActionConfiguration in
            let availability: String = switch entry.state.availability {
            case .ready: "ready"
            case .needsConfiguration: "needs_configuration"
            case .unavailable: "unavailable"
            }
            return .init(id: entry.id, localKeywords: entry.descriptor.intentHints.localKeywords,
                         modelBinding: "none", modelCriteria: nil, isEnabled: entry.isEnabled,
                         availability: availability, unavailableReasonCode: availability == "ready" ? nil : availability,
                         fallbackPriority: entry.descriptor.fallbackPriority)
        }
        return try? OperationContext(capturedAt: OperationRecorder.nowMilliseconds(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            ruleVersion: nil, requestedModel: nil,
            configuration: .init(localRules: [], actions: actions, defaultTargetID: registry.fallbackActionID ?? registry.fallbackSetupActionID,
                recognitionEnabled: false, recognitionQuestion: nil, thresholds: []))
    }

    private func captureOperation(_ trigger: OperationCaptureTrigger, userInitiated: Bool = false,
                                  allowEmpty: Bool = false) -> OperationToken? {
        synchronizeOperationGeneration(userInitiated: userInitiated)
        if userInitiated { suppressRestoredCapture = false }
        guard !suppressRestoredCapture,
              allowEmpty || !operationText.isEmpty || [.confirmation, .clear, .hide].contains(trigger),
              let context = operationContext() else { return nil }
        if operationInput == nil {
            operationInput = OperationInput(id: UUID().uuidString, lineageID: operationLineageID,
                inputVersion: operationVersion, capturedAt: OperationRecorder.nowMilliseconds(), text: operationText)
        }
        guard let input = operationInput else { return nil }
        if let token = capturedOperationToken, token.inputID == input.id, token.contextID == context.id,
           recorder.isCurrent(token) { return token }
        let token = recorder.capture(input: input, context: context, trigger: trigger)
        capturedOperationToken = token
        return token
    }

    @discardableResult
    private func recordEvent(_ kind: OperationEventKind, token: OperationToken, attemptID: String? = nil,
                             requestID: String? = nil, targetKind: OperationTargetKind? = nil, targetID: String? = nil,
                             routeSource: OperationRouteSource? = nil, outcome: OperationEventOutcome? = nil,
                             reason: String? = nil, duration: Int64? = nil, details: OperationDetails) -> String? {
        let event = OperationEvent(id: UUID().uuidString, inputID: token.inputID, contextID: token.contextID,
            runID: token.runID, occurredAt: OperationRecorder.nowMilliseconds(), kind: kind,
            attemptID: attemptID, requestID: requestID, targetKind: targetKind, targetID: targetID,
            routeSource: routeSource, outcome: outcome, reasonCode: reason, durationMS: duration, details: details)
        return recorder.record(event, token: token) ? event.id : nil
    }

    private func operationSource(_ source: RouteSource?) -> OperationRouteSource? {
        switch source {
        case .explicit: .explicit
        case .localKeyword: .localKeyword
        case .fallback: .fallback
        case .recognition: .localApplication
        case nil: nil
        }
    }

    private func operationTarget(_ decision: RouteDecision) -> (OperationTargetKind?, String?, OperationEventOutcome) {
        switch decision {
        case .action(let id, _): (.action, id, .available)
        case .application(let id, _): (.application, id, .available)
        case .setup(let id, _): (.setup, id, .setup)
        case .unavailable(.targetUnavailable(let id), _): (.unknown, id, .unavailable)
        case .unavailable, .empty: (nil, nil, .unavailable)
        }
    }

    private func recordPanelVisibility(_ visible: Bool) {
        defer { refreshRecentDocumentDate(); refreshThinkingPrompt() }
        if !visible { thinkingPrompt.invalidate(); closeRecentDocument(); closeReview() }
        guard panelIsVisible != visible else { return }
        if visible {
            panelIsVisible = true
            presentationID = UUID().uuidString
            presentedRoute = nil
            clearedVisibleToken = nil
            let token = captureOperation(.stableInput, userInitiated: !isRestoringPanel, allowEmpty: true)
            if let token {
                lastVisibleToken = token
                recordEvent(.panelOpened, token: token, details: .panel(.init(presentationID: presentationID)))
            }
            recordPresentedRoute(token: token)
        } else {
            invalidatePreparation()
            state.panelSessionID = UUID()
            let token = clearedVisibleToken ?? captureOperation(.hide) ?? lastVisibleToken
            if let token {
                recordEvent(.panelHidden, token: token, details: .panel(.init(presentationID: presentationID)))
            }
            panelIsVisible = false
            presentedRoute = nil
            lastVisibleToken = nil
            clearedVisibleToken = nil
        }
    }

    private func recordPresentedRoute(token suppliedToken: OperationToken? = nil) {
        guard panelIsVisible, !state.isComposingText, pendingSetup == nil, !suppressRestoredCapture else { return }
        // Ordinary typing is sampled after it settles; user actions and recognition force a capture.
        guard suppliedToken != nil || operationInput != nil else { return }
        guard let token = suppliedToken ?? captureOperation(.stableInput) else { return }
        guard recorder.isCurrent(token) else { return }
        lastVisibleToken = token
        let decision = routeDecision
        guard renderedDecision == decision, renderedInputIdentity == actionInput().identity else { return }
        guard case .empty = decision else {
            let (kind, id, outcome) = operationTarget(decision)
            let source = operationSource(decision.source)
            if let old = presentedRoute, old.token.inputID == token.inputID, old.token.contextID == token.contextID,
               old.decision == decision, old.event.routeSource == source { return }
            let event = OperationEvent(id: UUID().uuidString, inputID: token.inputID, contextID: token.contextID,
                runID: token.runID, occurredAt: OperationRecorder.nowMilliseconds(), kind: .routePresented,
                targetKind: kind, targetID: id, routeSource: source, outcome: outcome,
                details: .route(.init(presentationID: presentationID)))
            if recorder.record(event, token: token) { presentedRoute = .init(event: event, token: token, decision: decision) }
            return
        }
    }

    private func selectionTargetKind(_ id: String) -> OperationTargetKind {
        if registry.setupSnapshot(for: id) != nil { return .setup }
        if registry.descriptor(for: id) != nil { return .action }
        if currentExplicitTarget?.targetID == id { return currentExplicitTarget?.kind ?? .unknown }
        return currentIntentSnapshot?.applications.contains(where: { $0.id == id }) == true ? .application : .unknown
    }

    private func recordSelection(id: String, origin: OperationSelectionOrigin,
                                 trigger: OperationSelectionTrigger, token: OperationToken?) {
        guard let token else {
            selectionIsInherited = true
            firstChoiceEventID = nil
            return
        }
        let kind = selectionTargetKind(id)
        let previous = presentedRoute.flatMap { $0.token.inputID == token.inputID ? $0.event.id : nil }
        let eventID = recordEvent(.targetSelected, token: token, targetKind: kind, targetID: id, routeSource: .explicit,
            details: .selection(.init(selectionOrigin: origin, trigger: trigger, previousPresentedEventID: previous)))
        selectionIsInherited = eventID == nil
        if eventID == nil { firstChoiceEventID = nil }
        else if origin == .userChoice, firstChoiceEventID == nil { firstChoiceEventID = eventID }
    }

    private func recordBlockedConfirmation(_ reason: String) {
        guard let token = captureOperation(.confirmation, userInitiated: true) else { return }
        recordEvent(.confirmationBlocked, token: token, outcome: .unavailable, reason: reason,
                    details: .confirmation(.init()))
    }

    private func recordAttempt(targetKind: OperationTargetKind, targetID: String, decision: RouteDecision,
                               source: IntentRecognition.ConfirmationSource) -> RecordedAttempt? {
        guard let token = captureOperation(.confirmation, userInitiated: true, allowEmpty: targetID == "clipboard"),
              let routeSource = operationSource(decision.source) else { return nil }
        recordPresentedRoute(token: token)
        let confirmation: OperationConfirmationSource = switch source {
        case .enter: .enter
        case .commandEnter: .commandEnter
        case .button: .button
        }
        let displayed = presentedRoute.flatMap {
            $0.token.inputID == token.inputID && $0.event.targetKind == targetKind && $0.event.targetID == targetID
                && $0.event.routeSource == routeSource && $0.event.outcome == .available ? $0.event.id : nil
        }
        let attempt = OperationAttempt(id: UUID().uuidString, inputID: token.inputID, contextID: token.contextID,
            targetKind: targetKind, targetID: targetID, routeSource: routeSource,
            selectionOrigin: decision.source == .explicit ? currentExplicitTarget?.origin ?? .automatic : .automatic,
            confirmationSource: confirmation, decisionEventID: displayed,
            firstChoiceEventID: decision.source == .explicit ? firstChoiceEventID : nil,
            retryOfAttemptID: lastAttemptID)
        let event = OperationEvent(id: UUID().uuidString, inputID: token.inputID, contextID: token.contextID,
            runID: token.runID, occurredAt: OperationRecorder.nowMilliseconds(), kind: .confirmRequested,
            attemptID: attempt.id, details: .confirmation(.init(
                textTransform: (targetKind == .application || registry.descriptor(for: targetID)?.preservesOriginalText == true
                        ? .unchanged : .trimWhitespaceAndNewlines),
                selectionContinuity: decision.source == .explicit && currentExplicitTarget != nil
                    ? (selectionIsInherited ? .inherited : .direct) : nil)))
        guard recorder.confirm(attempt, event: event, token: token) else { return nil }
        lastAttemptID = attempt.id
        recorder.markInflight(token, activityID: attempt.id, active: true)
        return RecordedAttempt(token: token, attempt: attempt, startedAt: RuntimeLog.ticks(),
                               selectionIsInherited: selectionIsInherited)
    }

    private func recordSubmission(_ operation: RecordedAttempt?, accepted: Bool, reason: String? = nil) {
        guard let operation else { return }
        recordEvent(accepted ? .submissionAccepted : .submissionRejected, token: operation.token,
            attemptID: operation.attempt.id, outcome: accepted ? .accepted : .failed, reason: reason,
            details: .submission(.init()))
        if !accepted { recorder.markInflight(operation.token, activityID: operation.attempt.id, active: false) }
    }

    private func recordExecution(_ operation: RecordedAttempt?, outcome: OperationExecutionOutcome, reason: String? = nil) {
        guard let operation else { return }
        recordEvent(.executionFinished, token: operation.token, attemptID: operation.attempt.id,
            outcome: OperationEventOutcome(rawValue: outcome.rawValue), reason: reason,
            duration: Int64(RuntimeLog.milliseconds(since: operation.startedAt)), details: .execution(.init()))
        recorder.markInflight(operation.token, activityID: operation.attempt.id, active: false)
    }

    private func recordSetupFinished(_ pending: PendingSetup, outcome: OperationEventOutcome, reason: String? = nil) {
        guard let token = pending.operationToken else { return }
        recordEvent(.setupFinished, token: token, targetKind: .setup, targetID: pending.request.snapshot.id,
                    outcome: outcome, reason: reason, details: .setup(.init(setupID: pending.request.id.uuidString)))
        recorder.markInflight(token, activityID: pending.request.id.uuidString, active: false)
    }

    private func restoreOperationInput(_ input: OperationInput?, generation: Int64?, attemptID: String?,
                                       firstChoiceID: String?, inheritedSelection: Bool = true,
                                       merged: Bool, userInitiated: Bool = false) {
        stableInputTask?.cancel()
        guard let input else {
            if !merged { resetOperationLineage(text: draft.content) }
            suppressRestoredCapture = !userInitiated
            if userInitiated { _ = captureOperation(.stableInput, userInitiated: true) }
            return
        }
        let sourceIsCurrent = generation == recorder.currentGeneration && !recorder.isRetired(lineageID: input.lineageID)
        if !sourceIsCurrent {
            if !merged { resetOperationLineage(text: draft.content) }
            suppressRestoredCapture = !userInitiated
            guard userInitiated else { return }
        } else if !merged {
            operationGeneration = recorder.currentGeneration
            operationLineageID = input.lineageID
            operationVersion = input.inputVersion
            operationText = input.text
            operationInput = input
            capturedOperationToken = nil
            firstChoiceEventID = firstChoiceID
            lastAttemptID = attemptID
            selectionIsInherited = currentExplicitTarget != nil && inheritedSelection
            presentedRoute = nil
        }
        guard let token = captureOperation(.stableInput, userInitiated: userInitiated) else { return }
        recordEvent(.draftRestored, token: token,
            details: .restoration(.init(sourceLineageID: input.lineageID, sourceAttemptID: attemptID,
                                       mode: merged ? .merge : .restore)))
    }

    private func recordLocalRecognition(_ snapshot: IntentRecognition.Snapshot, summary: RecognitionSummary,
                                        action: IntentRecognition.Action?, reason: String?) {
        guard !state.isComposingText, snapshot.text == operationText,
              let token = captureOperation(.recognition), let identifier = summary.requestID?.uuidString else { return }
        let matches = snapshot.applicationEvaluation.map { Dictionary(uniqueKeysWithValues: $0.matches.map { ($0.id, $0.kind.rawValue) }) }
        var details = OperationRecognitionDetails()
        details.candidates = snapshot.applications.filter { matches == nil || matches?[$0.id] != nil }
            .enumerated().map { index, application in
            .init(id: application.id, name: application.name, bundleIdentifier: application.bundleIdentifier,
                  rank: index, match: matches?[application.id] ?? summary.applicationMatch?.rawValue,
                  openCount: snapshot.applicationRanks[application.id]?.openCount,
                  lastOpenedAt: snapshot.applicationRanks[application.id].map { Int64($0.lastOpenedAt.timeIntervalSince1970 * 1000) })
        }
        recordEvent(.recognitionStarted, token: token, requestID: identifier,
                    details: .recognition(details))
        let target: String? = action.map { switch $0 { case .openApplication(let id): id } }
        recordEvent(.recognitionFinished, token: token, requestID: identifier,
                    targetKind: target == nil ? nil : .application, targetID: target,
                    routeSource: .localApplication, outcome: target == nil ? .noSuggestion : .suggested,
                    reason: reason, details: .recognition(details))
        recordPresentedRoute(token: token)
    }

    private func actionInput() -> ActionInput {
        ActionInput(identity: .init(draftID: draft.id, revision: revision),
                    text: draft.content.trimmingCharacters(in: .whitespacesAndNewlines),
                    originalText: draft.content)
    }

    private var currentExplicitTarget: DraftTargetSelection? {
        explicitTargetDraftID == draft.id ? explicitTarget : nil
    }

    private func clearExplicitTarget() {
        explicitTarget = nil
        explicitTargetDraftID = nil
        state.hasExplicitTarget = false
        state.intentDeviated = false
    }

    private func restoreRoutingSelection(_ selection: DraftTargetSelection?) {
        explicitTarget = selection
        explicitTargetDraftID = selection == nil ? nil : draft.id
        correctionTargetID = nil
        state.hasExplicitTarget = selection != nil
        state.intentDeviated = selection != nil
    }

    /// Only a committed edit from content to whitespace ends a draft. IME candidates never do.
    private func finishCommittedEdit() {
        let hasContent = !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if committedDraftHasContent && !hasContent {
            let token = captureOperation(.clear, userInitiated: true, allowEmpty: true)
            if let token { recordEvent(.draftCleared, token: token, details: .clear(.init())) }
            clearExplicitTarget()
            correctionTargetID = nil
            draft.id = UUID()
            draftRoutingStartRevision = routingInteractionRevision
            draftEditingStartRevision = revision
            resetOperationLineage(text: draft.content)
        }
        committedDraftHasContent = hasContent
    }

    @discardableResult
    private func restoreFailedSubmission() -> Bool {
        guard state.mode == .quickInput, let failedSubmission, !state.isComposingText else { return false }
        let hasContent = !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let merged = hasContent || revision != draftEditingStartRevision
            || routingInteractionRevision != draftRoutingStartRevision
        let content = hasContent ? draft.content + "\n\n" + failedSubmission.draft.content : failedSubmission.draft.content
        guard replaceText(content, reason: .restoreDraft) else { return false }
        if !merged {
            draft.id = failedSubmission.draft.id
            restoreRoutingSelection(failedSubmission.selection)
        }
        restoreOperationInput(failedSubmission.operationInput, generation: failedSubmission.operationGeneration,
                              attemptID: failedSubmission.sourceAttemptID,
                              firstChoiceID: failedSubmission.firstChoiceEventID,
                              inheritedSelection: failedSubmission.selectionIsInherited,
                              merged: merged, userInitiated: true)
        self.failedSubmission = nil
        state.hasFailedSubmission = false
        state.message = failedSubmission.message
        refresh()
        return true
    }

}

struct DraftTargetSelection: Sendable, Equatable {
    let targetID: String
    let title: String
    let origin: OperationSelectionOrigin
    var kind: OperationTargetKind = .action
}

struct FailedSubmission: Sendable, Equatable {
    let draft: RecordDraft
    let message: String
    var selection: DraftTargetSelection? = nil
    var selectionIsInherited = false
    var operationInput: OperationInput? = nil
    var operationGeneration: Int64? = nil
    var sourceAttemptID: String? = nil
    var firstChoiceEventID: String? = nil
}
