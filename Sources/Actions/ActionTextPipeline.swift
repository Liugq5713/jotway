import Foundation

/// `原始文本 → AI 处理 → 写入` 管道的 AI 环节（见 launcher-refactor.md §2.6）。
///
/// 加工结果不只是文本：提醒事项还要带上从自然语言里解析出的到期时间，
/// 所以返回 `ProcessedText`（文本 + 可选 due）。备忘录忽略 due，提醒事项消费它。
/// 具体加工形态见 `AITextProcessor`（DeepSeek）；`PassthroughTextProcessor` 为原文直通兜底。
protocol ActionTextProcessor: Sendable {
    func process(_ text: String) async throws -> ProcessedText
}

/// 加工产物：整理后的正文 + 可选时间（due 仅提醒事项用，start/end 仅日历日程用）。
struct ProcessedText: Sendable {
    var text: String
    /// 从自然语言解析出的到期时间；备忘录忽略，提醒事项写入 reminder 的 due。
    var due: Date? = nil
    /// 从自然语言解析出的日程开始时间；仅日历 action 消费，缺省时由 action 层回退为当前时刻。
    var start: Date? = nil
    /// 从自然语言解析出的日程结束时间；缺省时由 action 层回退为开始 + 1 小时。
    var end: Date? = nil
}

/// 兜底：原文直通，不做任何加工，也不带 due。
struct PassthroughTextProcessor: ActionTextProcessor {
    func process(_ text: String) async throws -> ProcessedText { ProcessedText(text: text) }
}
