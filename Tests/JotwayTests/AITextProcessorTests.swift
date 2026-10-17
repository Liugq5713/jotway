import XCTest
@testable import Jotway

/// Notes 的独立补充与失败降级。
/// 用假 provider（预设 Response / 抛错）覆盖，无需真网络。
@MainActor
final class AITextProcessorTests: XCTestCase {
    /// 构造一个直接吐预设文本的假 provider。
    private func provider(returning result: String) -> ModelTextInvocation {
        .init(version: "test") { _, _ in result }
    }

    private func failingProvider() -> ModelTextInvocation {
        .init(version: "test") { _, _ in throw AIProviderPlugin.Failure(message: "boom") }
    }

    func testNotesReturnsSeparateSupplement() async throws {
        let processor = AINotesSupplementProcessor(provider: provider(returning:
            #"{"items":[{"text":"是否需要确认鸡蛋的数量？"}]}"#))
        let supplement = try await processor.process("呃 就是那个 买牛奶 然后鸡蛋")
        XCTAssertEqual(supplement.supplement.items, [.init(text: "是否需要确认鸡蛋的数量？")])
        XCTAssertEqual(supplement.supplement.tags, [])
    }

    func testNotesFailureReturnsNoSupplement() async throws {
        let processor = AINotesSupplementProcessor(provider: failingProvider())
        let supplement = try await processor.process("AI 挂了也要存下来")
        XCTAssertEqual(supplement.supplement, .empty)
    }

}
