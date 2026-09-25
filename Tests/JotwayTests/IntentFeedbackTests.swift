import GRDB
import XCTest
@testable import Jotway

@MainActor
final class IntentFeedbackTests: XCTestCase {
    func testFrozenSampleSurvivesRestartWithIndependentOutcomeAndPrivateFailureLog() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Jotway-Feedback-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let logs = root.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        let logURL = logs.appendingPathComponent(String(format: "jotway-%04d-%02d-%02d.jsonl",
            components.year!, components.month!, components.day!))
        let preservedLogLine = #"{"schemaVersion":1,"acceptanceMode":"retired-value"}"# + "\n"
        try Data(preservedLogLine.utf8).write(to: logURL)
        let path = root.appendingPathComponent("feedback.sqlite").path
        let queue = try DatabaseQueue(path: path)
        try Database.migrate(queue)
        let repository = LauncherStore(dbQueue: queue)
        let log = RuntimeLog(directory: logs, calendar: calendar, clock: { now })
        let store = IntentFeedbackStore(repository: repository, log: log)
        let body = "  synthetic-private-body\nhttps://example.invalid/private?key=synthetic-secret  "
        let snapshot = IntentRecognition.Snapshot(draftID: UUID(), revision: 7, panelSession: 2,
            configuration: UUID(), registryRevision: 1, text: body, applications: [
                .init(id: "synthetic-app", name: "Private Application Name", url: root.appendingPathComponent("Private.app"),
                      bundleIdentifier: "com.jotway.tests.private")
            ], webSearchActionID: nil)
        let suggestion = IntentRecognition.Suggestion(snapshot: snapshot, action: .openApplication("synthetic-app"),
            recognition: .init(source: .localAppName, requestID: UUID(), ruleVersion: "jev-intent-v2", actualModel: nil,
                               applicationMatch: .prefix))
        let sample = suggestion.feedback(confirmationSource: .enter,
            at: Date(timeIntervalSince1970: 1_800_000_000))
        store.record(sample)
        store.record(suggestion.feedback(confirmationSource: .commandEnter,
            at: .distantFuture)) // Same event cannot rewrite its acceptance time or trigger source.
        await store.flush()
        let initial = try XCTUnwrap(repository.intentFeedback(id: sample.id))
        XCTAssertEqual(initial.sample, sample)
        XCTAssertEqual(initial.execution.outcome, .notStarted)
        let request = UUID()
        store.execution(sample.id, .init(outcome: .requested, requestID: request))
        store.execution(sample.id, .init(outcome: .failed, requestID: request, finished: true))
        store.execution(sample.id, .init(outcome: .opened, requestID: request, finished: true)) // A late duplicate callback cannot overwrite the first result.
        await store.flush()
        try queue.close()

        let restarted = try DatabaseQueue(path: path)
        defer { try? restarted.close() }
        try Database.migrate(restarted)
        let reopenedRepository = LauncherStore(dbQueue: restarted)
        let restored = try XCTUnwrap(reopenedRepository.intentFeedback(id: sample.id))
        XCTAssertEqual(restored.sample, sample)
        XCTAssertEqual(restored.sample.text, body)
        XCTAssertEqual(restored.sample.draftRevision, 7)
        XCTAssertEqual(restored.sample.label, .userAccepted)
        XCTAssertEqual(restored.sample.confirmationSource, .enter)
        XCTAssertEqual(restored.sample.recognition.source, .localAppName)
        XCTAssertEqual(restored.sample.recognition.applicationMatch, .prefix)
        var unknownObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(sample)) as? [String: Any])
        let unknownID = UUID()
        unknownObject["id"] = unknownID.uuidString
        unknownObject["action"] = "retired-action"
        unknownObject["targetID"] = "retired-target"
        unknownObject["text"] = "历史反馈正文"
        let unknownData = try JSONSerialization.data(withJSONObject: unknownObject, options: [.sortedKeys])
        try await restarted.write { db in
            try db.execute(sql: "INSERT INTO intent_feedback(id, sample, execution) VALUES (?, ?, ?)",
                arguments: [unknownID.uuidString, unknownData, try JSONEncoder().encode(IntentFeedback.Execution())])
        }
        let unknown = try XCTUnwrap(reopenedRepository.intentFeedback(id: unknownID))
        XCTAssertEqual(unknown.sample.action, .unknown)
        XCTAssertNotEqual(unknown.sample.action, .none, "历史未知 action 不得伪装成无意图")
        XCTAssertEqual(unknown.sample.targetID, "retired-target")
        XCTAssertEqual(unknown.sample.text, "历史反馈正文")
        let storedUnknownData = try await restarted.read { try Data.fetchOne($0,
            sql: "SELECT sample FROM intent_feedback WHERE id = ?", arguments: [unknownID.uuidString]) }
        XCTAssertEqual(storedUnknownData, unknownData,
            "兼容读取不得改写原始历史反馈")
        let suite = "JotwayTests.UnknownFeedback.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let modules = BundledActions.modules(preferences: preferences)
        XCTAssertNil(ActionConfiguration(preferences: preferences, modules: modules)
            .registry.descriptor(for: unknown.sample.targetID),
            "未知历史目标不得进入当前执行注册表")
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(sample)) as? [String: Any])
        var legacyRecognition = try XCTUnwrap(legacy["recognition"] as? [String: Any])
        legacyRecognition.removeValue(forKey: "applicationMatch")
        legacy["recognition"] = legacyRecognition
        legacy.removeValue(forKey: "confirmationSource")
        let decodedLegacy = try JSONDecoder().decode(IntentFeedback.self,
            from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decodedLegacy.recognition.applicationMatch, "既有样本无需迁移或伪造匹配类型")
        XCTAssertNil(decodedLegacy.confirmationSource, "§15 前的样本保持原始 JSON，不改写触发来源")
        XCTAssertNil(restored.sample.recognition.actualModel)
        XCTAssertEqual(restored.execution.outcome, .failed)
        XCTAssertEqual(restored.execution.requestID, request)
        let feedbackCount = try await restarted.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM intent_feedback")
        }
        XCTAssertEqual(feedbackCount, 2)

        try await restarted.write { try $0.execute(sql: "CREATE TRIGGER fail_feedback BEFORE INSERT ON intent_feedback BEGIN SELECT RAISE(FAIL, 'synthetic-private-error'); END") }
        let failedStore = IntentFeedbackStore(repository: reopenedRepository, log: log)
        var another = suggestion
        another.id = UUID()
        let failed = another.feedback()
        failedStore.record(failed)
        failedStore.record(failed, storageAvailable: false) // The app's fallback memory store cannot claim a durable sample.
        await failedStore.flush()
        XCTAssertNil(try reopenedRepository.intentFeedback(id: failed.id))
        _ = await log.status()
        let export = root.appendingPathComponent("logs.zip")
        let exportedIncomplete = try await log.export(to: export)
        XCTAssertFalse(exportedIncomplete)
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.path))
        XCTAssertTrue(try String(contentsOf: logURL, encoding: .utf8).hasPrefix(preservedLogLine),
            "完整旧日志行在轮转和导出前后必须逐字保留")
        let bytes = try FileManager.default.contentsOfDirectory(at: log.directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        for privateValue in [body, "synthetic-secret", "synthetic-private-error", "Private Application Name", root.path] {
            XCTAssertFalse(bytes.contains(privateValue))
        }
        let rows = try bytes.split(separator: "\n").map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
        XCTAssertTrue(rows.contains { $0["feedbackID"] as? String == sample.id.uuidString && $0["outcome"] as? String == "success" })
        XCTAssertTrue(rows.contains { $0["feedbackID"] as? String == sample.id.uuidString
            && $0["feedbackConfirmation"] as? String == "enter" })
        XCTAssertTrue(rows.contains { $0["feedbackID"] as? String == sample.id.uuidString && $0["outcome"] as? String == "discarded" })
        let failures = rows.filter { $0["feedbackID"] as? String == failed.id.uuidString }
        XCTAssertEqual(failures.count, 2)
        XCTAssertTrue(failures.allSatisfy { $0["outcome"] as? String == "failed" && $0["errorCode"] as? String == "storage" })
    }
}
