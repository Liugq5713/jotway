import Foundation
import XCTest
@testable import Jotway

@MainActor
final class IntentRecognitionTests: XCTestCase {
    private typealias Snapshot = IntentRecognition.Snapshot

    @MainActor
    private final class Probe {
        struct Call {
            let text: String
            let key: String
        }

        var current: Snapshot?
        var calls: [Call] = []
        var keyReads = 0
        private var replies: [Int: CheckedContinuation<Jev.Decision?, Error>] = [:]

        func recognize(_ text: String, key: String) async throws -> Jev.Decision? {
            let index = calls.count
            calls.append(Call(text: text, key: key))
            // Deliberately ignore cancellation: the coordinator must reject a late transport reply.
            return try await withCheckedThrowingContinuation { continuation in
                replies[index] = continuation
            }
        }

        func reply(_ index: Int, action: Jev.Action?) throws {
            let continuation = try XCTUnwrap(replies.removeValue(forKey: index))
            continuation.resume(returning: action.map { Jev.Decision(action: $0, model: "jev-test") })
        }

        func finish() {
            let pending = Array(replies.values)
            replies.removeAll()
            for continuation in pending { continuation.resume(returning: nil) }
        }
    }

    private enum TestFailure: Error { case timedOut }

    private func until(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("意图识别离线操作未在 2 秒内结束", file: file, line: line)
        throw TestFailure.timedOut
    }

    /// 默认给全部四个 action 且都可用；地板为 apple-notes，与 PanelController 快照构造对齐。
    private static let allActions: [IntentRecognition.ActionTarget] = [
        .init(id: "chrome", title: "Google 搜索"),
        .init(id: "apple-reminders", title: "存到提醒事项"),
        .init(id: "apple-calendar", title: "存到日历"),
        .init(id: "apple-notes", title: "存到备忘录")]

    private func snapshot(text: String = "请查询内部审批流程",
                          availableActions: [IntentRecognition.ActionTarget] = allActions,
                          defaultActionID: String = "apple-notes",
                          applications: [IntentRecognition.Application] = []) -> Snapshot {
        Snapshot(draftID: UUID(), revision: 0, panelSession: 1, configuration: UUID(),
                 registryRevision: 1, text: text, applications: applications, availableActions: availableActions,
                 defaultActionID: defaultActionID,
                 captureOptions: availableActions.filter { $0.id != "chrome" }
                    .map { .init(id: $0.id, criteria: $0.title) },
                 webSearchActionID: availableActions.contains { $0.id == "chrome" } ? "chrome" : nil)
    }

    private func changing(_ value: Snapshot, draftID: UUID? = nil, revision: Int? = nil,
                          panelSession: Int? = nil, configuration: UUID? = nil, text: String? = nil,
                          applications: [IntentRecognition.Application]? = nil) -> Snapshot {
        Snapshot(draftID: draftID ?? value.draftID, revision: revision ?? value.revision,
                 panelSession: panelSession ?? value.panelSession, configuration: configuration ?? value.configuration,
                 registryRevision: value.registryRevision,
                 text: text ?? value.text, applications: applications ?? value.applications,
                 applicationRanks: value.applicationRanks,
                 availableActions: value.availableActions, defaultActionID: value.defaultActionID,
                 captureOptions: value.captureOptions, webSearchActionID: value.webSearchActionID)
    }

    private func coordinator(_ probe: Probe, debounce: Duration = .milliseconds(1), log: RuntimeLog = .shared) -> IntentRecognition {
        IntentRecognition(debounce: debounce, log: log, readKey: {
            probe.keyReads += 1
            return "synthetic-test-key"
        }, recognize: { text, key, _ in
            try await probe.recognize(text, key: key)
        }, isCurrent: { probe.current == $0 })
    }

    private func update(_ value: Snapshot?, on coordinator: IntentRecognition, probe: Probe) {
        probe.current = value
        coordinator.update(value)
    }

    func testDebounceMergesInputBeforeReadingKeyOrRecognizing() async throws {
        let probe = Probe(), recognition = coordinator(probe, debounce: .milliseconds(20))
        defer { recognition.update(nil); probe.finish() }
        let first = snapshot(text: "请查"), second = changing(first, revision: 1, text: "请查询内部"),
            latest = changing(first, revision: 2, text: "请查询内部审批流程")
        update(first, on: recognition, probe: probe)
        update(second, on: recognition, probe: probe)
        update(latest, on: recognition, probe: probe)
        XCTAssertTrue(probe.calls.isEmpty)
        XCTAssertEqual(probe.keyReads, 0)
        try await until { probe.calls.count == 1 }
        XCTAssertEqual(probe.calls[0].text, latest.text)
        XCTAssertEqual(probe.calls[0].key, "synthetic-test-key")
        XCTAssertEqual(probe.keyReads, 1)
        try probe.reply(0, action: .capture(actionID: "apple-calendar"))
        try await until { recognition.suggestion != nil }
        XCTAssertEqual(recognition.suggestion?.snapshot, latest)
        XCTAssertEqual(recognition.suggestion?.action, .action("apple-calendar", diagnostic: .capture))
        XCTAssertFalse(recognition.isRecognizing)
    }

    func testSuggestionCanBeFinishedOnceWithoutOwningManualSelection() async throws {
        let probe = Probe(), recognition = coordinator(probe)
        defer { recognition.update(nil); probe.finish() }
        // 提醒可用、日历不可用：可切目标 = Jev(.capture reminders) + chrome + 地板 notes。
        let snap = snapshot(text: "记得下午三点交周报",
            availableActions: [.init(id: "chrome", title: "Google 搜索"),
                               .init(id: "apple-reminders", title: "存到提醒事项"),
                               .init(id: "apple-notes", title: "存到备忘录")])
        update(snap, on: recognition, probe: probe)
        try await until { probe.calls.count == 1 }
        try probe.reply(0, action: .capture(actionID: "apple-reminders"))
        try await until { recognition.suggestion != nil }

        XCTAssertEqual(recognition.suggestion?.targetID, "apple-reminders")
        XCTAssertEqual(recognition.suggestion?.title, "存到提醒事项")
        XCTAssertEqual(recognition.finishSuggestion(confirmed: false)?.action,
                       .action("apple-reminders", diagnostic: .capture))
        XCTAssertNil(recognition.suggestion, "建议展示只能结束一次")
        XCTAssertNil(recognition.finishSuggestion(confirmed: true))
    }

    func testModelResultMustMatchBindingsFromSnapshot() async throws {
        let probe = Probe(), recognition = coordinator(probe)
        defer { recognition.update(nil); probe.finish() }
        // 只启用 chrome、无提醒事项：可切目标应只有 Jev 建议(.google→chrome) + 兜底备忘录。
        let snap = snapshot(text: "搜一下 Swift 并发",
            availableActions: [.init(id: "chrome", title: "Google 搜索"),
                               .init(id: "apple-notes", title: "存到备忘录")])
        update(snap, on: recognition, probe: probe)
        try await until { probe.calls.count == 1 }
        try probe.reply(0, action: .google)
        try await until { recognition.suggestion != nil }
        XCTAssertEqual(recognition.suggestion?.targetID, "chrome")
    }

    func testGenericInstalledApplicationNameIsNotBlacklisted() throws {
        let application = IntentRecognition.Application(
            id: "app_0123456789abcdef", name: "ExampleApp", url: URL(fileURLWithPath: "/Applications/ExampleApp.app"))

        let match = try XCTUnwrap(IntentRecognition.localApplicationMatch(
            in: "打开 ExampleApp", applications: [application]))

        XCTAssertNil(match.rejection)
        XCTAssertEqual(match.applications, [application])
    }
}
