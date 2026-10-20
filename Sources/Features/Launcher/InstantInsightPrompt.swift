import CryptoKit
import Foundation

/// A shared behavior preference, separate from model selection and Notes instructions.
struct InstantInsightPrompt: Equatable, Sendable {
    static let preferenceKey = "instantInsightPrompt.v1"
    static let maximumBytes = 16_000
    static let defaultText = """
        围绕当前草稿提供有用的文字帮助，按用户的完整请求组织回答。可以结合翻译、解释、总结、比较、改写或步骤建议，选择适合内容的段落、列表、代码或表格。根据问题决定说明详略。遵从用户明确指定的语言与格式；没有指定时使用提问语言，无法判断时参考界面语言。清楚的独立术语可以解释，明确请求缺少必要信息时提出澄清问题，不虚构背景。普通记录、待办、没有请求的摘录或不明片段没有值得提供的帮助时保持安静。
        """

    struct Snapshot: Equatable, Sendable {
        let text: String
        let version: String
    }

    let savedText: String
    let snapshot: Snapshot?

    init(stored: Any? = nil) {
        let text = stored as? String ?? ""
        savedText = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : text
        guard (stored == nil || stored is String), text.utf8.count <= Self.maximumBytes else {
            snapshot = nil
            return
        }
        let effective = savedText.isEmpty ? Self.defaultText : savedText
        snapshot = Snapshot(text: effective,
            version: SHA256.hash(data: Data(effective.utf8)).map { String(format: "%02x", $0) }.joined())
    }
}
