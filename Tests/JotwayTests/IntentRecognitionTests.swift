import Foundation
import XCTest
@testable import Jotway

@MainActor
final class IntentRecognitionTests: XCTestCase {
    private typealias Snapshot = IntentRecognition.Snapshot
    private var current: Snapshot?
    private func snapshot(text: String, applications: [IntentRecognition.Application] = []) -> Snapshot {
        Snapshot(draftID: UUID(), revision: 0, panelSession: 1, registryRevision: 1,
                 text: text, applications: applications)
    }
    func testInputUpdatesSynchronouslyWithoutModelConfiguration() {
        let recognition = IntentRecognition(isCurrent: { self.current == $0 })
        for text in ["请查", "请查询内部", "请查询内部审批流程", "@calendar 明天开会"] {
            current = snapshot(text: text)
            recognition.update(current)
            XCTAssertEqual(recognition.snapshot, current)
            XCTAssertNil(recognition.suggestion, "普通正文不产生模型分类或替代目标")
        }
    }
    func testSuggestionCanBeFinishedOnceWithoutOwningManualSelection() throws {
        let app = IntentRecognition.Application(id: "app_0123456789abcdef", name: "ExampleApp",
            url: URL(fileURLWithPath: "/Applications/ExampleApp.app"))
        let recognition = IntentRecognition(isCurrent: { self.current == $0 })
        current = snapshot(text: "ExampleApp", applications: [app]); recognition.update(current)
        XCTAssertEqual(recognition.suggestion?.targetID, app.id)
        XCTAssertEqual(recognition.finishSuggestion(confirmed: false)?.action, .openApplication(app.id))
        XCTAssertNil(recognition.suggestion)
        XCTAssertNil(recognition.finishSuggestion(confirmed: true))
    }
    func testChangedSnapshotInvalidatesLocalSuggestion() {
        let app = IntentRecognition.Application(id: "app_0123456789abcdef", name: "ExampleApp",
            url: URL(fileURLWithPath: "/Applications/ExampleApp.app"))
        let recognition = IntentRecognition(isCurrent: { self.current == $0 })
        current = snapshot(text: "ExampleApp", applications: [app]); recognition.update(current)
        XCTAssertNotNil(recognition.suggestion)
        current = snapshot(text: "后来输入的正文", applications: [app])
        XCTAssertNil(recognition.finishSuggestion(confirmed: true))
        recognition.update(current); XCTAssertNil(recognition.suggestion)
        current = snapshot(text: String(repeating: "x", count: 12_001), applications: [app])
        recognition.update(current); XCTAssertNil(recognition.suggestion)
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
