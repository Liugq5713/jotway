import Foundation

/// Optional DeepSeek body rewriting; destination and scheduling are independent.
/// Provider failures preserve the original text. Cancellation remains cancellation.
struct AITextProcessor: ActionTextProcessor {
    enum Mode: Sendable {
        /// 备忘录：整理正文，首行即标题。
        case notes
        /// 提醒事项：只整理正文。
        case reminders
        /// 日历：只整理正文。
        case calendar
    }

    /// 钉死 DeepSeek 的 provider（由 `AppState` 用 `DeepSeek.source()` 构造并注入）。
    let provider: AIProviderPlugin
    let mode: Mode
    /// 用户自定义的整理风格：非空时取代 `defaultStyle`，只影响风格段、锁定后缀原样保留。
    let styleOverride: String?
    /// 备忘录追加相关标签开关；仅 `.notes` 模式消费，开时在锁定后缀追加自动打标签的要求。
    let notesAutoTags: Bool
    init(provider: AIProviderPlugin, mode: Mode, styleOverride: String? = nil,
         notesAutoTags: Bool = false) {
        self.provider = provider
        self.mode = mode
        self.styleOverride = styleOverride
        self.notesAutoTags = notesAutoTags
    }

    func process(_ text: String) async throws -> ProcessedText {
        try Task.checkCancellation()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ProcessedText(text: text)
        }
        do {
            let output = try await provider.generate(content: text, instructions: instructions())
            try Task.checkCancellation()
            let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return ProcessedText(text: text) }
            switch mode {
            case .notes:
                return ProcessedText(text: cleaned)
            case .reminders, .calendar:
                // Structured/time JSON is not a body response. Never interpret its dates.
                guard !cleaned.hasPrefix("{"), !cleaned.hasPrefix("["), !cleaned.hasPrefix("```") else {
                    return ProcessedText(text: text)
                }
                return ProcessedText(text: cleaned)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return ProcessedText(text: text)
        }
    }

    // MARK: - 指令

    /// 默认整理规则：只整理不发挥。
    /// 设置页把它当作「整理风格」的默认值展示；用户覆盖后由 `styleOverride` 取代。
    static let defaultStyle = """
        你是 Jotway 的文字整理助手。任务是把用户随手记下 / 口述的一段文字整理干净，直接用于保存。
        只做整理：去掉口语碎语、语气词、明显错别字与重复；把杂乱内容整理得通顺，必要时用要点罗列；首行给一个精炼的标题。
        不改变原意、不新增事实、不回答其中的问题、不加任何评论或解释；保留原文的疑问、犹豫与矛盾。
        默认保持输入所用语言；中英混合输入保持原有语言构成，不因界面语言而翻译。只有用户在正文中明确要求翻译时，才按该指令翻译。
        """

    static var localizedDefaultStyle: String { L10n.text("action.ai.default_style") }

    /// 生效的整理风格：用户覆盖（非空）优先，否则用默认风格。仅影响风格段，锁定后缀不受其影响。
    private var style: String {
        if let styleOverride, !styleOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return styleOverride
        }
        return Self.defaultStyle
    }

    private func instructions() -> String {
        switch mode {
        case .notes:
            var suffix = "\n只输出整理后的正文本身（首行为标题），不要额外说明，不要用代码块包裹。\n正文中已有的 #标签 原样保留。"
            if notesAutoTags {
                suffix += "\n另起一行，在正文最后追加 1–3 个与内容相关的 #标签（# 后接连续文字、不含空格），独占最后一行。"
            }
            return style + suffix
        case .reminders, .calendar:
            return style + """

                只输出整理后的正文本身（首行为标题），不要额外说明、不要用代码块或 JSON 包裹。
                时间由应用从原始输入独立处理；不要提取、换算或补充日期时间，不要输出 due、start、end 字段。
                """
        }
    }
}
