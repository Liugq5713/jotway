import Foundation
import XCTest
@testable import Jotway

/// Historical decoding checks; no callable service remains.
@MainActor
final class JevTests: XCTestCase {
    func testHistoricalDiagnosticsRemainReadable() throws {
        let transform = try JSONDecoder().decode(OperationTextTransform.self, from: Data(#""remove_action_mention""#.utf8))
        XCTAssertEqual(transform, .removeActionMention)
        XCTAssertNil(LegacyIntentDiagnostics.Action(rawValue: "removed-action"), "在线诊断只接受当前固定 action 集合")
        let historicalAction = try JSONDecoder().decode(LegacyIntentDiagnostics.Action.self, from: Data(#""retired-action""#.utf8))
        let historicalReason = try JSONDecoder().decode(LegacyIntentDiagnostics.Reason.self, from: Data(#""retired-reason""#.utf8))
        XCTAssertEqual(historicalAction, .unknown)
        XCTAssertEqual(historicalReason, .unknown)
        XCTAssertEqual(String(data: try JSONEncoder().encode(historicalAction), encoding: .utf8), #""unknown""#,
                       "历史未知值只能收敛为固定非执行状态，不能写入任意原值")
        XCTAssertEqual(LegacyIntentDiagnostics().bounded.ruleVersion, "jev-intent-v9")
        XCTAssertEqual(LegacyIntentDiagnostics(ruleVersion: "jev-intent-v2").bounded.ruleVersion, "jev-intent-v2",
                       "Historical logs must retain their original rules")
    }
}
