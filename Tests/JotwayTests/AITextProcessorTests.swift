import XCTest
@testable import Jotway

/// 固定基准时间，稳定相对时间解析与断言。文件作用域（nonisolated）以便 @Sendable 闭包引用。
private let fixedNow = Calendar.current.date(
    from: DateComponents(year: 2026, month: 9, day: 23, hour: 9, minute: 0))!

/// 存入前的 DeepSeek 加工环节：整理文本、提醒事项解析到期时间、失败降级存原文。
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
                                        mode: .notes, now: { fixedNow })
        let processed = try await processor.process("呃 就是那个 买牛奶 然后鸡蛋")
        XCTAssertEqual(processed.text, "买牛奶\n还要买鸡蛋")
        XCTAssertNil(processed.due)
    }

    func testRemindersModeParsesTextAndDue() async throws {
        let json = #"{"text": "开会", "due": "2026-09-24T15:00:00"}"#
        let processor = AITextProcessor(provider: provider(returning: json),
                                        mode: .reminders, now: { fixedNow })
        let processed = try await processor.process("提醒我明天下午三点开会")
        XCTAssertEqual(processed.text, "开会")
        let expected = Calendar.current.date(
            from: DateComponents(year: 2026, month: 9, day: 24, hour: 15, minute: 0, second: 0))
        XCTAssertEqual(processed.due, expected)
    }

    func testFailureFallsBackToOriginalText() async throws {
        let processor = AITextProcessor(provider: failingProvider(),
                                        mode: .notes, now: { fixedNow })
        let processed = try await processor.process("AI 挂了也要存下来")
        XCTAssertEqual(processed.text, "AI 挂了也要存下来")
        XCTAssertNil(processed.due)
    }

}
