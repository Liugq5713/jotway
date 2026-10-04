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

    func testNotesModeUsesCleanedText() async throws {
        let processor = AITextProcessor(provider: provider(returning: "买牛奶\n还要买鸡蛋"),
                                        mode: .notes)
        let processed = try await processor.process("呃 就是那个 买牛奶 然后鸡蛋")
        XCTAssertEqual(processed.text, "买牛奶\n还要买鸡蛋")
    }

    func testRemindersModeUsesBodyWithoutTimeFields() async throws {
        let processor = AITextProcessor(provider: provider(returning: "开会"), mode: .reminders)
        let processed = try await processor.process("提醒我明天下午三点开会")
        XCTAssertEqual(processed.text, "开会")
    }

    func testFailureFallsBackToOriginalText() async throws {
        let processor = AITextProcessor(provider: failingProvider(),
                                        mode: .notes)
        let processed = try await processor.process("AI 挂了也要存下来")
        XCTAssertEqual(processed.text, "AI 挂了也要存下来")
    }

}
