import XCTest
@testable import Jotway

/// 存入前的 DeepSeek 正文整理；时间由原始草稿的本地计划独立处理。
/// 用假 provider（预设 Response / 抛错）覆盖，无需真网络。
@MainActor
final class AITextProcessorTests: XCTestCase {
    /// 构造一个直接吐预设文本的假 provider。
    private func provider(returning result: String) -> AIProviderPlugin {
        AIProviderPlugin(configuration: {
            .init(version: "test", perform: { _ in .init(result: result, error: nil) })
        })
    }

    /// 构造一个 generate 阶段抛错的假 provider（模拟没配 Key / 断网）。
    private func failingProvider() -> AIProviderPlugin {
        AIProviderPlugin(configuration: {
            .init(version: "test", perform: { _ in throw AIProviderPlugin.Failure(message: "boom") })
        })
    }

    func testNotesReturnsSeparateSupplement() async throws {
        let processor = AINotesSupplementProcessor(provider: provider(returning:
            #"{"items":[{"kind":"question","text":"是否需要确认鸡蛋的数量？"}],"tags":["采购"]}"#),
            autoTags: true)
        let supplement = try await processor.process("呃 就是那个 买牛奶 然后鸡蛋")
        XCTAssertEqual(supplement.items, [.init(kind: .question, text: "是否需要确认鸡蛋的数量？")])
        XCTAssertEqual(supplement.tags, ["采购"])
    }

    func testRemindersModeUsesBodyWithoutTimeFields() async throws {
        let processor = AITextProcessor(provider: provider(returning: "开会"), mode: .reminders)
        let processed = try await processor.process("提醒我明天下午三点开会")
        XCTAssertEqual(processed.text, "开会")
    }

    func testNotesFailureReturnsNoSupplement() async throws {
        let processor = AINotesSupplementProcessor(provider: failingProvider())
        let supplement = try await processor.process("AI 挂了也要存下来")
        XCTAssertEqual(supplement, .empty)
    }

}
