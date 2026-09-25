import Foundation

/// 用户在设置页手动加的分流规则：一段自然语言短语 → 一个 action id。
/// 命中优先于内置 localKeywords，也先于 Jev；优先级由 RouteResolver 统一解释。
/// 仅本地保存（UserDefaults JSON），永不外传。
struct IntentRule: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    /// 触发短语（已 trim）。默认「开头命中」：草稿以此开头即路由到 actionID。
    var phrase: String
    /// 命中后路由的目标 action id，例如 "apple-notes" / "chrome"。
    var actionID: String

    init(id: UUID = UUID(), phrase: String, actionID: String) {
        self.id = id
        self.phrase = phrase
        self.actionID = actionID
    }
}
