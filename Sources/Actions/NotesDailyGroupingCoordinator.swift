import Foundation

/// One module-owned FIFO serializes original saves and refresh writes across suspension points.
/// Generation runs outside this FIFO; only its latest still-valid version may reenter to write.
@MainActor
final class NotesDailyGroupingCoordinator {
    typealias Run = @MainActor @Sendable (AppleNotes.Request) async throws -> AppleNotes.Response
    struct RefreshWork: Sendable {
        let processor: any NotesSupplementProcessor
        var validate: @Sendable () async throws -> Void = { try Task.checkCancellation() }
    }
    typealias Processor = @MainActor @Sendable (NotesDailyDocument, String) async throws -> RefreshWork
    private enum SaveError: Error { case metadataUnavailable, preparationInvalidated }
    struct Configuration: Sendable {
        let supplementsEnabled: Bool
        var classifier: NotesGroupingClassifier? = nil
        var titleGenerator: NotesInitialTitleGenerator? = nil
        var validateTitle: @MainActor @Sendable () throws -> Void = { try Task.checkCancellation() }
        let validateOriginal: @MainActor @Sendable () throws -> Void
        let validateRefresh: @MainActor @Sendable () throws -> Void
        let processor: Processor
    }
    private let store: NotesDailyGroupingStore
    private let index: NotesIndex
    private let classifier: NotesGroupingClassifier
    private let run: Run
    private let now: @MainActor @Sendable () -> Date
    private let timeZone: @MainActor @Sendable () -> TimeZone
    private let refreshTimeout: Duration
    private let groupingTimeout: Duration
    private let classificationTimeout: Duration
    private let cacheBudget: Int
    private var cacheScope: NotesDailyScope?
    private var generation: UInt64 = 0
    private var cache: [String: (candidate: Candidate, used: UInt64, bytes: Int)] = [:]
    private var cacheBytes = 0
    private var access: UInt64 = 0
    private var tail: Task<Void, Never>?
    private var refreshes: [String: (id: UUID, task: Task<Void, Never>)] = [:]
    private var recoveredScopes = Set<String>()
    private var titleTail: Task<Void, Never>?
    private var titleWorker: (key: String, id: UUID, task: Task<Void, Never>)?

    init(store: NotesDailyGroupingStore, index: NotesIndex, classifier: NotesGroupingClassifier,
         run: @escaping Run, now: @escaping @MainActor @Sendable () -> Date = { Date() },
         timeZone: @escaping @MainActor @Sendable () -> TimeZone = { .current },
         refreshTimeout: Duration = .seconds(300),
         groupingTimeout: Duration = NotesGroupingClassifier.overallTimeout,
         classificationTimeout: Duration = NotesGroupingClassifier.timeout,
         cacheBudget: Int = 16 * 1024 * 1024) {
        self.store = store
        self.index = index
        self.classifier = classifier
        self.run = run
        self.now = now
        self.timeZone = timeZone
        self.refreshTimeout = min(.seconds(300), max(.zero, refreshTimeout))
        self.groupingTimeout = min(NotesGroupingClassifier.overallTimeout, max(.zero, groupingTimeout))
        self.classificationTimeout = min(NotesGroupingClassifier.timeout, max(.zero, classificationTimeout))
        self.cacheBudget = max(0, cacheBudget)
    }

    func cancelRefreshes() {
        refreshes.values.forEach { $0.task.cancel() }
        refreshes.removeAll()
        recoveredScopes.removeAll()
    }

    func save(original: String, entryID: String, folderID: String, submittedAt: Date,
              configuration: Configuration) async throws -> ActionOutcome {
        let accepted = ContinuousClock.now
        let deadline = accepted.advanced(by: groupingTimeout)
        let preparationDeadline = deadline.advanced(by: .zero - classificationTimeout)
        let started = RuntimeLog.ticks()
        let submittedZone = timeZone().identifier
        let diagnostics = NotesGroupingDiagnostics()
        let log = RuntimeLog.current ?? RuntimeLog.Context()
        defer {
            if let report = diagnostics.finish() {
                log.emit(.stageFinished, .init(stage: .notesGrouping, outcome: report.outcome,
                    actionID: "apple-notes", grouping: report))
            }
        }
        do {
            return try await NotesGroupingDiagnostics.$current.withValue(diagnostics) {
                try await serial { [self] in
                    diagnostics.duration(.queue, since: started)
                    try configuration.validateOriginal()
                    let initialScope = scope(folderID)
                    activateScope(initialScope)
                    do {
                        if try await store.receipt(entryID: entryID) != nil { return await completion(entryID, recovered: true) }
                        _ = try await store.pending(scope: initialScope)
                    } catch {
                        diagnostics.update { $0.reason = .metadata }
                        return try await rawSave(original, folderID: folderID, validate: configuration.validateOriginal)
                    }
                    var preparationFailed = false
                    let preparationStarted = RuntimeLog.ticks()
                    do { try await reconcile(scope: initialScope, deadline: preparationDeadline) }
                    catch is CancellationError { throw CancellationError() }
                    catch {
                        preparationFailed = true
                        diagnostics.update { $0.reason = preparationReason(error) }
                    }
                    diagnostics.duration(.preparation, since: preparationStarted)
                    try configuration.validateOriginal()
                    if try await store.receipt(entryID: entryID) != nil { return await completion(entryID, recovered: true) }
                    // Even a preparation timeout cannot turn an unresolved write into a duplicate.
                    let unresolved = try await store.pending(scope: initialScope)
                    guard !unresolved.contains(where: { $0.snapshot.entries.contains(where: { $0.id == entryID }) })
                    else { throw uncertain() }

                    for attempt in 0..<2 where !preparationFailed {
                        let current = scope(folderID)
                        activateScope(current)
                        let token = generation
                        let candidates: [Candidate]
                        let preparationStarted = RuntimeLog.ticks()
                        do {
                            // Only the initial preparation reserves the full model window.
                            // One cross-day reselection shares the original overall deadline.
                            candidates = try await self.candidates(scope: current,
                                deadline: attempt == 0 ? preparationDeadline : deadline)
                        }
                        catch is CancellationError { throw CancellationError() }
                        catch {
                            diagnostics.duration(.preparation, since: preparationStarted)
                            diagnostics.update { $0.reason = preparationReason(error) }
                            try configuration.validateOriginal()
                            if current != scope(folderID), attempt == 0 {
                                diagnostics.update { $0.reselected = true }
                                continue
                            }
                            break
                        }
                        diagnostics.duration(.preparation, since: preparationStarted)
                        diagnostics.update { $0.candidates = candidates.count }
                        let modelStarted = RuntimeLog.ticks()
                        let remaining = min(classificationTimeout, ContinuousClock.now.duration(to: deadline))
                        let decision: NotesGroupingClassifier.Result
                        if candidates.isEmpty { diagnostics.update { $0.reason = .noCandidates } }
                        decision = try await (configuration.classifier ?? classifier).classify(original, candidates: candidates.map {
                            .init(id: $0.snapshot.groupID, title: $0.document.title, originals: $0.document.entries.map(\.text))
                        }, timeout: max(.zero, remaining))
                        diagnostics.duration(.model, since: modelStarted)
                        diagnostics.update {
                            switch decision.fallback {
                            case .inputTooLarge: $0.reason = .inputBudget
                            case .invalidCandidates, .invalidOutput, .modelMismatch: $0.reason = .invalidOutput
                            case .providerError: $0.reason = .providerError
                            case .configuration: $0.reason = .configuration
                            case .timeout: $0.reason = .modelTimeout
                            case nil: break
                            }
                        }
                        try configuration.validateOriginal()
                        if current != scope(folderID) {
                            if attempt == 0 { diagnostics.update { $0.reselected = true }; continue }
                            break
                        }
                        guard token == generation else { throw SaveError.preparationInvalidated }
                        let selected: Candidate?
                        let title: String?
                        switch decision.decision {
                        case .append(let id):
                            selected = candidates.first { $0.snapshot.groupID == id }
                            title = selected?.document.title
                            diagnostics.update { $0.modelDecision = .append }
                        case .new(let proposed):
                            selected = nil; title = decision.fallback == nil ? proposed : nil
                            diagnostics.update {
                                $0.modelDecision = .new
                                if $0.reason == nil { $0.reason = .semanticNew }
                            }
                        }
                        do {
                            let saved = try await saveManaged(original: original, entryID: entryID, submittedAt: submittedAt,
                                submittedZone: submittedZone, scope: current, title: title, candidate: selected, configuration: configuration)
                            diagnostics.update { $0.savedAs = selected == nil ? .new : .append }
                            scheduleRefresh(saved, configuration: configuration)
                            return await completion(entryID)
                        } catch SaveError.metadataUnavailable {
                            diagnostics.update { $0.reason = .metadata }
                            return try await rawSave(original, folderID: folderID, validate: configuration.validateOriginal)
                        } catch let failure as ActionFailure where selected != nil && failure.executionOutcome == .failed
                            && (failure.code == .stale || failure.osStatus == -1728) {
                            try configuration.validateOriginal()
                            if let selected { try await conflict(selected.snapshot) }
                            diagnostics.update { $0.reason = .finalConflict }
                            break
                        } catch NotesHistoryError.stale {
                            try configuration.validateOriginal()
                            if current != scope(folderID), attempt == 0 { diagnostics.update { $0.reselected = true }; continue }
                            if let selected { try await conflict(selected.snapshot) }
                            diagnostics.update { $0.reason = .finalConflict }
                            break
                        }
                    }
                    let current = scope(folderID)
                    activateScope(current)
                    do {
                        let saved = try await saveManaged(original: original, entryID: entryID, submittedAt: submittedAt,
                            submittedZone: submittedZone, scope: current, title: nil, candidate: nil, configuration: configuration)
                        diagnostics.update { $0.savedAs = .new }
                        scheduleRefresh(saved, configuration: configuration)
                        return await completion(entryID)
                    } catch SaveError.metadataUnavailable {
                        diagnostics.update { $0.reason = .metadata }
                        return try await rawSave(original, folderID: folderID, validate: configuration.validateOriginal)
                    }
                }
            }
        } catch {
            diagnostics.update {
                if error is CancellationError { $0.outcome = .cancelled; $0.reason = .cancelled }
                else if (error as? ActionFailure)?.executionOutcome == .unknown { $0.outcome = .uncertain; $0.reason = .uncertainWrite }
                else { $0.outcome = .failed; if $0.reason == nil { $0.reason = .stale } }
            }
            throw error
        }
    }

    /// Called after configuration is ready, once per same-day scope. Never resumes yesterday.
    func resume(folderID: String, configuration: Configuration) async {
        startTitles(folderID: folderID, configuration: configuration)
        let current = scope(folderID)
        activateScope(current)
        let key = current.folderID + "|" + current.day + "|" + current.timeZoneID
        guard recoveredScopes.insert(key).inserted else { return }
        do {
            let values = try await serial { [self] in
                try configuration.validateOriginal()
                activateScope(current)
                let deadline = ContinuousClock.now.advanced(by: groupingTimeout - classificationTimeout)
                try await reconcile(scope: current, deadline: deadline)
                return try await candidates(scope: current, deadline: deadline)
            }
            for value in values where value.snapshot.generatedRevision != value.snapshot.originalRevision {
                scheduleRefresh(value, configuration: configuration)
            }
        } catch {
            recoveredScopes.remove(key)
            emit(.failed, code: RuntimeLog.code(error))
        }
    }

    private struct Candidate: Sendable {
        let snapshot: NotesDailyGroupingStore.Snapshot
        let document: NotesDailyDocument
        var source: NotesSource? = nil
    }

    func invalidateCandidates() {
        generation &+= 1
        cache.removeAll()
        cacheBytes = 0
        cacheScope = nil
        recoveredScopes.removeAll()
    }

    private func activateScope(_ current: NotesDailyScope) {
        guard cacheScope != current else { return }
        invalidateCandidates()
        cacheScope = current
    }

    private func invalidate(_ noteID: String) {
        if let old = cache.removeValue(forKey: noteID) {
            cacheBytes -= old.bytes
            NotesGroupingDiagnostics.current?.update { $0.cacheInvalidations += 1 }
        }
    }

    private func install(_ value: Candidate) {
        guard let noteID = value.snapshot.noteID, value.source != nil, cacheScope == value.snapshot.scope else { return }
        invalidate(noteID)
        let document = value.document
        let bytes = document.title.utf8.count + document.entries.reduce(0) { $0 + $1.text.utf8.count }
            + (document.generated?.text.utf8.count ?? 0) + (document.generated?.html?.utf8.count ?? 0)
        guard bytes <= cacheBudget else { return }
        while cacheBytes + bytes > cacheBudget, let oldest = cache.min(by: { $0.value.used < $1.value.used })?.key {
            invalidate(oldest)
        }
        access &+= 1
        cache[noteID] = (value, access, bytes)
        cacheBytes += bytes
    }

    private func checkPreparation(_ current: NotesDailyScope, token: UInt64, deadline: ContinuousClock.Instant) throws {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw NotesGroupingDeadline.Failure.expired }
        guard token == generation, current == cacheScope, current == scope(current.folderID) else {
            throw SaveError.preparationInvalidated
        }
    }

    private func conflict(_ record: NotesDailyGroupingStore.Snapshot) async throws {
        if let noteID = record.noteID { invalidate(noteID) }
        guard try await store.snapshot(groupID: record.groupID) == record else { throw SaveError.preparationInvalidated }
        try await store.markConflicted(groupID: record.groupID)
    }

    nonisolated private func preparationReason(_ error: Error) -> NotesGroupingDiagnostics.Reason {
        if error is NotesGroupingDeadline.Failure || (error as? ActionFailure)?.code == .timeout { return .preparationTimeout }
        return error is SaveError ? .stale : .readFailure
    }

    private func scope(_ folderID: String) -> NotesDailyScope {
        .current(folderID: folderID, at: now(), timeZone: timeZone())
    }

    private func serial<T: Sendable>(_ operation: @escaping @MainActor @Sendable () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task {
            await previous?.value
            try Task.checkCancellation()
            return try await operation()
        }
        tail = Task { _ = try? await task.value }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private func readResponse(_ request: AppleNotes.Request, deadline: ContinuousClock.Instant) async throws -> AppleNotes.Response {
        var request = request
        request.readDeadline = deadline
        request.groupingDiagnostics = NotesGroupingDiagnostics.current
        let frozen = request
        let response = try await NotesGroupingDeadline.read(until: deadline) { [run] in try await run(frozen) }
        if let failure = AppleNotes.actionFailure(for: response, operation: request.operation) { throw failure }
        return response
    }

    private func read(_ noteID: String, deadline: ContinuousClock.Instant) async throws -> (NotesSource, NotesSourceBody) {
        let response = try await readResponse(.init(requestID: UUID().uuidString, operation: "managedRead", noteID: noteID,
                                                    historyRead: true), deadline: deadline)
        guard let source = response.sources?.first, source.id == noteID, let body = response.sourceBody else {
            throw NotesHistoryError.response
        }
        return (source, body)
    }

    private func sameState(_ left: NotesSource, _ right: NotesSource) -> Bool {
        left.id == right.id && left.folderID == right.folderID && left.created == right.created
            && left.modified == right.modified && left.locked == right.locked && left.shared == right.shared
    }

    private func candidates(scope current: NotesDailyScope, deadline: ContinuousClock.Instant) async throws -> [Candidate] {
        let token = generation
        let pendingGroups = Set(try await store.pending(scope: current).map { $0.snapshot.groupID })
        let records = try await store.snapshots(scope: current)
        try checkPreparation(current, token: token, deadline: deadline)
        var result: [Candidate] = []
        for record in records where record.layout == .grouped && !record.conflicted && !pendingGroups.contains(record.groupID) {
            guard record.scope == current, let noteID = record.noteID else { continue }
            do {
                try checkPreparation(current, token: token, deadline: deadline)
                if let hit = cache[noteID], hit.candidate.snapshot == record, let baseline = hit.candidate.source {
                    let response = try await readResponse(.init(requestID: UUID().uuidString, operation: "managedState",
                        noteID: noteID, historyRead: true), deadline: deadline)
                    try checkPreparation(current, token: token, deadline: deadline)
                    guard let state = response.sources?.first, state.id == noteID else { throw NotesHistoryError.response }
                    if sameState(state, baseline) {
                        guard try await store.snapshot(groupID: record.groupID) == record else { throw SaveError.preparationInvalidated }
                        try checkPreparation(current, token: token, deadline: deadline)
                        access &+= 1
                        cache[noteID]?.used = access
                        NotesGroupingDiagnostics.current?.update { $0.cacheHits += 1 }
                        result.append(hit.candidate)
                        continue
                    }
                    invalidate(noteID)
                }
                NotesGroupingDiagnostics.current?.update { $0.cacheMisses += 1 }
                let (source, body) = try await read(noteID, deadline: deadline)
                try checkPreparation(current, token: token, deadline: deadline)
                try NotesUpdateGuard(noteID: noteID, scope: current, boundary: record.boundary)
                    .validate(source: source, body: body, at: now(), timeZone: timeZone())
                let candidate = Candidate(snapshot: record, document: try .recover(snapshot: record, body: body), source: source)
                guard try await store.snapshot(groupID: record.groupID) == record else { throw SaveError.preparationInvalidated }
                try checkPreparation(current, token: token, deadline: deadline)
                install(candidate)
                result.append(candidate)
            } catch {
                try checkPreparation(current, token: token, deadline: deadline)
                invalidate(noteID)
                let missing = (error as? ActionFailure)?.osStatus == -1728
                if case NotesHistoryError.stale = error { try await conflict(record) }
                else if case NotesHistoryError.ambiguous = error { try await conflict(record) }
                else if missing || (error as? ActionFailure)?.code == .stale { try await conflict(record) }
                else { throw error } // Incomplete candidate sets never reach the classifier.
            }
        }
        try checkPreparation(current, token: token, deadline: deadline)
        return result
    }

    private func saveManaged(original: String, entryID: String, submittedAt: Date, submittedZone: String,
                             scope current: NotesDailyScope, title: String?, candidate: Candidate?,
                             configuration: Configuration) async throws -> Candidate {
        let prior = candidate?.snapshot
        let groupID = prior?.groupID ?? UUID().uuidString
        refreshes.removeValue(forKey: groupID)?.task.cancel()
        var entries = candidate?.document.entries ?? []
        entries.append(.init(identity: .init(id: entryID, submittedAt: submittedAt,
            timeZoneID: submittedZone, sequence: entries.count), text: original))
        let initial = candidate == nil ? try await initialTitle(original, proposed: title, configuration: configuration) : nil
        let document = NotesDailyDocument(title: title ?? initial?.title ?? NotesInitialTitleGenerator.placeholder(for: original), scope: current, entries: entries,
                                         generated: configuration.supplementsEnabled ? candidate?.document.generated : nil)
        let coverage: Date?
        if let revision = prior?.generatedRevision, let old = candidate?.document,
           old.entries.indices.contains(revision - 1) {
            coverage = old.entries[revision - 1].identity.submittedAt
        } else { coverage = nil }
        let rendered = document.renderRetainingGenerated(coveredAt: coverage)
        let next = NotesDailyGroupingStore.Snapshot(groupID: groupID, noteID: prior?.noteID, scope: current,
            originalRevision: entries.count, generatedRevision: document.generated == nil ? nil : prior?.generatedRevision,
            entries: entries.map(\.identity), boundary: rendered.boundary,
            title: prior?.title ?? initial.map { titleMetadata($0, entryID: entryID, configuration: configuration) })
        let pending = NotesDailyGroupingStore.Pending(operationID: UUID().uuidString,
            kind: prior == nil ? .create : .append, previousBodyHash: prior?.boundary.bodyHash, snapshot: next)
        let confirmed = try await write(pending, content: rendered.content, previous: prior,
                                        validate: configuration.validateOriginal)
        if prior == nil { titleDiagnostic(state: confirmed.title?.state ?? .complete, code: initial?.code,
                                         adopted: confirmed.title?.state == .complete,
                                         nextAttempt: confirmed.title?.nextAttempt, recoveryAvailable: true) }
        startTitles(folderID: current.folderID, configuration: configuration)
        return .init(snapshot: confirmed, document: document)
    }

    private func write(_ pending: NotesDailyGroupingStore.Pending, content: AppleNotes.Content,
                       previous: NotesDailyGroupingStore.Snapshot?,
                       validate: @escaping @MainActor @Sendable () async throws -> Void) async throws -> NotesDailyGroupingStore.Snapshot {
        try await validate()
        guard scope(pending.snapshot.scope.folderID) == pending.snapshot.scope else { throw NotesHistoryError.stale }
        let cacheGeneration = generation
        if let noteID = previous?.noteID { invalidate(noteID) }
        let token: String
        do { token = try await index.stageDailyOrigin(noteID: previous?.noteID, boundary: pending.snapshot.boundary) }
        catch { throw SaveError.metadataUnavailable }
        do { try await store.stage(pending) }
        catch {
            try? await index.discardDailyOrigin(token: token)
            if error is NotesDailyGroupingStore.Failure { throw error }
            throw SaveError.metadataUnavailable
        }
        var dispatched = false
        let operation = previous == nil ? "create" : "update"
        do {
            try await validate()
            try Task.checkCancellation()
            guard scope(pending.snapshot.scope.folderID) == pending.snapshot.scope else { throw NotesHistoryError.stale }
            let guardValue = previous.flatMap { record in
                record.noteID.map { NotesUpdateGuard(noteID: $0, scope: record.scope, boundary: record.boundary) }
            }
            let beforeSend: @Sendable () async throws -> Void = { [self] in
                try await validate()
                guard await scope(pending.snapshot.scope.folderID) == pending.snapshot.scope else { throw NotesHistoryError.stale }
            }
            let request = AppleNotes.Request(requestID: pending.operationID, operation: operation,
                folderID: pending.snapshot.scope.folderID, noteID: previous?.noteID, html: content.html,
                validateBeforeSend: beforeSend, updateGuard: guardValue, managedConfirmation: true,
                groupingDiagnostics: NotesGroupingDiagnostics.current)
            dispatched = true
            let response = try await run(request)
            if let failure = AppleNotes.actionFailure(for: response, operation: operation) { throw failure }
            guard let noteID = response.noteID, response.folderID == pending.snapshot.scope.folderID,
                  let plaintext = response.plaintext,
                  pending.snapshot.boundary.extract(from: plaintext) != nil else { throw uncertain() }
            // Confirmed external writes remain confirmed even if the submitting task was cancelled.
            let confirmed = try await store.confirm(operationID: pending.operationID, noteID: noteID,
                scope: pending.snapshot.scope, plaintext: plaintext)
            do { try await index.confirmDailyOrigin(token: token, noteID: noteID) }
            catch { emit(.failed, code: .storage) }
            if cacheGeneration == generation, cacheScope == confirmed.scope, scope(confirmed.scope.folderID) == confirmed.scope,
               let source = response.sources?.first, let body = response.sourceBody,
               (try? NotesUpdateGuard(noteID: noteID, scope: confirmed.scope, boundary: confirmed.boundary)
                .validate(source: source, body: body, at: now(), timeZone: timeZone())) != nil,
               let document = try? NotesDailyDocument.recover(snapshot: confirmed, body: body) {
                install(.init(snapshot: confirmed, document: document, source: source))
            }
            return confirmed
        } catch {
            let failure = AppleNotes.actionFailure(for: error, operation: operation)
            if !dispatched || (!(error is CancellationError) && failure.executionOutcome == .failed) {
                try? await store.discardUnsent(operationID: pending.operationID)
                try? await index.discardDailyOrigin(token: token)
                if error is CancellationError { throw error }
                if case NotesHistoryError.stale = error { throw error }
                throw failure
            }
            // Do not issue another write. A later same-day read can reconcile the pending version.
            emit(.uncertain, code: failure.code, stage: pending.kind == .refresh ? .notesRefresh : .notesOriginalSave)
            throw uncertain()
        }
    }

    private func reconcile(scope current: NotesDailyScope, deadline: ContinuousClock.Instant) async throws {
        let token = generation
        guard current == scope(current.folderID) else { return }
        for pending in try await store.pending(scope: current) {
            try checkPreparation(current, token: token, deadline: deadline)
            var matches: [(NotesSource, NotesSourceBody)] = []
            if let id = pending.snapshot.noteID {
                if let (source, body) = try? await read(id, deadline: deadline), source.folderID == current.folderID,
                   pending.snapshot.boundary.extract(from: body.text) != nil { matches.append((source, body)) }
            } else {
                let reader = AppleNotesReader(run: { [self] in try await readResponse($0, deadline: deadline) })
                let sources = try await reader.metadata(folderID: current.folderID)
                for source in sources where !source.locked && !source.shared
                    && NotesDailyScope.current(folderID: source.folderID, at: source.created, timeZone: timeZone()) == current {
                    if let body = try? await reader.body(noteID: source.id), body.attachments == 0,
                       pending.snapshot.boundary.extract(from: body.text) != nil { // Read metadata and body together before installing a confirmed cache baseline.
                        let (confirmedSource, confirmedBody) = try await read(source.id, deadline: deadline)
                        if pending.snapshot.boundary.extract(from: confirmedBody.text) != nil { matches.append((confirmedSource, confirmedBody)) }
                    }
                }
            }
            try checkPreparation(current, token: token, deadline: deadline)
            guard matches.count == 1, let match = matches.first else { continue }
            try NotesUpdateGuard(noteID: match.0.id, scope: current, boundary: pending.snapshot.boundary)
                .validate(source: match.0, body: match.1, at: now(), timeZone: timeZone())
            let confirmed = try await store.confirm(operationID: pending.operationID, noteID: match.0.id, scope: current, plaintext: match.1.text)
            let originToken = try await index.stageDailyOrigin(noteID: match.0.id, boundary: pending.snapshot.boundary)
            try await index.confirmDailyOrigin(token: originToken, noteID: match.0.id)
            try checkPreparation(current, token: token, deadline: deadline)
            install(.init(snapshot: confirmed, document: try .recover(snapshot: confirmed, body: match.1), source: match.0))
            if pending.kind == .title { titleDiagnostic(state: .complete, code: nil, adopted: true) }
        }
    }

    private func scheduleRefresh(_ candidate: Candidate, configuration: Configuration) {
        guard configuration.supplementsEnabled, candidate.snapshot.layout == .grouped, let noteID = candidate.snapshot.noteID else { return }
        let groupID = candidate.snapshot.groupID
        refreshes.removeValue(forKey: groupID)?.task.cancel()
        let id = UUID()
        let deadline = ContinuousClock.now.advanced(by: refreshTimeout)
        let task = Task { [weak self] in
            guard let self else { return }
            await NotesGroupingDiagnostics.$current.withValue(nil) { [self] in
                defer { if refreshes[groupID]?.id == id { refreshes.removeValue(forKey: groupID) } }
                do {
                    try configuration.validateRefresh()
                    let work = try await configuration.processor(candidate.document, noteID)
                    let remaining = ContinuousClock.now.duration(to: deadline)
                    guard remaining > .zero else { emit(.timeout, code: .timeout); return }
                    let result = try await work.processor.process(candidate.document.original, timeout: remaining)
                    guard let preparation = result.report.preparation,
                          [NotesSupplementResult.Preparation.generated, .historyOnly, .validEmpty].contains(preparation) else {
                        emit(result.outcome, code: result.report.preparation == .timeout ? .timeout : .unavailable)
                        return
                    }
                    try await serial { [self] in
                        try configuration.validateRefresh()
                        try await work.validate()
                        guard ContinuousClock.now < deadline, refreshes[groupID]?.id == id,
                              scope(candidate.snapshot.scope.folderID) == candidate.snapshot.scope,
                              let current = try await store.snapshot(groupID: groupID), !current.conflicted,
                              current.originalRevision == candidate.snapshot.originalRevision,
                              current.entries == candidate.snapshot.entries,
                              current.boundary.regions.filter({ $0.kind != .title })
                                == candidate.snapshot.boundary.regions.filter({ $0.kind != .title })
                        else { throw NotesHistoryError.stale }
                        // A title may have completed while this model request was running.
                        let (source, body) = try await read(noteID, deadline: deadline)
                        try NotesUpdateGuard(noteID: noteID, scope: current.scope, boundary: current.boundary)
                            .validate(source: source, body: body, at: now(), timeZone: timeZone())
                        let latest = try NotesDailyDocument.recover(snapshot: current, body: body)
                        let rendered = latest.render(supplement: result.supplement)
                        let next = NotesDailyGroupingStore.Snapshot(groupID: groupID, noteID: noteID, scope: current.scope,
                            originalRevision: current.originalRevision, generatedRevision: current.originalRevision,
                            entries: current.entries, boundary: rendered.boundary, layout: current.layout, title: current.title)
                        let pending = NotesDailyGroupingStore.Pending(operationID: UUID().uuidString, kind: .refresh,
                            previousBodyHash: current.boundary.bodyHash, snapshot: next)
                        _ = try await write(pending, content: rendered.content, previous: current, validate: {
                            try configuration.validateRefresh()
                            try await work.validate()
                            guard ContinuousClock.now < deadline else { throw NotesHistoryError.stale }
                        })
                        emit(.success)
                    }
                } catch { emit(error is CancellationError ? .cancelled : .discarded, code: RuntimeLog.code(error)) }
            }
        }
        refreshes[groupID] = (id, task)
    }

    private func rawSave(_ original: String, folderID: String,
                         validate: @escaping @MainActor @Sendable () throws -> Void) async throws -> ActionOutcome {
        try validate()
        let document = NotesDailyDocument(title: NotesInitialTitleGenerator.placeholder(for: original),
            scope: scope(folderID), entries: [.init(identity: .init(id: UUID().uuidString, submittedAt: now(),
                timeZoneID: timeZone().identifier, sequence: 0), text: original)], layout: .independent)
        let content = document.render().content
        titleDiagnostic(state: .pending, code: .storage, adopted: false, recoveryAvailable: false)
        let response = try await run(.init(requestID: UUID().uuidString, operation: "create", folderID: folderID,
            html: content.html, validateBeforeSend: { try await validate() },
            groupingDiagnostics: NotesGroupingDiagnostics.current))
        if let failure = AppleNotes.actionFailure(for: response, operation: "create") { throw failure }
        guard response.noteID?.isEmpty == false, response.folderID == folderID else { throw uncertain() }
        NotesGroupingDiagnostics.current?.update { $0.outcome = .success; $0.savedAs = .raw }
        emit(.success, stage: .notesOriginalSave)
        return outcome(noteID: response.noteID)
    }

    private func outcome(notice: Bool = true, noteID: String? = nil) -> ActionOutcome {
        .init(messageKey: "result.notes.saved", effect: .created, showsCompletionNotice: notice,
              savedNoteID: noteID)
    }
    private func completion(_ entryID: String, recovered: Bool = false) async -> ActionOutcome {
        NotesGroupingDiagnostics.current?.update { $0.outcome = .success; if recovered { $0.savedAs = .recovered } }
        let receipt = try? await store.receipt(entryID: entryID)
        let claimed = (try? await store.claimCompletion(entryID: entryID)) ?? false
        emit(.success, stage: .notesOriginalSave)
        return outcome(notice: claimed, noteID: receipt?.noteID)
    }
    private func uncertain() -> ActionFailure {
        .init(localized: "error.notes.save_uncertain", code: .processFailed, executionOutcome: .unknown)
    }

    private func emit(_ outcome: RuntimeLog.Outcome, code: RuntimeLog.Code? = nil, stage: RuntimeLog.Stage = .notesRefresh) {
        let log = RuntimeLog.current ?? RuntimeLog.Context()
        log.emit(.stageFinished, .init(stage: stage, outcome: outcome, errorCode: code, actionID: "apple-notes"))
    }
}

extension NotesDailyGroupingCoordinator {
    /// Ordinary preparation completes before entering the same FIFO as grouped saves and updates.
    func saveIndependent(original: String, entryID: String, folderID: String, submittedAt: Date,
                         supplement: NotesSupplement, configuration: Configuration) async throws -> ActionOutcome {
        try await serial { [self] in
            try configuration.validateOriginal()
            var current = scope(folderID)
            activateScope(current)
            do {
                if try await store.receipt(entryID: entryID) != nil { return await completion(entryID, recovered: true) }
                _ = try await store.pending(scope: current)
            } catch { return try await rawSave(original, folderID: folderID, validate: configuration.validateOriginal) }
            do { try await reconcile(scope: current, deadline: .now.advanced(by: .seconds(30))) }
            catch is CancellationError { throw CancellationError() }
            catch { /* Unrelated recovery failure must not prevent a distinct original save. */ }
            if try await store.receipt(entryID: entryID) != nil { return await completion(entryID, recovered: true) }
            guard try await !store.pending(scope: current).contains(where: { $0.snapshot.entries.contains(where: { $0.id == entryID }) })
            else { throw uncertain() }
            let initial = try await initialTitle(original, proposed: nil, configuration: configuration)
            current = scope(folderID) // Initial-title work may cross midnight; create belongs to its write day.
            activateScope(current)
            let entry = NotesDailyGroupingStore.Entry(id: entryID, submittedAt: submittedAt,
                timeZoneID: timeZone().identifier, sequence: 0)
            let document = NotesDailyDocument(title: initial.title ?? NotesInitialTitleGenerator.placeholder(for: original),
                scope: current, entries: [.init(identity: entry, text: original)], layout: .independent)
            let rendered = document.render(supplement: supplement)
            let next = NotesDailyGroupingStore.Snapshot(groupID: UUID().uuidString, scope: current,
                originalRevision: 1, generatedRevision: rendered.content.itemCount + rendered.content.historyCount > 0 ? 1 : nil,
                entries: [entry], boundary: rendered.boundary, layout: .independent,
                title: titleMetadata(initial, entryID: entryID, configuration: configuration))
            do {
                _ = try await write(.init(operationID: UUID().uuidString, kind: .create, previousBodyHash: nil, snapshot: next),
                                    content: rendered.content, previous: nil, validate: configuration.validateOriginal)
            } catch SaveError.metadataUnavailable {
                return try await rawSave(original, folderID: folderID, validate: configuration.validateOriginal)
            }
            titleDiagnostic(state: next.title?.state ?? .complete, code: initial.code, adopted: initial.title != nil,
                            nextAttempt: next.title?.nextAttempt, recoveryAvailable: true)
            startTitles(folderID: folderID, configuration: configuration)
            return await completion(entryID)
        }
    }

    private func initialTitle(_ original: String, proposed: String?, configuration: Configuration) async throws -> NotesInitialTitleGenerator.Result {
        if let proposed, NotesInitialTitleGenerator.valid(proposed) { return .init(title: proposed) }
        do { return try await generateTitle(original, configuration: configuration) }
        catch NotesHistoryError.stale {
            // A model change invalidates its title, not the accepted original submission.
            return .init(code: .stale)
        }
    }

    private func titleMetadata(_ result: NotesInitialTitleGenerator.Result, entryID: String,
                               configuration: Configuration) -> NotesDailyGroupingStore.Title {
        .init(state: result.title != nil ? .complete : result.paused ? .paused : .pending,
              firstEntryID: entryID, attemptCount: 0,
              nextAttempt: result.title == nil && !result.paused ? now().addingTimeInterval(60) : nil,
              configurationVersion: configuration.titleGenerator?.version ?? "unavailable")
    }

    /// Serializes model rounds globally without holding the Notes write FIFO during recovery.
    private func generateTitle(_ original: String, configuration: Configuration) async throws -> NotesInitialTitleGenerator.Result {
        guard let generator = configuration.titleGenerator else { return .init(code: .configuration, paused: true) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        let previous = titleTail
        let task = Task {
            await previous?.value
            try Task.checkCancellation()
            try configuration.validateTitle()
            let result = try await generator.generate(original, until: deadline)
            try configuration.validateTitle()
            return result
        }
        titleTail = Task { _ = try? await task.value }
        do {
            return try await withTaskCancellationHandler {
                try await NotesGroupingDeadline.read(until: deadline) { try await task.value }
            } onCancel: { task.cancel() }
        } catch is NotesGroupingDeadline.Failure {
            task.cancel()
            return .init(code: .timeout)
        }
    }

    func cancelTitles() {
        titleWorker?.task.cancel()
        titleWorker = nil
    }

    func startTitles(folderID: String, configuration: Configuration) {
        guard (try? configuration.validateTitle()) != nil else { return }
        let key = folderID + "|" + (configuration.titleGenerator?.version ?? "unavailable")
        guard titleWorker?.key != key else { return }
        cancelTitles()
        let id = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            defer { if titleWorker?.id == id { titleWorker = nil } }
            while !Task.isCancelled {
                do {
                    try configuration.validateTitle()
                    let current = scope(folderID)
                    let expired = try await serial { [self] in try await store.expireTitles(except: current) }
                    if expired > 0 { titleDiagnostic(state: .expired, code: nil, adopted: false) }
                    // Unknown create/update outcomes are read-reconciled, never blindly reissued.
                    try await serial { [self] in
                        try configuration.validateTitle()
                        activateScope(current)
                        try await reconcile(scope: current, deadline: .now.advanced(by: .seconds(30)))
                    }
                    let unresolved = Set(try await store.pending(scope: current).map { $0.snapshot.groupID })
                    let version = configuration.titleGenerator?.version ?? "unavailable"
                    var eligible = try await store.snapshots(scope: current).filter {
                        !$0.conflicted && !unresolved.contains($0.groupID) && $0.noteID != nil
                            && $0.title.map { [.pending, .paused].contains($0.state) } == true
                    }
                    // Wake paused records only for a changed, non-secret model/configuration identity.
                    for record in eligible {
                        if var title = record.title, title.configurationVersion != version {
                            title.state = .pending; title.configurationVersion = version; title.nextAttempt = now()
                            let updated = title
                            _ = try await serial { [self] in try await store.updateTitle(updated, expected: record) }
                        }
                    }
                    eligible = try await store.snapshots(scope: current).filter {
                        !$0.conflicted && $0.noteID != nil && !unresolved.contains($0.groupID) && $0.title?.state == .pending
                    }.sorted {
                        let left = $0.title?.nextAttempt ?? .distantFuture, right = $1.title?.nextAttempt ?? .distantFuture
                        return left == right ? $0.groupID < $1.groupID : left < right
                    }
                    if let due = eligible.first, (due.title?.nextAttempt ?? .distantFuture) <= now() {
                        await recoverTitle(due, configuration: configuration)
                    } else {
                        let delay = min(60, max(1, eligible.first?.title?.nextAttempt?.timeIntervalSince(now()) ?? 60))
                        try await Task.sleep(for: .seconds(delay))
                    }
                } catch is CancellationError { break }
                catch NotesHistoryError.stale { break }
                catch {
                    titleDiagnostic(state: .pending, code: RuntimeLog.code(error), adopted: false)
                    do { try await Task.sleep(for: .seconds(60)) } catch { break }
                }
            }
        }
        titleWorker = (key, id, task)
    }

    private func recoverTitle(_ record: NotesDailyGroupingStore.Snapshot, configuration: Configuration) async {
        guard let noteID = record.noteID, let metadata = record.title else { return }
        do {
            // Reserve the next round durably before networking, so restart cannot reset backoff.
            var reserved = metadata
            reserved.attemptCount += 1
            let minutes = [5.0, 15, 30][min(reserved.attemptCount - 1, 2)]
            reserved.nextAttempt = now().addingTimeInterval(minutes * 60)
            let reservation = reserved
            let original: String? = try await serial { [self] in
                try configuration.validateTitle()
                guard try await store.updateTitle(reservation, expected: record) else { return nil }
                guard let current = try await store.snapshot(groupID: record.groupID), !current.conflicted,
                      current.scope == scope(current.scope.folderID), current.title?.firstEntryID == metadata.firstEntryID
                else { throw NotesHistoryError.stale }
                let (source, body) = try await read(noteID, deadline: .now.advanced(by: .seconds(30)))
                try NotesUpdateGuard(noteID: noteID, scope: current.scope, boundary: current.boundary)
                    .validate(source: source, body: body, at: now(), timeZone: timeZone())
                let document = try NotesDailyDocument.recover(snapshot: current, body: body)
                guard let first = document.entries.first, first.identity.id == metadata.firstEntryID else { throw NotesHistoryError.ambiguous }
                return first.text
            }
            guard let original else { return }
            let result = try await generateTitle(original, configuration: configuration)
            try configuration.validateTitle()
            if let title = result.title {
                try await serial { [self] in
                    try configuration.validateTitle()
                    guard let current = try await store.snapshot(groupID: record.groupID), !current.conflicted,
                          current.scope == scope(current.scope.folderID), var state = current.title,
                          [.pending, .paused].contains(state.state), state.firstEntryID == metadata.firstEntryID
                    else { throw NotesHistoryError.stale }
                    // Merge only the title into the latest confirmed body after concurrent append/refresh.
                    let (source, body) = try await read(noteID, deadline: .now.advanced(by: .seconds(30)))
                    try NotesUpdateGuard(noteID: noteID, scope: current.scope, boundary: current.boundary)
                        .validate(source: source, body: body, at: now(), timeZone: timeZone())
                    let rendered = try NotesDailyDocument.replacingTitle(title, snapshot: current, body: body)
                    state.state = .complete; state.nextAttempt = nil
                    let next = NotesDailyGroupingStore.Snapshot(groupID: current.groupID, noteID: noteID,
                        scope: current.scope, originalRevision: current.originalRevision, generatedRevision: current.generatedRevision,
                        entries: current.entries, boundary: rendered.boundary, layout: current.layout, title: state)
                    _ = try await write(.init(operationID: UUID().uuidString, kind: .title,
                        previousBodyHash: current.boundary.bodyHash, snapshot: next), content: rendered.content,
                        previous: current, validate: configuration.validateTitle)
                    titleDiagnostic(state: .complete, code: nil, adopted: true)
                }
            } else {
                try await serial { [self] in
                    try configuration.validateTitle()
                    guard let current = try await store.snapshot(groupID: record.groupID), var title = current.title else { return }
                    title.state = result.paused ? .paused : .pending
                    if result.paused { title.nextAttempt = nil }
                    _ = try await store.updateTitle(title, expected: current)
                    titleDiagnostic(state: title.state, code: result.code, adopted: false,
                                    nextAttempt: title.nextAttempt, recoveryAvailable: true)
                }
            }
        } catch {
            let failure = error as? ActionFailure
            // An uncertain write retains its staged expected version; subsequent passes only read it.
            if case NotesHistoryError.ambiguous = error { try? await serial { [self] in try await store.markConflicted(groupID: record.groupID) } }
            else if case NotesHistoryError.stale = error {
                if !Task.isCancelled, (try? configuration.validateTitle()) != nil,
                   record.scope == scope(record.scope.folderID) { try? await serial { [self] in try await store.markConflicted(groupID: record.groupID) } }
            } else if failure?.osStatus == -1728 || failure?.code == .stale {
                try? await serial { [self] in try await store.markConflicted(groupID: record.groupID) }
            }
            titleDiagnostic(state: failure?.executionOutcome == .unknown ? .uncertain
                                : (try? await store.snapshot(groupID: record.groupID))?.title?.state ?? .pending,
                            code: RuntimeLog.code(error), adopted: false)
        }
    }

    private func titleDiagnostic(state: NotesDailyGroupingStore.Title.State, code: RuntimeLog.Code?, adopted: Bool,
                                 nextAttempt: Date? = nil, recoveryAvailable: Bool? = nil) {
        var log = RuntimeLog.current ?? RuntimeLog.Context()
        log.purpose = .notesTitle
        log.emit(.stageFinished, .init(stage: .notesTitle, outcome: adopted ? .success : .discarded, errorCode: code,
            title: .init(attempts: 0, elapsedMs: 0, errorCategory: code, state: state, adopted: adopted,
                nextRetrySeconds: nextAttempt.map { Int(min(86_400, max(0, $0.timeIntervalSince(now())))) },
                recoveryAvailable: recoveryAvailable)))
    }
}
