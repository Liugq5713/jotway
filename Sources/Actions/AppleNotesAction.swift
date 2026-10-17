import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class AppleNotesModule: ActionModule {
    nonisolated static let moduleDescriptor = ActionDescriptor(
        id: "apple-notes", title: "Save to Notes", settingsName: "Apple Notes",
        summary: "Save notes and ideas; the fallback when no clearer intent is found.",
        titleKey: "action.notes.title", settingsNameKey: "action.notes.settings_name",
        summaryKey: "action.notes.summary", systemImageName: "note.text", tint: .orange,
        settingsGroup: .init(id: "storage", title: "Save", order: 0, titleKey: "actions.group.storage"),
        enablementPolicy: .alwaysEnabled, fallbackPriority: 0,
        intentHints: IntentHints(localKeywords: ["记一下", "存备忘录", "留个备忘", "记个备忘", "存备忘", "先存",
                                                       "save to notes", "take a note"]),
        presentationPolicy: .returnToPreviousApplication, preservesOriginalText: true,
        preparationTiming: .afterConfirmation, applicationBundleIdentifier: "com.apple.Notes")

    let descriptor = AppleNotesModule.moduleDescriptor
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    let history: NotesHistory
    private let preferences: UserDefaults
    private let run: @MainActor @Sendable (AppleNotes.Request) async throws -> AppleNotes.Response
    let models: ModelConfiguration
    private let groupingStore: NotesDailyGroupingStore
    @ObservationIgnored private lazy var grouping = NotesDailyGroupingCoordinator(store: groupingStore,
        index: history.index, classifier: .capability(generator: models.frozenText(.fast)), run: { [weak self] request in
            guard let self else { throw NotesHistoryError.stale }
            return try await self.perform(request)
        })
    private var groupingRevision = 0
    private var refreshRevision = 0
    private(set) var destination: AppleNotes.Destination?
    private(set) var repairFailure: ActionFailure?
    private(set) var configurationRevision = 0

    init(preferences: UserDefaults,
         models suppliedModels: ModelConfiguration? = nil,
         groupingStore: NotesDailyGroupingStore? = nil,
         history: NotesHistory? = nil,
         run: @escaping @MainActor @Sendable (AppleNotes.Request) async throws -> AppleNotes.Response = {
             try await AppleNotes.run($0)
         }) {
        let models = suppliedModels ?? ModelConfiguration(preferences: preferences)
        self.models = models
        self.history = history ?? NotesHistory(preferences: preferences, models: models, reader: .init(run: run))
        self.preferences = preferences
        self.groupingStore = groupingStore ?? NotesDailyGroupingStore(
            url: StorageLocation.appSupport.appendingPathComponent("notes-daily-grouping.sqlite"))
        self.run = run
        destination = preferences.data(forKey: "notesDestination")
            .flatMap { try? JSONDecoder().decode(AppleNotes.Destination.self, from: $0) }
        self.history.onChange = { [weak self] in self?.changed() }
        self.history.onAuthorized = { [weak self] in
            guard let self, repairFailure?.osStatus == -1743 else { return }
            repairFailure = nil
            changed()
        }
        observeModels()
        self.history.onPermissionDenied = { [weak self] in
            self?.repairFailure = ActionFailure(localized: "error.notes.automation_denied", code: .configuration, osStatus: -1743)
            self?.changed()
        }
    }

    private func observeModels() {
        withObservationTracking { _ = models.version(.fast); _ = models.version(.deep) } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshRevision &+= 1
                self.grouping.cancelRefreshes(); self.grouping.cancelTitles()
                self.refreshAvailability(); self.changed(); self.observeModels()
            }
        }
    }

    var state: ActionModuleState {
        .init(configurationRevision: configurationRevision,
              availability: repairFailure.map { .needsConfiguration(message: $0.localizedDescription) }
                  ?? (destination == nil
                      ? .needsConfiguration(message: L10n.text("action.state.select_notes")) : .ready),
              summary: destination.map { L10n.text("action.state.save_to", $0.name) }
                  ?? L10n.text("action.state.no_destination"),
              hasSavedConfiguration: ["notesDestination", "notesTag", "notesAITagsEnabled",
                                      "aiRewriteEnabled.\(descriptor.id)", "aiRewritePrompt.\(descriptor.id)",
                                      "notesSupplementPrompt", "notesDailyGroupingEnabled"]
                  .contains { preferences.object(forKey: $0) != nil })
    }

    var settings: ActionSettings? {
        ActionSettings { [unowned self] in AnyView(AppleNotesSettingsView(module: self)) }
    }

    var setup: ActionSetup? {
        let lifetime = AppleNotesSetupLifetime()
        return ActionSetup(title: L10n.text("action.notes.setup.action_title"),
                           invalidate: { lifetime.invalidate() }) { [self] onFinish in
            AnyView(AppleNotesSetupView(module: self, lifetime: lifetime, onFinish: onFinish))
        }
    }

    func refreshAvailability() {
        guard let folderID = destination?.id else { return }
        let configuration = groupingConfiguration(folderID: folderID)
        grouping.startTitles(folderID: folderID, configuration: configuration)
        guard isDailyGroupingEnabled, isAISupplementEnabled, hasGroupingConfiguration else { return }
        Task { [grouping] in await grouping.resume(folderID: folderID, configuration: configuration) }
    }

    func makeAction() -> any LauncherAction {
        let destinationID = destination?.id
        let retriever = isAISupplementEnabled ? history.snapshot() : nil
        let generation = history.generation
        let validate: @Sendable () async throws -> Void = { [weak self] in
            try Task.checkCancellation()
            guard let self else { throw NotesHistoryError.stale }
            // Once submitted, preference and index updates must not prevent saving the frozen
            // original. Changing the actual destination still invalidates the pending write.
            guard await self.destination?.id == destinationID else { throw NotesHistoryError.stale }
        }
        let validateHistory: @Sendable () async throws -> Void = { [weak self] in
            try await validate()
            guard let self else { throw NotesHistoryError.stale }
            if let retriever { try await self.history.validate(version: retriever.version, generation: generation) }
            try await validate()
        }
        var action = AppleNotesAction(descriptor: descriptor, destination: destination,
            processor: notesSupplementProcessor(preferences: preferences, frozen: models.frozenText(.deep), id: descriptor.id, retriever: retriever,
                historyUnavailable: history.enabled ? .unavailable : .disabled, validate: validateHistory),
            run: { [self] request in
                try await perform(request)
            })
        action.originIndex = history.index
        action.validate = validate
        if let destinationID {
            let configuration = groupingConfiguration(folderID: destinationID)
            if isDailyGroupingEnabled {
                action.groupingSave = { [grouping] original, entryID, submittedAt in
                    try await grouping.save(original: original, entryID: entryID, folderID: destinationID,
                                            submittedAt: submittedAt, configuration: configuration)
                }
            }
            action.independentSave = { [grouping] original, entryID, submittedAt, supplement in
                try await grouping.saveIndependent(original: original, entryID: entryID, folderID: destinationID,
                    submittedAt: submittedAt, supplement: supplement, configuration: configuration)
            }
        }
        return action
    }

    // Retain the existing switch, including its default, without migrating or executing old styles.
    var isAISupplementEnabled: Bool { enabledPreference("aiRewriteEnabled.\(descriptor.id)") }
    var isDailyGroupingEnabled: Bool { enabledPreference("notesDailyGroupingEnabled") }
    var isReviewEnabled: Bool { enabledPreference("notesReview.enabled") }
    var hasGroupingConfiguration: Bool { (try? models.textConfiguration(.fast)) != nil }

    func setDailyGroupingEnabled(_ enabled: Bool) {
        preferences.set(enabled, forKey: "notesDailyGroupingEnabled")
        groupingRevision &+= 1
        refreshRevision &+= 1
        grouping.invalidateCandidates()
        grouping.cancelRefreshes()
        changed()
    }

    func saveGroupingKey(_ key: String) throws {
        guard let source = models.source(for: models.binding(.fast).primary, capability: .fast) else {
            throw AIProviderPlugin.Failure(message: "Selected model is unavailable", runtimeLogCode: .configuration)
        }
        try models.saveSourceKey(key, source: source)
        refreshRevision &+= 1
        grouping.cancelRefreshes()
        changed()
    }

    private func groupingConfiguration(folderID: String) -> NotesDailyGroupingCoordinator.Configuration {
        let frozenDeep = models.frozenText(.deep)
        let expectedGrouping = groupingRevision
        let expectedRefresh = refreshRevision
        let expectedHistory = history.generation
        let original: @MainActor @Sendable () throws -> Void = { [weak self] in
            try Task.checkCancellation()
            guard let self, self.destination?.id == folderID else { throw NotesHistoryError.stale }
        }
        let refresh: @MainActor @Sendable () throws -> Void = { [weak self] in
            try original()
            guard let self, self.isDailyGroupingEnabled, self.groupingRevision == expectedGrouping,
                  self.isAISupplementEnabled, self.refreshRevision == expectedRefresh,
                  self.history.generation == expectedHistory else { throw NotesHistoryError.stale }
        }
        let expectedTitle = models.version(.fast)
        let validateTitle: @MainActor @Sendable () throws -> Void = { [weak self] in
            try original()
            guard let self, self.models.version(.fast) == expectedTitle else { throw NotesHistoryError.stale }
        }
        let frozenTitle: ModelTextInvocation
        do { frozenTitle = try models.text(.fast) }
        catch {
            frozenTitle = .init(version: expectedTitle) { _, _ in
                throw AIProviderPlugin.Failure(message: "Initial title model is not configured", runtimeLogCode: .configuration)
            }
        }
        let titleGenerator = NotesInitialTitleGenerator(invocation: frozenTitle.validating {
            try await validateTitle()
        })
        return .init(supplementsEnabled: isAISupplementEnabled, classifier: .capability(generator: models.frozenText(.fast)),
                     titleGenerator: titleGenerator, validateTitle: validateTitle, validateOriginal: original,
                     validateRefresh: refresh, processor: { [weak self] document, noteID in
            try refresh()
            guard let self else { throw NotesHistoryError.stale }
            let retriever = try await self.history.freshSnapshot()
            let validate: @Sendable () async throws -> Void = { [weak self] in
                try await refresh()
                if let retriever, let self {
                    try await self.history.validate(version: retriever.version, generation: expectedHistory)
                }
                try await refresh()
            }
            let processor = notesSupplementProcessor(preferences: self.preferences, frozen: frozenDeep, id: self.descriptor.id,
                retriever: retriever, historyUnavailable: self.history.enabled ? .unavailable : .disabled,
                retrievalQuery: document.retrievalQuery, excludedNoteID: noteID, validate: validate)
            return .init(processor: processor, validate: validate)
        })
    }
    var supplementPrompt: String { preferences.string(forKey: "notesSupplementPrompt") ?? "" }
    var hasLegacyRewritePrompt: Bool {
        preferences.string(forKey: "aiRewritePrompt.\(descriptor.id)")?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
    var notesTag: String { preferences.string(forKey: "notesTag") ?? "Jotway" }
    var isAITagsEnabled: Bool { enabledPreference("notesAITagsEnabled") }

    func setDestination(_ value: AppleNotes.Destination) throws {
        let data = try JSONEncoder().encode(value)
        preferences.set(data, forKey: "notesDestination")
        guard preferences.data(forKey: "notesDestination") == data else {
            throw ActionFailure(localized: "error.destination_save_failed", code: .storage)
        }
        destination = value
        groupingRevision &+= 1
        refreshRevision &+= 1
        grouping.invalidateCandidates()
        grouping.cancelRefreshes()
        grouping.cancelTitles()
        refreshAvailability()
        repairFailure = nil
        changed()
    }

    func loadDestinations() async throws -> [AppleNotes.Destination] {
        let expectedRevision = configurationRevision
        let response = try await perform(.init(requestID: UUID().uuidString, operation: "folders"))
        guard configurationRevision == expectedRevision else {
            throw ActionFailure(localized: "error.notes.configuration_changed", code: .stale)
        }
        guard let folders = response.folders else {
            throw ActionFailure(localized: "error.notes.folders_failed", code: .validation)
        }
        guard !folders.isEmpty else {
            let failure = ActionFailure(localized: "error.notes.no_folders", code: .configuration,
                                        osStatus: response.osStatus)
            repairFailure = failure
            changed()
            throw failure
        }
        if let destination, !folders.contains(where: { $0.id == destination.id }) {
            repairFailure = ActionFailure(localized: "error.notes.destination_missing", code: .configuration)
            changed()
        } else if repairFailure != nil {
            repairFailure = nil
            changed()
        }
        history.refreshAvailability()
        return folders
    }

    func authorizeAndSetDefaultDestination() async throws {
        let folders = try await loadDestinations()
        try Task.checkCancellation()
        // The adapter places Notes' default folder first. Keep a valid user choice.
        guard let value = folders.first(where: { $0.id == destination?.id }) ?? folders.first else {
            throw ActionFailure(localized: "error.notes.no_folders", code: .configuration)
        }
        try setDestination(value)
    }

    private func perform(_ request: AppleNotes.Request) async throws -> AppleNotes.Response {
        try Task.checkCancellation()
        let expectedRevision = configurationRevision
        do {
            let response = try await run(request)
            // A closed setup view cannot apply a late authorization response. A create
            // response must retain its write outcome even if cancellation arrived afterward.
            if !["create", "update"].contains(request.operation) { try Task.checkCancellation() }
            if let failure = AppleNotes.actionFailure(for: response, operation: request.operation) {
                throw failure
            }
            return response
        } catch {
            if !["create", "update"].contains(request.operation) { try Task.checkCancellation() }
            if error is CancellationError { throw error }
            let failure = AppleNotes.actionFailure(for: error, operation: request.operation)
            let missingCurrentDestination = failure.osStatus == -1728
                && request.folderID != nil && request.folderID == destination?.id
            if configurationRevision == expectedRevision,
               failure.osStatus == -1743 || missingCurrentDestination {
                repairFailure = failure
                changed()
            }
            throw failure
        }
    }

    func setAISupplementEnabled(_ enabled: Bool) {
        preferences.set(enabled, forKey: "aiRewriteEnabled.\(descriptor.id)")
        refreshRevision &+= 1
        grouping.cancelRefreshes()
        changed()
    }
    func setSupplementPrompt(_ text: String) {
        let key = "notesSupplementPrompt"
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? preferences.removeObject(forKey: key) : preferences.set(text, forKey: key)
        refreshRevision &+= 1
        grouping.cancelRefreshes()
        changed()
    }
    func setNotesTag(_ raw: String) { preferences.set(cleanActionTag(raw), forKey: "notesTag"); changed() }
    func setAITagsEnabled(_ enabled: Bool) { preferences.set(enabled, forKey: "notesAITagsEnabled"); changed() }
    func setReviewEnabled(_ enabled: Bool) { preferences.set(enabled, forKey: "notesReview.enabled"); changed() }

    private func enabledPreference(_ key: String) -> Bool {
        preferences.object(forKey: key) == nil || preferences.bool(forKey: key)
    }
    private func changed() { configurationRevision &+= 1; onChange?() }
}

/// Notes always keeps the frozen original draft; the processor can only provide appended material.
struct AppleNotesAction: LauncherAction {
    let descriptor: ActionDescriptor
    let destination: AppleNotes.Destination?
    let processor: any NotesSupplementProcessor
    /// Retained for callers with saved tag preferences; tag appending is paused.
    let tag: String?
    var originIndex: NotesIndex?
    var supplementTimeout: Duration = .seconds(300)
    var groupingSave: (@MainActor @Sendable (String, String, Date) async throws -> ActionOutcome)? = nil
    var independentSave: (@MainActor @Sendable (String, String, Date, NotesSupplement) async throws -> ActionOutcome)? = nil
    var validate: @Sendable () async throws -> Void = { try Task.checkCancellation() }
    let run: @MainActor @Sendable (AppleNotes.Request) async throws -> AppleNotes.Response

    init(descriptor: ActionDescriptor = AppleNotesModule.moduleDescriptor,
         destination: AppleNotes.Destination?,
         processor: any NotesSupplementProcessor = NoNotesSupplementProcessor(),
         tag: String? = nil,
         run: @escaping @MainActor @Sendable (AppleNotes.Request) async throws -> AppleNotes.Response
             = { try await AppleNotes.run($0) }) {
        self.descriptor = descriptor
        self.destination = destination
        self.processor = processor
        self.tag = tag
        self.run = run
    }

    func prepare(_ input: ActionInput) async throws -> PreparedAction {
        try Task.checkCancellation()
        let original = input.originalText
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ActionFailure(localized: "error.notes.empty", code: .validation)
        }
        guard let destination else {
            throw ActionFailure(localized: "error.notes.choose_destination", code: .configuration)
        }
        if let groupingSave {
            let submittedAt = Date()
            // Restoring a failed draft advances the editor revision but preserves its lineage.
            // Only a changed original or a distinct draft is a distinct Notes submission.
            let entryID = input.identity.draftID.uuidString + ":"
                + NotesDailyBoundary.hash(NotesDailyBoundary.normalizedLines(original))
            return PreparedAction(actionID: descriptor.id, inputIdentity: input.identity) {
                try await groupingSave(original, entryID, submittedAt)
            }
        }
        var log = RuntimeLog.current ?? RuntimeLog.Context()
        log.module = .ai
        log.purpose = .supplement
        let started = RuntimeLog.ticks()
        let result: NotesSupplementResult
        do {
            result = try await RuntimeLog.$current.withValue(log) {
                try await processor.process(original, timeout: supplementTimeout)
            }
        } catch {
            let code = RuntimeLog.code(error)
            let skipped = NotesSupplementResult.empty(code == .stale ? .stale : (code == .cancelled ? .cancelled : .providerError))
            log.emit(.stageFinished, .init(stage: .notesPreparation, outcome: skipped.outcome,
                durationMs: RuntimeLog.milliseconds(since: started), actionID: "apple-notes", notes: skipped.report))
            // Only cancellation of the submission stops saving; optional cancellation skips assistance.
            try Task.checkCancellation()
            return try await prepared(original: original, input: input, destination: destination, result: skipped, log: log)
        }
        log.emit(.stageFinished, .init(stage: .notesPreparation, outcome: result.outcome,
            durationMs: RuntimeLog.milliseconds(since: started), actionID: "apple-notes", notes: result.report))
        try Task.checkCancellation()
        return try await prepared(original: original, input: input, destination: destination, result: result, log: log)
    }

    private func prepared(original: String, input: ActionInput, destination: AppleNotes.Destination,
                          result: NotesSupplementResult, log: RuntimeLog.Context) async throws -> PreparedAction {
        try await validate()
        if let independentSave {
            let entryID = input.identity.draftID.uuidString + ":" + NotesDailyBoundary.hash(NotesDailyBoundary.normalizedLines(original))
            let submittedAt = Date()
            return PreparedAction(actionID: descriptor.id, inputIdentity: input.identity) {
                try await independentSave(original, entryID, submittedAt, result.supplement)
            }
        }
        let requestID = UUID().uuidString
        return PreparedAction(actionID: descriptor.id, inputIdentity: input.identity) {
            try Task.checkCancellation()
            var originToken: String?
            var invokedCreate = false
            do {
                try await validate()
                let entry = NotesDailyGroupingStore.Entry(id: input.identity.draftID.uuidString,
                    submittedAt: Date(), timeZoneID: TimeZone.current.identifier, sequence: 0)
                let document = NotesDailyDocument(title: NotesInitialTitleGenerator.placeholder(for: original),
                    scope: .current(folderID: destination.id), entries: [.init(identity: entry, text: original)], layout: .independent)
                var rendered = document.render(supplement: result.supplement)
                var content = rendered.content
                var report = result.report
                if let originIndex {
                    do { originToken = try await originIndex.stageDailyOrigin(noteID: nil, boundary: rendered.boundary) }
                    catch {
                        // If provenance cannot be persisted, save only the original: generated
                        // material must never depend on an unrecorded post-write callback.
                        rendered = document.render()
                        content = rendered.content
                        report.adoption = .provenanceUnavailable
                    }
                }
                try Task.checkCancellation()
                try await validate()
                let request = AppleNotes.Request(requestID: requestID, operation: "create", folderID: destination.id,
                    html: content.html, validateBeforeSend: validate)
                report.adoptedItemCount = content.itemCount
                report.adoptedHistoryCount = content.historyCount
                if report.adoption == nil {
                    report.adoption = (content.itemCount != result.supplement.items.count || content.historyCount != result.supplement.history.count)
                        ? .renderFiltered : (content.itemCount + content.historyCount == 0 ? .empty : .applied)
                }
                log.emit(.stageFinished, .init(stage: .notesAdoption,
                    outcome: report.adoption == .provenanceUnavailable || report.adoption == .renderFiltered ? .discarded : .success,
                    actionID: "apple-notes",
                    notes: report, externalRequestID: UUID(uuidString: requestID)))
                invokedCreate = true
                let response = try await run(request)
                if let failure = AppleNotes.actionFailure(for: response, operation: request.operation) {
                    throw failure
                }
                guard response.noteID?.isEmpty == false else {
                    throw ActionFailure(localized: "error.notes.save_failed",
                                        code: .processFailed, osStatus: response.osStatus, executionOutcome: .unknown)
                }
                if let originToken, let noteID = response.noteID {
                    // Retain the pending fingerprint if confirmation persistence fails.
                    try? await originIndex?.confirmDailyOrigin(token: originToken, noteID: noteID)
                }
                return ActionOutcome(messageKey: "result.notes.saved", effect: .created,
                                     showsCompletionNotice: true, savedNoteID: response.noteID)
            } catch {
                let failure = AppleNotes.actionFailure(for: error, operation: "create")
                // The adapter only throws cancellation/staleness before sending create;
                // after dispatch it must return a confirmed or explicitly uncertain outcome.
                if let originToken, !invokedCreate || error is CancellationError
                    || failure.executionOutcome == .failed {
                    try? await originIndex?.discardDailyOrigin(token: originToken)
                }
                if error is CancellationError { throw error }
                if case NotesHistoryError.stale = error {
                    throw ActionFailure(localized: "error.notes.configuration_changed", code: .stale)
                }
                throw failure
            }
        }
    }
}
