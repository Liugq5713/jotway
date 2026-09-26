import GRDB
import XCTest
@testable import Jotway

@MainActor
final class IntentFeedbackTests: XCTestCase {
    func testFrozenSampleSurvivesRestartWithIndependentOutcomeAndPrivateFailureLog() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Jotway-Operations-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("operations.sqlite").path
        let queue = try DatabaseQueue(path: path)
        try Database.migrate(queue)
        let store = OperationStore(dbQueue: queue)
        let body = "  =合成正文\n" + String(repeating: "完整中英 mixed 🗒️\n", count: 500)
        let input = OperationInput(id: "input-1", lineageID: "lineage-1", inputVersion: 3, capturedAt: 1000, text: body)
        let context = try OperationContext(capturedAt: 1000, ruleVersion: "synthetic-v1",
            configuration: .init(localRules: [.init(phrase: "保留", targetID: "apple-notes")]))
        let recapturedContext = try OperationContext(capturedAt: 9000, ruleVersion: "synthetic-v1",
            configuration: context.configuration)
        XCTAssertEqual(context.id, recapturedContext.id, "identical configurations ignore capture time")
        let capture = OperationEvent(id: "capture-1", inputID: input.id, contextID: context.id, runID: "run-1",
            occurredAt: 1000, kind: .inputCaptured, details: .capture(.init(trigger: .stableInput)))
        XCTAssertTrue(try store.capture(input: input, context: context, event: capture))
        XCTAssertFalse(try store.capture(input: input, context: recapturedContext, event: capture))
        var alteredCapture = capture
        alteredCapture.occurredAt += 1
        XCTAssertThrowsError(try store.append(alteredCapture), "event ID with conflicting content cannot be silently ignored")
        let presented = OperationEvent(id: "presented-1", inputID: input.id, contextID: context.id, runID: "run-1",
            occurredAt: 950, kind: .routePresented, targetKind: .action, targetID: "apple-notes", routeSource: .fallback,
            outcome: .available, details: .route(.init(presentationID: "panel-1")))
        XCTAssertTrue(try store.append(presented))
        let attempt = OperationAttempt(id: "attempt-1", inputID: input.id, contextID: context.id, targetKind: .action,
            targetID: "apple-notes", routeSource: .fallback, selectionOrigin: .automatic, confirmationSource: .button,
            decisionEventID: presented.id)
        let confirm = OperationEvent(id: "confirm-1", inputID: input.id, contextID: context.id, runID: "run-1",
            occurredAt: 900, kind: .confirmRequested, attemptID: attempt.id, details: .confirmation(.init()))
        XCTAssertTrue(try store.confirm(attempt: attempt, event: confirm))
        XCTAssertFalse(try store.confirm(attempt: attempt, event: confirm))
        let finish = OperationEvent(id: "finish-1", inputID: input.id, contextID: context.id, runID: "run-1",
            occurredAt: 1100, kind: .executionFinished, attemptID: attempt.id, outcome: .created,
            durationMS: 50, details: .execution(.init()))
        XCTAssertThrowsError(try store.append(finish), "execution requires prior acceptance")
        let accepted = OperationEvent(id: "accepted-1", inputID: input.id, contextID: context.id, runID: "run-1",
            occurredAt: 1050, kind: .submissionAccepted, attemptID: attempt.id, details: .submission(.init()))
        XCTAssertTrue(try store.append(accepted))
        var rejected = accepted
        rejected.id = "rejected-1"; rejected.kind = .submissionRejected; rejected.reasonCode = "target_unavailable"
        XCTAssertThrowsError(try store.append(rejected), "accepted and rejected are exclusive")
        XCTAssertTrue(try store.append(finish))
        XCTAssertFalse(try store.append(finish))
        var duplicateFinish = finish
        duplicateFinish.id = "finish-duplicate"
        XCTAssertThrowsError(try store.append(duplicateFinish), "one terminal effect per attempt")

        let otherInput = OperationInput(id: "input-2", lineageID: "lineage-2", inputVersion: 0, capturedAt: 1200, text: body)
        let otherCapture = OperationEvent(id: "capture-2", inputID: otherInput.id, contextID: context.id, runID: "run-1",
            occurredAt: 1200, kind: .inputCaptured, details: .capture(.init(trigger: .confirmation)))
        XCTAssertTrue(try store.capture(input: otherInput, context: context, event: otherCapture))
        var crossAttempt = attempt
        crossAttempt.id = "cross-attempt"; crossAttempt.inputID = otherInput.id
        var crossConfirm = confirm
        crossConfirm.id = "cross-confirm"; crossConfirm.inputID = otherInput.id; crossConfirm.attemptID = crossAttempt.id
        XCTAssertThrowsError(try store.confirm(attempt: crossAttempt, event: crossConfirm), "decision must belong to the same input")
        XCTAssertEqual(try store.snapshot().attempts.count, 1, "rejected confirm transaction leaves no attempt")
        let recognition = OperationEvent(id: "recognition-start", inputID: input.id, contextID: context.id,
            runID: "run-1", occurredAt: 1200, kind: .recognitionStarted, requestID: "request-1",
            details: .recognition(.init()))
        XCTAssertTrue(try store.append(recognition))
        var recognized = recognition
        recognized.id = "recognition-finish"; recognized.kind = .recognitionFinished; recognized.outcome = .stale
        recognized.inputID = otherInput.id
        XCTAssertThrowsError(try store.append(recognized), "request snapshots cannot drift")
        recognized.inputID = input.id
        XCTAssertTrue(try store.append(recognized))
        var wrongDetails = recognition
        wrongDetails.id = "wrong-details"; wrongDetails.requestID = "wrong-request"; wrongDetails.details = .clear(.init())
        XCTAssertThrowsError(try store.append(wrongDetails))
        try queue.close()

        let reopened = try DatabaseQueue(path: path)
        defer { try? reopened.close() }
        try Database.migrate(reopened)
        let persisted = OperationStore(dbQueue: reopened)
        let snapshot = try persisted.snapshot()
        XCTAssertEqual(snapshot.inputs.count, 2, "identical text in independent lineages stays independent")
        XCTAssertEqual(snapshot.inputs.first?.text, body)
        XCTAssertGreaterThan(snapshot.inputs.first?.utf8Bytes ?? 0, 4096)
        XCTAssertEqual(snapshot.contexts.count, 1)
        XCTAssertEqual(snapshot.attempts, [attempt])
        XCTAssertEqual(snapshot.events.first?.id, capture.id)
        XCTAssertEqual(snapshot.events[1].id, presented.id, "sequence survives clock rollback")
        XCTAssertEqual(snapshot.events.map(\.sequence).compactMap { $0 }, snapshot.events.compactMap(\.sequence).sorted())
        XCTAssertEqual(snapshot.events.first(where: { $0.id == finish.id })?.outcome, .created)
        let removed = try persisted.expire(before: 1300, excludingLineages: ["lineage-1"])
        XCTAssertEqual(removed, ["lineage-2"])
        XCTAssertThrowsError(try persisted.append(otherCapture), "callbacks cannot restore a deleted input")
        try persisted.removeAll()
        XCTAssertTrue(try persisted.snapshot().contexts.isEmpty)
        XCTAssertThrowsError(try persisted.append(finish), "terminal callbacks cannot recreate cleared inputs")
    }
}
