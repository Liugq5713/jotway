import Foundation

/// 会话内的草稿身份；隐藏面板后保留，应用进程退出后清空。
struct RecordDraft: Codable, Equatable, Sendable {
    var id: UUID
    var content: String

    init(id: UUID = UUID(), content: String = "") {
        self.id = id; self.content = content
    }
}
