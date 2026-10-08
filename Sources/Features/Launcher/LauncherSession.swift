import Foundation

enum LauncherEvent {
    case inputChanged(String)
    case panelPrepared(quote: String?)
    case panelPresented
    case panelDismissed
    case panelVisibilityChanged(Bool)
    case compositionChanged(Bool)
    case confirm(IntentRecognition.ConfirmationSource)
    case cycleTarget(forward: Bool)
    case selectTarget(String, trigger: OperationSelectionTrigger = .button)
    case toggleTargetMenu
    case useAutomatic(trigger: OperationSelectionTrigger = .button)
    case candidateMenuChanged(Bool)
    case readingGettingStartedChanged(Bool)
    case externalFocusChanged
    case refreshConfiguration
    case preserveDraft
    case captureBeforeTermination
    case cancel
    case preloadApplications
    case cancelApplicationPreload
    case restoreFailedSubmission
    case actionSetupFinished(UUID, ActionSetupResult)
    case planPresented(planID: UUID, panelSessionID: UUID)
    case timeContextChanged
}

enum LauncherEffect {
    case replaceEditor(String, LauncherSession.ReplacementReason)
    case prepareSubmission
    case cancelSubmission
    case hidePanel(submitted: Bool, presentationPolicy: PresentationPolicy)
    case hideForApplicationLaunch
    case showPanel
    case showActionSetup(ActionSetupRequest)
    case closeActionSetup(UUID)
    case restoreEditorAfterSetup
    case openApplication(URL, dispatched: @MainActor () -> Void, completion: @MainActor (Result<Void, Error>) -> Void)
}

/// 启动器会话：拥有草稿、意图、路由和提交任务，不持有窗口或原生编辑器。
@MainActor
final class LauncherSession {
    struct Configuration {
        let revision: UUID
        let hasAPIKey: Bool
    }

    enum ReplacementReason { case restoreDraft, newDraft }

    let state = LauncherViewState()
    let catalog: ApplicationCatalog
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

    private let registry: ActionRegistry
    private let recorder: OperationRecorder
    private let configuration: () -> Configuration
    private let readKey: @MainActor @Sendable () throws -> String?
    private let recognize: IntentRecognition.Recognize
    private let applicationUsage: () -> [String: ApplicationUsage]
    private let recordApplicationOpen: (URL) -> Bool
    private let routeResolver = RouteResolver()
    private var revision = 0
    private var savedRevision = 0
    private var panelSession = 0
    private var acceptsIntentSuggestions = false
    private var isReplacingEditor = false
    private var isSubmitting = false
    private var applicationOpenID: UUID?
    private var applicationNotice: String?
    private var recognizingHintTask: Task<Void, Never>?
    private var submissions: [UUID: Task<Void, Never>] = [:]
    private var explicitTarget: DraftTargetSelection?
    private var explicitTargetDraftID: UUID?
    private var routingInteractionRevision = 0
    private var draftRoutingStartRevision = 0
    private var draftEditingStartRevision = 0
    private var committedDraftHasContent = false
    private var correctionTargetID: String?
    private let now: @MainActor () -> Date
    private let timeZone: @MainActor () -> TimeZone
    private var preparationClockTask: Task<Void, Never>?
    private struct PendingActionConfirmation {
        let snapshot: ActionExecutionSnapshot
        let input: ActionInput
        let planID: UUID
        let generation: UUID
        let panelSessionID: UUID
        let configuration: UUID
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
    private var recognitionTokens: [UUID: (token: OperationToken, started: UInt64)] = [:]

    private lazy var actionExecutor: ActionExecutor = {
        let executor = ActionExecutor()
        executor.changed = { [weak self] in self?.preparationChanged($0) }
        return executor
    }()
    private lazy var recognition = IntentRecognition(
        readKey: readKey, recognize: recognize,
        isCurrent: { [weak self] in self?.currentIntentSnapshot == $0 },
        changed: { [weak self] in self?.renderIntentSuggestion() },
        requestStarted: { [weak self] in self?.recordRecognitionStarted($0, trace: $1) },
        requestFinished: { [weak self] in self?.recordRecognitionFinished($0, trace: $1, outcome: $2, action: $3, actualModel: $4) })

    init(registry: ActionRegistry, recorder: OperationRecorder,
         catalog: ApplicationCatalog,
         configuration: @escaping () -> Configuration,
         readKey: @escaping @MainActor @Sendable () throws -> String?,
         recognize: @escaping IntentRecognition.Recognize,
         applicationUsage: @escaping () -> [String: ApplicationUsage],
         recordApplicationOpen: @escaping (URL) -> Bool,
         now: @escaping @MainActor () -> Date = { Date() },
         timeZone: @escaping @MainActor () -> TimeZone = { .current }) {
        self.registry = registry
        self.recorder = recorder
        self.operationGeneration = recorder.currentGeneration
        self.operationLineageID = recorder.newLineageID()
        self.catalog = catalog
        self.configuration = configuration
        self.readKey = readKey
        self.recognize = recognize
        self.applicationUsage = applicationUsage
        self.recordApplicationOpen = recordApplicationOpen
        self.now = now
        self.timeZone = timeZone
        catalog.changed = { [weak self] in
            guard let self else { return }
            self.refresh()
        }
    }

    isolated deinit {
        recognizingHintTask?.cancel()
        stableInputTask?.cancel()
        preparationClockTask?.cancel()
        // 已提交的外部写入不随窗口隐藏或会话释放而取消。
    }

    var hasUnsavedChanges: Bool { revision != savedRevision }

    func send(_ event: LauncherEvent) {
        state.lastEventSucceeded = true
        switch event {
        case .inputChanged(let text): updateInput(text)
        case .panelPrepared(let quote): state.lastEventSucceeded = prepare(quote: quote)
        case .panelPresented:
            catalog.refreshIfNeeded()
            activate()
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
            }
            else { finishCommittedEdit(); trackOperationText(draft.content); refresh() }
        case .confirm(let source): confirm(source)
        case .cycleTarget(let forward): cycleTarget(forward: forward)
        case .selectTarget(let id, let trigger): selectTarget(id: id, trigger: trigger)
        case .toggleTargetMenu:
            guard state.canChooseTarget, !state.isComposingText else { return }
            cancelPendingConfirmation()
            state.isIntentCandidateMenuVisible.toggle()
        case .useAutomatic(let trigger): useAutomatic(trigger: trigger)
        case .candidateMenuChanged(let visible):
            if visible { cancelPendingConfirmation() }
            state.isIntentCandidateMenuVisible = visible && state.canChooseTarget
            refresh()
        case .readingGettingStartedChanged(let reading):
            state.isReadingGettingStarted = reading
            if reading { suspend() } else { refresh() }
        case .externalFocusChanged: suspend()
        case .refreshConfiguration: refresh()
        case .preserveDraft:
            cancelPendingConfirmation()
            state.lastEventSucceeded = preserveDraft()
        case .captureBeforeTermination:
            guard !state.isComposingText else { return }
            _ = captureOperation(.stableInput, userInitiated: true, allowEmpty: true)
        case .cancel: cancel()
        case .preloadApplications: preloadApplications()
        case .cancelApplicationPreload: cancelApplicationPreload()
        case .restoreFailedSubmission: state.lastEventSucceeded = restoreFailedSubmission()
        case .actionSetupFinished(let id, let result): finishSetup(id: id, result: result)
        case .planPresented(let planID, let sessionID):
            acknowledgePresentedPlan(planID, panelSessionID: sessionID)
        case .timeContextChanged:
            invalidatePreparation()
            refresh()
        }
    }

    func updateInput(_ text: String) {
        guard !isReplacingEditor else { return }
        if draft.content != text {
            invalidatePreparation()
            invalidateSetup()
            draft.content = text
            revision += 1
        }
        if !state.isComposingText { finishCommittedEdit(); trackOperationText(text) }
        synchronizeDraftState()
        refresh()
    }

    /// 开始一次面板展示；草稿始终来自会话，剪贴板内容只是一次输入。
    @discardableResult
    func prepare(quote: String? = nil) -> Bool {
        guard !state.isComposingText else { return false }
        invalidatePreparation()
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
        state.panelSessionID = UUID()
        invalidateSetup()
        panelSession += 1
        activate()
    }

    func activate() {
        guard pendingSetup == nil else { return }
        acceptsIntentSuggestions = true
        refresh()
    }

    func suspend() {
        acceptsIntentSuggestions = false
        state.canChooseTarget = false
        state.canConfirm = false
        state.intentCanCycle = false
        invalidatePreparation()
        recognition.update(nil)
        cancelRecognizingHint()
    }

    func panelClosed() {
        recordPanelVisibility(false)
        invalidateSetup()
        suspend()
        actionExecutor.reset()
        state.intentCandidates = []
        state.isIntentCandidateMenuVisible = false
        state.displayedActionTitle = nil
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
        if state.isIntentCandidateMenuVisible {
            state.isIntentCandidateMenuVisible = false
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

    func refresh() {
        guard !isReplacingEditor else { return }
        registry.refreshAvailability()
        if let pending = pendingActionConfirmation,
           pending.configuration != configuration().revision
            || registry.executionSnapshot(for: pending.snapshot.id)?.configurationIdentity != pending.snapshot.configurationIdentity {
            invalidatePreparation()
        }
        _ = checkPreparationContext()
        if let pendingSetup, !registry.containsModule(id: pendingSetup.request.snapshot.id,
                                                      instance: pendingSetup.request.snapshot.moduleInstance) {
            invalidateSetup()
        }
        state.isIntentRecognitionEnabled = true
        recognition.update(currentIntentSnapshot)
        renderIntentSuggestion()
        updateRecognizingHint()
    }

    private var currentIntentSnapshot: IntentRecognition.Snapshot? {
        guard acceptsIntentSuggestions, hasPreparedDraft, !isSubmitting,
              pendingSetup == nil,
              !state.isReadingGettingStarted, !state.isComposingText,
              !state.isOpeningApplication, applicationOpenID == nil,
              !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let available = registry.executionSnapshots()
        let defaultActionID = registry.fallbackActionID ?? ""
        let availableActions = available
            .map { IntentRecognition.ActionTarget(id: $0.id, title: $0.descriptor.localizedTitle) }
        let captureOptions = available.compactMap { snapshot -> Jev.CaptureOption? in
            guard case .capture(let criteria) = snapshot.descriptor.intentHints.modelBinding else { return nil }
            return Jev.CaptureOption(id: snapshot.id, criteria: criteria)
        }
        let webSearchActionID = available.first {
            $0.descriptor.intentHints.modelBinding == .webSearch
        }?.id
        let conversationActionID = available.first {
            $0.descriptor.intentHints.modelBinding == .conversation
        }?.id
        let applications = draft.content.utf8.count <= Jev.maximumTextBytes
            ? IntentRecognition.applicationCandidates(in: draft.content, from: catalog.applications ?? []) : []
        let usage = applicationUsage()
        let ranks = Dictionary(applications.compactMap { application -> (String, IntentRecognition.ApplicationRank)? in
            guard let value = usage[application.url.resolvingSymlinksInPath().path] else { return nil }
            return (application.id, .init(openCount: value.openCount, lastOpenedAt: value.lastOpenedAt))
        }, uniquingKeysWith: { first, _ in first })
        return .init(draftID: draft.id, revision: revision, panelSession: panelSession,
            configuration: configuration().revision, registryRevision: registry.revision, text: draft.content,
            applications: applications, applicationRanks: ranks, availableActions: availableActions,
            defaultActionID: defaultActionID, captureOptions: captureOptions,
            webSearchActionID: webSearchActionID, conversationActionID: conversationActionID)
    }

    /// 展示、预览和提交每次都消费同一个值类型决策。
    private var routeDecision: RouteDecision {
        if let pendingActionConfirmation { return pendingActionConfirmation.decision }
        let snapshot = currentIntentSnapshot
        let selectedID = currentExplicitTarget?.targetID ?? correctionTargetID
        let recognizedID = recognition.suggestion?.targetID
        return routeResolver.resolve(RouteInput(
            draft: draft,
            actions: registry.executionSnapshots().map(\.descriptor),
            userRules: registry.currentUserRules,
            explicitTargetID: selectedID,
            recognizedTargetID: recognizedID,
            recognitionIsCurrent: recognition.suggestion?.snapshot == snapshot,
            defaultActionID: registry.fallbackActionID,
            applicationIDs: Set((snapshot?.applications ?? []).map(\.id)),
            setupActions: registry.setupSnapshots().map(\.descriptor),
            defaultSetupActionID: registry.fallbackSetupActionID))
    }

    private func renderIntentSuggestion() {
        updateRecognizingHint()
        guard !state.isComposingText, pendingSetup == nil else { return }
        let decision = routeDecision
        let candidates = makeIntentCandidates()
        let routeTargetID = decision.targetID
        let explicitID = currentExplicitTarget?.targetID
        let selectedID = explicitID ?? routeTargetID
        state.intentTitle = selectedID.flatMap(targetTitle) ?? recognition.suggestion?.title
        let interactive = hasPreparedDraft && acceptsIntentSuggestions && !isSubmitting
            && !state.isReadingGettingStarted
        state.canChooseTarget = interactive && (!candidates.isEmpty || explicitID != nil)
        state.intentCanCycle = interactive && candidates.contains { $0.id != selectedID }
        state.hasExplicitTarget = explicitID != nil
        state.intentDeviated = state.hasExplicitTarget
        state.canConfirm = interactive && !state.isOpeningApplication
            && !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let issue = recognition.issue
        state.intentIssue = issue == JevDiagnostics.Reason.missingKey.userMessage ? nil : issue
        state.intentCandidates = candidates.map {
            IntentCandidate(id: $0.id, title: $0.title, isSelected: $0.id == selectedID)
        }
        if !state.canChooseTarget { state.isIntentCandidateMenuVisible = false }
        guard case .empty = decision else {
            render(decision)
            renderedDecision = decision
            renderedInputIdentity = actionInput().identity
            recordPresentedRoute()
            return
        }
        state.displayedActionTitle = explicitID.flatMap(targetTitle)
        renderedDecision = decision
        renderedInputIdentity = actionInput().identity
        actionExecutor.reset()
    }

    private func render(_ decision: RouteDecision) {
        switch decision {
        case .action(let id, _):
            guard let snapshot = registry.executionSnapshot(for: id) else {
                state.displayedActionTitle = nil
                actionExecutor.reset()
                return
            }
            state.displayedActionTitle = snapshot.descriptor.localizedTitle
            guard acceptsIntentSuggestions, !isSubmitting else { actionExecutor.reset(); return }
            actionExecutor.schedule(snapshot: snapshot, input: actionInput(),
                context: ScheduleContext(referenceDate: now(), timeZone: timeZone()), panelSessionID: state.panelSessionID)
        case .application(let id, _):
            let application = currentIntentSnapshot?.applications.first { $0.id == id }
            state.displayedActionTitle = application.map { L10n.text("launcher.open_application", $0.name) }
            actionExecutor.reset()
        case .setup(let id, _):
            state.displayedActionTitle = registry.setupSnapshot(for: id)?.setup.title
            actionExecutor.reset()
        case .unavailable(let failure, _):
            state.displayedActionTitle = decision.targetID.flatMap(targetTitle)
            switch failure {
            case .targetUnavailable(let id):
                state.intentIssue = registry.settingsEntry(for: id)?.state.availability.message
                    ?? L10n.text("launcher.target_unavailable")
            case .noDefaultAction: state.intentIssue = L10n.text("launcher.no_default_action")
            }
            actionExecutor.reset()
        case .empty:
            state.displayedActionTitle = nil
            actionExecutor.reset()
        }
    }

    private func updateRecognizingHint() {
        let wantsHint = recognition.isRecognizing && !state.isComposingText
            && !state.isIntentCandidateMenuVisible
        guard wantsHint else {
            cancelRecognizingHint()
            state.intentStatus = nil
            return
        }
        guard recognizingHintTask == nil else { return }
        let session = panelSession
        recognizingHintTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self, self.panelSession == session,
                  self.recognition.isRecognizing else { return }
            self.recognizingHintTask = nil
            self.state.intentStatus = L10n.text("launcher.recognizing")
        }
    }

    private func cancelRecognizingHint() {
        recognizingHintTask?.cancel()
        recognizingHintTask = nil
    }

    private func makeIntentCandidates() -> [(id: String, title: String)] {
        guard hasPreparedDraft, !state.isReadingGettingStarted, pendingSetup == nil else { return [] }
        let defaultID = registry.fallbackActionID
        var values: [(String, String)] = []
        func append(_ id: String, _ title: String) {
            if !values.contains(where: { $0.0 == id }) { values.append((id, title)) }
        }
        if let suggestion = recognition.suggestion,
           suggestion.snapshot == currentIntentSnapshot,
           registry.executionSnapshot(for: suggestion.targetID) != nil
            || currentIntentSnapshot?.applications.contains(where: { $0.id == suggestion.targetID }) == true {
            append(suggestion.targetID, suggestion.title)
        }
        for snapshot in registry.executionSnapshots() where snapshot.id != defaultID {
            append(snapshot.id, snapshot.descriptor.localizedTitle)
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

    private func targetTitle(_ id: String) -> String? {
        if let snapshot = registry.setupSnapshot(for: id) { return snapshot.setup.title }
        if let descriptor = registry.descriptor(for: id) { return descriptor.localizedTitle }
        return currentIntentSnapshot?.applications.first(where: { $0.id == id })
            .map { L10n.text("launcher.open_application", $0.name) }
            ?? (currentExplicitTarget?.targetID == id ? currentExplicitTarget?.title : nil)
    }

    func cycleTarget(forward: Bool) {
        guard !state.isComposingText, pendingSetup == nil, !isSubmitting else { return }
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
              !isSubmitting, let candidate = makeIntentCandidates().first(where: { $0.id == id }) else { return }
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
              !isSubmitting, currentExplicitTarget != nil else { return }
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
        if state.isIntentCandidateMenuVisible {
            state.isIntentCandidateMenuVisible = false
            return
        }
        if pendingActionConfirmation != nil { return }
        let enteredPlanID = state.currentPlanID
        let enteredSessionID = state.panelSessionID
        guard hasPreparedDraft, acceptsIntentSuggestions, !isSubmitting,
              pendingSetup == nil,
              !state.isOpeningApplication, !state.isComposingText,
              !state.isReadingGettingStarted else {
            recordBlockedConfirmation(state.isComposingText ? "composition_active" : pendingSetup != nil ? "setup_active" : "session_unavailable")
            return
        }
        if draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recordBlockedConfirmation("empty_input")
            guard preserveDraft() else { return }
            suspend()
            _ = handleEffect(.hidePanel(submitted: false, presentationPolicy: .returnToPreviousApplication))
            return
        }
        registry.refreshAvailability()
        let contextChanged = checkPreparationContext()
        guard let intentSnapshot = currentIntentSnapshot else { return }
        let resolved = routeDecision
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
            confirmAction(snapshot, decision: resolved, source: source,
                          enteredPlanID: contextChanged ? nil : enteredPlanID, enteredSessionID: enteredSessionID)
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
        if result == .completed, registry.executionSnapshot(for: pending.request.snapshot.id) != nil {
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
        let execution = actionExecutor.executionTask(prepared: prepared, planID: planID, snapshot: snapshot, input: input)
        recordSubmission(operation, accepted: true)
        let emptyDraftID = draft.id
        let emptyRevision = revision
        let emptyRoutingRevision = routingInteractionRevision
        let requestID = UUID()
        var log = RuntimeLog.Context()
        log.module = .app
        log.operation = .action
        log.emit(.requestStarted, .init(bytes: input.text.utf8.count, actionID: snapshot.id, attemptID: operation?.attempt.id))
        _ = handleEffect(.hidePanel(submitted: true,
            presentationPolicy: snapshot.descriptor.presentationPolicy))
        activeSubmissionCount += 1
        submissions[requestID] = Task { [weak self] in
            do {
                let outcome = try await execution.value
                self?.applicationNotice = outcome.localizedMessage
                self?.recordExecution(operation, outcome: outcome.effect)
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
        guard !state.isComposingText, draft.id == emptyDraftID, revision == emptyRevision,
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
                if ownsInput, IntentRecognition.isPureApplicationLaunch(snapshot.text, application: application,
                                                                       ranks: snapshot.applicationRanks) {
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
        cancelRecognizingHint()
        state.message = nil
        state.intentCandidates = []
        state.isIntentCandidateMenuVisible = false
        state.displayedActionTitle = nil
        return true
    }

    private func replaceText(_ text: String, reason: ReplacementReason) -> Bool {
        guard !state.isComposingText else { return false }
        isReplacingEditor = true
        defer { isReplacingEditor = false }
        guard handleEffect(.replaceEditor(text, reason)) else { return false }
        if draft.content != text {
            invalidatePreparation()
            draft.content = text
            revision += 1
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
        preparationClockTask?.cancel()
        preparationClockTask = nil
        state.presentedPlanID = nil
        actionExecutor.reset()
    }

    private func preparationChanged(_ preparation: ActionExecutor.Preparation?) {
        if let preparation {
            let date = now(), zone = timeZone()
            let valid = preparation.status.plan?.isCurrent(at: date, timeZone: zone)
                ?? preparation.context.isCurrent(at: date, timeZone: zone)
            if !valid {
                invalidatePreparation()
                renderIntentSuggestion()
                return
            }
        }
        let plan = preparation?.status.plan
        if state.currentPlanID != plan?.id { state.presentedPlanID = nil }
        state.currentPlanID = plan?.id
        state.planSummary = plan?.summary
        state.planContext = plan?.context
        state.timeIssue = nil
        state.preparationFailure = nil
        state.isCheckingActionPlan = false
        guard let preparation else {
            cancelPendingConfirmation()
            preparationClockTask?.cancel()
            preparationClockTask = nil
            return
        }
        if let pending = pendingActionConfirmation, pending.generation != preparation.generation {
            cancelPendingConfirmation()
        }
        switch preparation.status {
        case .needsInput(let issue):
            state.timeIssue = issue
            cancelPendingConfirmation()
        case .failed(let failure):
            state.preparationFailure = failure.message
            cancelPendingConfirmation()
        case .preparing: break
        case .ready: finishPendingConfirmation()
        }
        startPreparationClock()
    }

    private func startPreparationClock() {
        guard preparationClockTask == nil, actionExecutor.current != nil else { return }
        preparationClockTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, !Task.isCancelled else { return }
                if self.checkPreparationContext() { self.refresh() }
            }
        }
    }

    @discardableResult
    private func checkPreparationContext() -> Bool {
        guard let preparation = actionExecutor.current else { return false }
        let date = now(), zone = timeZone()
        let valid = preparation.status.plan?.isCurrent(at: date, timeZone: zone)
            ?? preparation.context.isCurrent(at: date, timeZone: zone)
        guard !valid else { return false }
        invalidatePreparation()
        return true
    }

    private func acknowledgePresentedPlan(_ planID: UUID, panelSessionID: UUID) {
        guard panelIsVisible, acceptsIntentSuggestions, pendingSetup == nil,
              !state.isComposingText, !state.isReadingGettingStarted,
              state.panelSessionID == panelSessionID, state.currentPlanID == planID,
              let preparation = actionExecutor.current, let plan = preparation.status.plan,
              preparation.identity.inputIdentity == actionInput().identity,
              preparation.identity.panelSessionID == panelSessionID, plan.id == planID, plan.summary != nil else { return }
        if checkPreparationContext() { refresh(); return }
        state.presentedPlanID = planID
    }

    private func confirmAction(_ snapshot: ActionExecutionSnapshot, decision: RouteDecision,
                               source: IntentRecognition.ConfirmationSource,
                               enteredPlanID: UUID?, enteredSessionID: UUID) {
        let input = actionInput()
        actionExecutor.schedule(snapshot: snapshot, input: input,
            context: ScheduleContext(referenceDate: now(), timeZone: timeZone()), panelSessionID: state.panelSessionID)
        guard let preparation = actionExecutor.current else {
            recordBlockedConfirmation("preparation_unavailable")
            return
        }
        switch preparation.status {
        case .needsInput(let issue):
            correctionTargetID = snapshot.id
            recordBlockedConfirmation(issue.reasonCode)
            return
        case .failed:
            correctionTargetID = snapshot.id
            recordBlockedConfirmation("preparation_failed")
            return
        case .preparing, .ready: break
        }
        guard let plan = preparation.status.plan, plan.isCurrent(at: now(), timeZone: timeZone()) else {
            correctionTargetID = snapshot.id
            recordBlockedConfirmation("time_expired")
            invalidatePreparation()
            renderIntentSuggestion()
            return
        }
        if plan.summary != nil {
            guard panelIsVisible, enteredPlanID == plan.id, state.presentedPlanID == plan.id,
                  enteredSessionID == state.panelSessionID else {
                correctionTargetID = snapshot.id
                recordBlockedConfirmation("time_not_presented")
                return
            }
        }
        pendingActionConfirmation = PendingActionConfirmation(snapshot: snapshot, input: input, planID: plan.id,
            generation: preparation.generation, panelSessionID: state.panelSessionID,
            configuration: configuration().revision, source: source, decision: decision)
        state.isPreparingAction = true
        finishPendingConfirmation()
    }

    private func finishPendingConfirmation() {
        guard let pending = pendingActionConfirmation else { return }
        guard acceptsIntentSuggestions, !state.isComposingText, !state.isReadingGettingStarted,
              pending.input.identity == actionInput().identity, pending.input.text == actionInput().text,
              pending.panelSessionID == state.panelSessionID, pending.configuration == configuration().revision,
              let freshSnapshot = registry.executionSnapshot(for: pending.snapshot.id),
              freshSnapshot.configurationIdentity == pending.snapshot.configurationIdentity,
              let preparation = actionExecutor.current, preparation.generation == pending.generation,
              let plan = preparation.status.plan, plan.id == pending.planID else {
            invalidatePreparation()
            renderIntentSuggestion()
            return
        }
        guard plan.isCurrent(at: now(), timeZone: timeZone()) else {
            recordBlockedConfirmation("time_expired")
            invalidatePreparation()
            renderIntentSuggestion()
            return
        }
        guard plan.summary == nil || (panelIsVisible && state.presentedPlanID == plan.id) else {
            cancelPendingConfirmation()
            return
        }
        guard let prepared = actionExecutor.prepared(planID: pending.planID, snapshot: freshSnapshot,
                input: pending.input, panelSessionID: pending.panelSessionID) else { return }
        let operation = recordAttempt(targetKind: .action, targetID: pending.snapshot.id,
                                      decision: pending.decision, source: pending.source)
        cancelPendingConfirmation()
        _ = recognition.finishSuggestion(confirmed: recognition.suggestion?.targetID == pending.snapshot.id)
        submit(freshSnapshot, prepared: prepared, planID: pending.planID, operation: operation)
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
            let binding: String
            let criteria: String?
            switch entry.descriptor.intentHints.modelBinding {
            case .none: binding = "none"; criteria = nil
            case .capture(let value): binding = "capture"; criteria = value
            case .webSearch: binding = "web_search"; criteria = nil
            case .conversation: binding = "conversation"; criteria = nil
            }
            return .init(id: entry.id, localKeywords: entry.descriptor.intentHints.localKeywords,
                         modelBinding: binding, modelCriteria: criteria, isEnabled: entry.isEnabled,
                         availability: availability, unavailableReasonCode: availability == "ready" ? nil : availability,
                         fallbackPriority: entry.descriptor.fallbackPriority)
        }
        let thresholds = Jev.Thresholds.trial
        return try? OperationContext(capturedAt: OperationRecorder.nowMilliseconds(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            ruleVersion: Jev.ruleVersion, requestedModel: Jev.model,
            configuration: .init(localRules: registry.currentUserRules.map { .init(phrase: $0.phrase, targetID: $0.actionID) },
                actions: actions, defaultTargetID: registry.fallbackActionID ?? registry.fallbackSetupActionID,
                recognitionEnabled: configuration().hasAPIKey,
                recognitionQuestion: (try? Jev.ruleDefinitionData()).flatMap { String(data: $0, encoding: .utf8) },
                thresholds: [.init(name: "current_request", value: thresholds.currentRequest),
                             .init(name: "choice_confidence", value: thresholds.choiceConfidence),
                             .init(name: "choice_probability", value: thresholds.choiceProbability)]))
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
        case .userRule: .userRule
        case .localKeyword: .localKeyword
        case .fallback: .fallback
        case .recognition: recognition.suggestion?.recognition.source == .localAppName ? .localApplication : .model
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
        guard let token = captureOperation(.confirmation, userInitiated: true),
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
                textTransform: targetKind == .application || registry.descriptor(for: targetID)?.preservesOriginalText == true
                    ? .unchanged : .trimWhitespaceAndNewlines,
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

    private func recognitionDetails(_ snapshot: IntentRecognition.Snapshot, trace: JevTrace) -> OperationRecognitionDetails {
        var details = trace.operationDetails
        let captureIDs = Set(snapshot.captureOptions.map(\.id))
        details.options.removeAll { $0.question == JevDiagnostics.QuestionID.captureKind.rawValue && !captureIDs.contains($0.id) }
        details.candidates = snapshot.applications.enumerated().map { index, application in
            .init(id: application.id, name: application.name, bundleIdentifier: application.bundleIdentifier,
                  rank: index, match: trace.recognitionSummary.applicationMatch?.rawValue,
                  openCount: snapshot.applicationRanks[application.id]?.openCount,
                  lastOpenedAt: snapshot.applicationRanks[application.id].map { Int64($0.lastOpenedAt.timeIntervalSince1970 * 1000) })
        }
        return details
    }

    private func recordRecognitionStarted(_ snapshot: IntentRecognition.Snapshot, trace: JevTrace) {
        guard !state.isComposingText, snapshot.text == operationText,
              let token = captureOperation(.recognition) else { return }
        recognitionTokens[trace.context.requestID] = (token, RuntimeLog.ticks())
        recordEvent(.recognitionStarted, token: token, requestID: trace.context.requestID.uuidString,
                    details: .recognition(recognitionDetails(snapshot, trace: trace)))
        recorder.markInflight(token, activityID: trace.context.requestID.uuidString, active: true)
        recordPresentedRoute(token: token)
    }

    private func recordRecognitionFinished(_ snapshot: IntentRecognition.Snapshot, trace: JevTrace,
                                           outcome: OperationEventOutcome, action: IntentRecognition.Action?, actualModel: String?) {
        guard let request = recognitionTokens.removeValue(forKey: trace.context.requestID) else { return }
        let token = request.token
        var details = recognitionDetails(snapshot, trace: trace)
        if let actualModel, JevDiagnostics.validModel(actualModel) { details.actualModel = actualModel }
        let target: (OperationTargetKind?, String?) = switch action {
        case .action(let id, _): (.action, id)
        case .openApplication(let id): (.application, id)
        case nil: (nil, nil)
        }
        recordEvent(.recognitionFinished, token: token, requestID: trace.context.requestID.uuidString,
                    targetKind: target.0, targetID: target.1,
                    routeSource: trace.recognitionSummary.source == .localAppName ? .localApplication : .model, outcome: outcome,
                    reason: outcome == .stale ? "stale" : outcome == .cancelled ? "cancelled" : trace.decisionReason.rawValue,
                    duration: Int64(RuntimeLog.milliseconds(since: request.started)), details: .recognition(details))
        recorder.markInflight(token, activityID: trace.context.requestID.uuidString, active: false)
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
        guard let failedSubmission, !state.isComposingText else { return false }
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
