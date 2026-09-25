import Foundation

enum LauncherEvent {
    case inputChanged(String)
    case panelPrepared(quote: String?)
    case panelPresented
    case panelDismissed
    case compositionChanged(Bool)
    case confirm(IntentRecognition.ConfirmationSource)
    case cycleTarget(forward: Bool)
    case selectTarget(String)
    case candidateMenuChanged(Bool)
    case readingGettingStartedChanged(Bool)
    case externalFocusChanged
    case refreshConfiguration
    case preserveDraft
    case cancel
    case preloadApplications
    case cancelApplicationPreload
    case restoreFailedSubmission
    case actionSetupFinished(UUID, ActionSetupResult)
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
    case openApplication(URL, @MainActor (Result<Void, Error>) -> Void)
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
        if case .openApplication(_, let completion) = effect {
            completion(.failure(NSError(domain: "Jotway.Launcher", code: 1,
                userInfo: [NSLocalizedDescriptionKey: L10n.text("launcher.open_unavailable")])))
        }
        return true
    }

    private let repository: LauncherStore
    private let registry: ActionRegistry
    private let feedback: IntentFeedbackStore
    private let storageAvailable: () -> Bool
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
    private var explicitTargetID: String?
    private var explicitTargetIdentity: ActionInput.Identity?
    private struct PendingSetup {
        let request: ActionSetupRequest
        let identity: ActionInput.Identity
        let panelSession: Int
    }
    private var pendingSetup: PendingSetup?
    private(set) var failedSubmission: FailedSubmission?

    private let actionExecutor = ActionExecutor()
    private lazy var recognition = IntentRecognition(
        readKey: readKey, recognize: recognize,
        isCurrent: { [weak self] in self?.currentIntentSnapshot == $0 },
        changed: { [weak self] in self?.renderIntentSuggestion() })

    init(repository: LauncherStore, registry: ActionRegistry, feedback: IntentFeedbackStore,
         catalog: ApplicationCatalog,
         storageAvailable: @escaping () -> Bool,
         configuration: @escaping () -> Configuration,
         readKey: @escaping @MainActor @Sendable () throws -> String?,
         recognize: @escaping IntentRecognition.Recognize,
         applicationUsage: @escaping () -> [String: ApplicationUsage],
         recordApplicationOpen: @escaping (URL) -> Bool) {
        self.repository = repository
        self.registry = registry
        self.feedback = feedback
        self.catalog = catalog
        self.storageAvailable = storageAvailable
        self.configuration = configuration
        self.readKey = readKey
        self.recognize = recognize
        self.applicationUsage = applicationUsage
        self.recordApplicationOpen = recordApplicationOpen
        catalog.changed = { [weak self] in
            guard let self else { return }
            self.refresh()
        }
    }

    isolated deinit {
        recognizingHintTask?.cancel()
        // 已提交的外部写入不随窗口隐藏或会话释放而取消。
    }

    var hasUnsavedChanges: Bool { revision != savedRevision }

    func send(_ event: LauncherEvent) {
        state.lastEventSucceeded = true
        switch event {
        case .inputChanged(let text): updateInput(text)
        case .panelPrepared(let quote): state.lastEventSucceeded = prepare(quote: quote)
        case .panelPresented: activate()
        case .panelDismissed: panelClosed()
        case .compositionChanged(let composing):
            state.isComposingText = composing
            if !composing { refresh() }
        case .confirm(let source): confirm(source)
        case .cycleTarget(let forward): cycleTarget(forward: forward)
        case .selectTarget(let id): selectTarget(id: id)
        case .candidateMenuChanged(let visible):
            state.isIntentCandidateMenuVisible = visible
            refresh()
        case .readingGettingStartedChanged(let reading):
            state.isReadingGettingStarted = reading
            if reading { suspend() } else { refresh() }
        case .externalFocusChanged: suspend()
        case .refreshConfiguration: refresh()
        case .preserveDraft: state.lastEventSucceeded = preserveDraft()
        case .cancel: cancel()
        case .preloadApplications: preloadApplications()
        case .cancelApplicationPreload: cancelApplicationPreload()
        case .restoreFailedSubmission: state.lastEventSucceeded = restoreFailedSubmission()
        case .actionSetupFinished(let id, let result): finishSetup(id: id, result: result)
        }
    }

    func updateInput(_ text: String) {
        guard !isReplacingEditor else { return }
        if draft.content != text {
            invalidateSetup()
            draft.content = text
            revision += 1
            clearExplicitTarget()
        }
        synchronizeDraftState()
        refresh()
    }

    /// 开始一次面板展示；草稿始终来自会话，剪贴板内容只是一次输入。
    @discardableResult
    func prepare(quote: String? = nil) -> Bool {
        guard !state.isComposingText else { return false }
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
        recognition.update(nil)
        cancelRecognizingHint()
    }

    func panelClosed() {
        invalidateSetup()
        suspend()
        clearExplicitTarget()
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
        if let pendingSetup {
            _ = handleEffect(.closeActionSetup(pendingSetup.request.id))
            finishSetup(id: pendingSetup.request.id, result: .cancelled)
            return
        }
        guard preserveDraft() else {
            state.lastEventSucceeded = false
            return
        }
        clearExplicitTarget()
        suspend()
        _ = handleEffect(.hidePanel(submitted: false, presentationPolicy: .returnToPreviousApplication))
    }

    func refresh() {
        guard !isReplacingEditor else { return }
        registry.refreshAvailability()
        if let pendingSetup, !registry.containsModule(id: pendingSetup.request.snapshot.id,
                                                      instance: pendingSetup.request.snapshot.moduleInstance) {
            invalidateSetup()
        }
        state.isIntentRecognitionEnabled = true
        if configuration().hasAPIKey, acceptsIntentSuggestions, hasPreparedDraft,
           catalog.applications == nil, !catalog.isLoading {
            catalog.preload()
        }
        recognition.update(currentIntentSnapshot)
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
            webSearchActionID: webSearchActionID)
    }

    /// 展示、预览和提交每次都消费同一个值类型决策。
    private var routeDecision: RouteDecision {
        let snapshot = currentIntentSnapshot
        let identity = ActionInput.Identity(draftID: draft.id, revision: revision)
        let selectedID = explicitTargetIdentity == identity ? explicitTargetID : nil
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
        let explicitID = explicitTargetIdentity == actionInput().identity ? explicitTargetID : nil
        let selectedID = explicitID ?? routeTargetID
        state.intentTitle = selectedID.flatMap(targetTitle) ?? recognition.suggestion?.title
        state.intentCanCycle = candidates.contains { $0.id != routeTargetID }
        state.intentDeviated = explicitID != nil
        let issue = recognition.issue
        state.intentIssue = issue == JevDiagnostics.Reason.missingKey.userMessage ? nil : issue
        state.intentCandidates = candidates.map {
            IntentCandidate(id: $0.id, title: $0.title, isSelected: $0.id == selectedID)
        }
        if !state.intentCanCycle { state.isIntentCandidateMenuVisible = false }
        guard case .empty = decision else {
            render(decision)
            return
        }
        state.displayedActionTitle = nil
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
            actionExecutor.schedule(snapshot: snapshot, input: actionInput())
        case .application(let id, _):
            let application = currentIntentSnapshot?.applications.first { $0.id == id }
            state.displayedActionTitle = application.map { L10n.text("launcher.open_application", $0.name) }
            actionExecutor.reset()
        case .setup(let id, _):
            state.displayedActionTitle = registry.setupSnapshot(for: id)?.setup.title
            actionExecutor.reset()
        case .unavailable, .empty:
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
        guard currentIntentSnapshot != nil else { return [] }
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
        if explicitTargetIdentity == actionInput().identity, let explicitTargetID,
           !values.contains(where: { $0.0 == explicitTargetID }) {
            append(explicitTargetID, targetTitle(explicitTargetID) ?? L10n.text("launcher.target_unavailable"))
        }
        return values
    }

    private func targetTitle(_ id: String) -> String? {
        if let snapshot = registry.setupSnapshot(for: id) { return snapshot.setup.title }
        if let descriptor = registry.descriptor(for: id) { return descriptor.localizedTitle }
        return currentIntentSnapshot?.applications.first(where: { $0.id == id })
            .map { L10n.text("launcher.open_application", $0.name) }
    }

    func cycleTarget(forward: Bool) {
        let candidates = makeIntentCandidates()
        guard !candidates.isEmpty else { return }
        let current = routeDecision.targetID
        let nextIndex: Int
        if let index = candidates.firstIndex(where: { $0.id == current }) {
            nextIndex = ((index + (forward ? 1 : -1)) % candidates.count + candidates.count) % candidates.count
        } else {
            nextIndex = forward ? 0 : candidates.count - 1
        }
        selectTarget(id: candidates[nextIndex].id)
    }

    func selectTarget(id: String) {
        guard makeIntentCandidates().contains(where: { $0.id == id }) else { return }
        explicitTargetID = id
        explicitTargetIdentity = actionInput().identity
        renderIntentSuggestion()
    }

    func confirm(_ source: IntentRecognition.ConfirmationSource) {
        guard hasPreparedDraft, acceptsIntentSuggestions, !isSubmitting,
              pendingSetup == nil,
              !state.isOpeningApplication, !state.isComposingText,
              !state.isReadingGettingStarted else { return }
        if draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard clearDraft() else { return }
            suspend()
            _ = handleEffect(.hidePanel(submitted: false, presentationPolicy: .returnToPreviousApplication))
            return
        }
        registry.refreshAvailability()
        guard let intentSnapshot = currentIntentSnapshot else { return }
        let resolved = routeDecision
        let suggestion = recognition.suggestion.flatMap { $0.snapshot == intentSnapshot ? $0 : nil }
        let acceptsSuggestion: Bool = switch resolved {
        case .action(let id, let routeSource), .application(let id, let routeSource):
            (routeSource == .recognition || routeSource == .explicit) && suggestion?.targetID == id
        case .setup, .unavailable, .empty: false
        }
        func finishFeedback() -> UUID? {
            if let suggestion, resolved.source == .explicit, suggestion.targetID != resolved.targetID,
               case .action = suggestion.action, let chosenID = resolved.targetID {
                recordCorrection(suggestion: suggestion, chosenTargetID: chosenID)
            }
            let consumed = recognition.finishSuggestion(confirmed: acceptsSuggestion)
            return acceptsSuggestion ? consumed.flatMap { recordFeedback($0, source: source) } : nil
        }
        switch resolved {
        case .setup(let id, _):
            guard let snapshot = registry.setupSnapshot(for: id) else { return }
            beginSetup(snapshot)
        case .action(let id, _):
            guard let snapshot = registry.executionSnapshot(for: id) else {
                state.message = L10n.text("launcher.action_unavailable")
                return
            }
            _ = finishFeedback()
            submit(snapshot)
        case .application(let id, _):
            guard let application = intentSnapshot.applications.first(where: { $0.id == id }) else {
                state.message = L10n.text("launcher.application_unavailable")
                return
            }
            guard canLaunch(application, snapshot: intentSnapshot) else {
                state.message = L10n.text("launcher.application_unavailable")
                return
            }
            let feedbackID = finishFeedback()
            launchSuggestedApplication(application, snapshot: intentSnapshot, feedbackID: feedbackID)
        case .unavailable(.targetUnavailable(let id), _):
            state.message = registry.settingsEntry(for: id)?.state.availability.message
                ?? L10n.text("launcher.target_unavailable")
        case .unavailable(.noDefaultAction, _), .empty:
            state.message = L10n.text("launcher.no_default_action")
        }
    }

    private func beginSetup(_ snapshot: ActionSetupSnapshot) {
        guard pendingSetup == nil else { return }
        let request = ActionSetupRequest(id: UUID(), snapshot: snapshot)
        pendingSetup = PendingSetup(request: request, identity: actionInput().identity,
                                    panelSession: panelSession)
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
        pending.request.snapshot.setup.invalidate()
        pendingSetup = nil
        state.isConfiguringAction = false
        guard pending.identity == actionInput().identity, pending.panelSession == panelSession,
              !state.isComposingText,
              registry.containsModule(id: pending.request.snapshot.id,
                                      instance: pending.request.snapshot.moduleInstance) else { return }
        if result == .completed, registry.executionSnapshot(for: pending.request.snapshot.id) != nil {
            explicitTargetID = pending.request.snapshot.id
            explicitTargetIdentity = pending.identity
        }
        activate()
        _ = handleEffect(.restoreEditorAfterSetup)
    }

    private func invalidateSetup() {
        guard let pending = pendingSetup else { return }
        pendingSetup = nil
        state.isConfiguringAction = false
        pending.request.snapshot.setup.invalidate()
        _ = handleEffect(.closeActionSetup(pending.request.id))
    }

    private func recordCorrection(suggestion: IntentRecognition.Suggestion, chosenTargetID: String) {
        let snapshot = suggestion.snapshot
        let correction = IntentCorrection(text: snapshot.text,
            jevTargetID: suggestion.targetID, jevLabel: suggestion.targetID,
            chosenTargetID: chosenTargetID,
            chosenLabel: chosenTargetID,
            recognition: suggestion.recognition)
        feedback.recordCorrection(correction, storageAvailable: storageAvailable())
    }

    private func recordFeedback(_ suggestion: IntentRecognition.Suggestion,
                                source: IntentRecognition.ConfirmationSource) -> UUID? {
        let confirmation: IntentFeedback.ConfirmationSource? = switch source {
        case .enter: .enter
        case .commandEnter: .commandEnter
        case .button: nil
        }
        guard let confirmation else { return nil }
        let sample = suggestion.feedback(confirmationSource: confirmation)
        feedback.record(sample, storageAvailable: storageAvailable())
        return sample.id
    }

    private func submit(_ snapshot: ActionExecutionSnapshot) {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let submitted = draft
        let input = actionInput()
        clearExplicitTarget()
        suspend()
        _ = handleEffect(.prepareSubmission)
        guard clearDraft() else {
            _ = handleEffect(.cancelSubmission)
            activate()
            return
        }
        let execution = actionExecutor.executionTask(snapshot: snapshot, input: input)
        let emptyDraftID = draft.id
        let emptyRevision = revision
        let requestID = UUID()
        var log = RuntimeLog.Context()
        log.module = .app
        log.operation = .action
        log.emit(.requestStarted, .init(bytes: input.text.utf8.count, actionID: snapshot.id))
        _ = handleEffect(.hidePanel(submitted: true,
            presentationPolicy: snapshot.descriptor.presentationPolicy))
        activeSubmissionCount += 1
        submissions[requestID] = Task { [weak self] in
            do {
                let outcome = try await execution.value
                self?.applicationNotice = outcome.localizedMessage
                log.emit(.requestFinished, .init(outcome: .success, actionID: snapshot.id))
            } catch {
                let failure = ActionFailure.presentation(for: error)
                log.emit(.requestFinished, .init(outcome: .failed, errorCode: failure.code,
                    osStatus: failure.osStatus, actionID: snapshot.id))
                self?.restoreAfterFailure(submitted, emptyDraftID: emptyDraftID,
                    emptyRevision: emptyRevision, message: failure.message)
            }
            self?.submissions.removeValue(forKey: requestID)
            self?.activeSubmissionCount -= 1
        }
    }

    private func restoreAfterFailure(_ submitted: RecordDraft,
                                     emptyDraftID: UUID, emptyRevision: Int, message: String) {
        guard !state.isComposingText, draft.id == emptyDraftID, revision == emptyRevision else {
            failedSubmission = FailedSubmission(draft: submitted, message: message)
            state.hasFailedSubmission = true
            state.message = message
            return
        }
        guard replaceText(submitted.content, reason: .restoreDraft) else {
            state.message = message
            return
        }
        draft.id = submitted.id
        savedRevision = revision
        synchronizeDraftState()
        failedSubmission = nil
        state.hasFailedSubmission = false
        applicationNotice = message
        _ = handleEffect(.showPanel)
        state.message = message
    }

    private func canLaunch(_ application: IntentRecognition.Application, snapshot: IntentRecognition.Snapshot) -> Bool {
        currentIntentSnapshot == snapshot && applicationOpenID == nil
            && ApplicationCatalog.isLaunchable(application.url, bundleIdentifier: application.bundleIdentifier)
    }

    private func launchSuggestedApplication(_ application: IntentRecognition.Application,
                                            snapshot: IntentRecognition.Snapshot, feedbackID: UUID?) {
        guard canLaunch(application, snapshot: snapshot), preserveDraft() else { return }
        let requestID = UUID()
        applicationOpenID = requestID
        state.isOpeningApplication = true
        suspend()
        _ = handleEffect(.hideForApplicationLaunch)
        let feedback = feedback
        feedback.execution(feedbackID, .init(outcome: .requested, requestID: requestID))
        _ = handleEffect(.openApplication(application.url, { [weak self] result in
            let outcome: IntentFeedback.Execution.Outcome
            switch result { case .success: outcome = .opened; case .failure: outcome = .failed }
            feedback.execution(feedbackID, .init(outcome: outcome, requestID: requestID, finished: true))
            guard let self, self.applicationOpenID == requestID else { return }
            self.applicationOpenID = nil
            let ownsInput = self.draft.id == snapshot.draftID && self.revision == snapshot.revision
                && self.panelSession == snapshot.panelSession && self.draft.content == snapshot.text
                && !self.state.isComposingText
            switch result {
            case .failure:
                if ownsInput {
                    self.applicationNotice = L10n.text("launcher.open_failed_preserved", application.name)
                }
            case .success:
                _ = self.recordApplicationOpen(application.url)
                if ownsInput, IntentRecognition.isPureApplicationLaunch(snapshot.text, application: application,
                                                                       ranks: snapshot.applicationRanks) {
                    if !self.clearDraft() {
                        self.applicationNotice = L10n.text("launcher.opened_clear_failed")
                    }
                }
            }
            self.state.isOpeningApplication = false
        }))
    }

    @discardableResult
    private func clearDraft() -> Bool {
        guard !state.isComposingText else { return false }
        // 先确认原生编辑器接受替换；失败时不动逻辑草稿。
        guard replaceText("", reason: .newDraft) else { return false }
        draft = RecordDraft()
        revision += 1
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
            draft.content = text
            revision += 1
            clearExplicitTarget()
        }
        synchronizeDraftState()
        return true
    }

    private func synchronizeDraftState() {
        state.draftContent = draft.content
        state.hasPreparedDraft = hasPreparedDraft
        state.hasUnsavedChanges = hasUnsavedChanges
    }

    private func actionInput() -> ActionInput {
        ActionInput(identity: .init(draftID: draft.id, revision: revision),
                    text: draft.content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func clearExplicitTarget() {
        explicitTargetID = nil
        explicitTargetIdentity = nil
    }

    @discardableResult
    private func restoreFailedSubmission() -> Bool {
        guard let failedSubmission, !state.isComposingText else { return false }
        let content = draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? failedSubmission.draft.content
            : draft.content + "\n\n" + failedSubmission.draft.content
        guard replaceText(content, reason: .restoreDraft) else { return false }
        self.failedSubmission = nil
        state.hasFailedSubmission = false
        state.message = failedSubmission.message
        return true
    }
}

struct FailedSubmission: Sendable, Equatable {
    let draft: RecordDraft
    let message: String
}
