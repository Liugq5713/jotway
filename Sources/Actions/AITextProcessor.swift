import Foundation

/// 存入前的 AI 加工环节（DeepSeek）。
///
/// 把用户口述 / 零散的文字整理干净再落地：去口语碎语、结构化、提炼首行标题；
/// 提醒事项额外从自然语言里解析到期时间。固定走 DeepSeek（由 `provider` 钉死），
/// 与设置里选的 AI 来源无关。
///
/// 降级优先：任何环节失败（没配 Key / 断网 / 超时 / 返回无法解析）都 **返回原始文字**，
/// 绝不因为 AI 出问题而丢内容——契合「回车永远有确定结果」。
struct AITextProcessor: ActionTextProcessor {
    enum Mode: Sendable {
        /// 备忘录：整理正文，首行即标题。
        case notes
        /// 提醒事项：整理正文 + 解析到期时间。
        case reminders
        /// 日历：整理正文 + 解析日程开始 / 结束时间。
        case calendar
    }

    /// 钉死 DeepSeek 的 provider（由 `AppState` 用 `DeepSeek.source()` 构造并注入）。
    let provider: AIProviderPlugin
    let mode: Mode
    /// 用户自定义的整理风格：非空时取代 `defaultStyle`，只影响风格段、锁定后缀原样保留。
    let styleOverride: String?
    /// 备忘录追加相关标签开关；仅 `.notes` 模式消费，开时在锁定后缀追加自动打标签的要求。
    let notesAutoTags: Bool
    /// 当前时间提供者：喂给相对时间解析（「明天下午三点」）的基准，可注入以稳定测试。
    let now: @Sendable () -> Date

    init(provider: AIProviderPlugin, mode: Mode, styleOverride: String? = nil,
         notesAutoTags: Bool = false, now: @escaping @Sendable () -> Date = { Date() }) {
        self.provider = provider
        self.mode = mode
        self.styleOverride = styleOverride
        self.notesAutoTags = notesAutoTags
        self.now = now
    }

    func process(_ text: String) async throws -> ProcessedText {
        // 空白输入不值得一次网络调用，直接原样返回。
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ProcessedText(text: text)
        }
        do {
            let output = try await provider.generate(content: text, instructions: instructions())
            switch mode {
            case .notes:
                let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.isEmpty ? ProcessedText(text: text) : ProcessedText(text: cleaned)
            case .reminders:
                return parseReminder(output) ?? ProcessedText(text: text)
            case .calendar:
                return parseCalendar(output) ?? ProcessedText(text: text)
            }
        } catch {
            // 降级存原文：AI 不可用不应阻断本地保存。
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
        case .reminders:
            return style + """

                当前时间：\(Self.nowFormatter.string(from: now()))
                此外，从文字中解析出到期时间：识别「明天下午三点」「周五」「10 分钟后」、"tomorrow at 3 pm"、"Friday" 等相对或具体时间，以当前时间为基准换算。
                只输出一个严格 JSON 对象，不要额外说明、不要用代码块包裹，形如：
                {"text": "整理后的正文（首行为标题）", "due": "2026-09-24T15:00:00"}
                没有明确到期时间时，due 用 null。due 用本地时间、格式严格为 yyyy-MM-dd'T'HH:mm:ss。
                """
        case .calendar:
            return style + """

                当前时间：\(Self.nowFormatter.string(from: now()))
                此外，从文字中解析出日程的开始与结束时间：识别「明天下午三点」「周五下午两点到三点」「下周三晚上」、"tomorrow at 3 pm"、"Friday from 2 to 3 pm" 等相对或具体时间，以当前时间为基准换算。
                只输出一个严格 JSON 对象，不要额外说明、不要用代码块包裹，形如：
                {"text": "整理后的正文（首行为标题）", "start": "2026-09-24T15:00:00", "end": "2026-09-24T16:00:00"}
                没有明确开始时间时，start 用 null；原文没提结束时间时，end 用 null（由应用按默认时长处理，不要自行假设）。
                start / end 用本地时间、格式严格为 yyyy-MM-dd'T'HH:mm:ss。
                """
        }
    }

    // MARK: - 解析

    /// 解析提醒事项的 JSON 输出；任何不符即返回 nil，交由上层降级。
    private func parseReminder(_ output: String) -> ProcessedText? {
        let stripped = Self.stripCodeFence(output)
        guard let data = stripped.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = (object["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        let due = (object["due"] as? String).flatMap { Self.dueFormatter.date(from: $0) }
        return ProcessedText(text: text, due: due)
    }

    /// 解析日历日程的 JSON 输出；任何不符即返回 nil，交由上层降级。
    /// end 允许缺省（模型被要求不自行假设时长），由 action 层回退为开始 + 1 小时。
    private func parseCalendar(_ output: String) -> ProcessedText? {
        let stripped = Self.stripCodeFence(output)
        guard let data = stripped.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = (object["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        let start = (object["start"] as? String).flatMap { Self.dueFormatter.date(from: $0) }
        let end = (object["end"] as? String).flatMap { Self.dueFormatter.date(from: $0) }
        return ProcessedText(text: text, start: start, end: end)
    }

    /// 防御性剥掉模型可能违规套上的 ```json ... ``` 围栏。
    private static func stripCodeFence(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        if let firstNewline = trimmed.firstIndex(of: "\n") {
            trimmed = String(trimmed[trimmed.index(after: firstNewline)...])
        }
        if let fence = trimmed.range(of: "```", options: .backwards) {
            trimmed = String(trimmed[..<fence.lowerBound])
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 当前时间（喂给模型的基准），本地时区、贴近日常表达。
    private static let nowFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm EEEE"
        return formatter
    }()

    /// 解析模型返回的 due（无时区，按本地时区解释）。
    private static let dueFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()
}
