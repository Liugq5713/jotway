import Foundation
import GRDB

/// 一次用户对 Jev 判断的纠正：Jev 建议了某目标，用户最终确认了另一个目标。
/// 只在「偏离」时记录，仅本地，滚动保留最近 `retentionLimit` 条，永不外传。
struct IntentCorrection: Codable, Equatable, Sendable {
    /// 滚动保留上限；超过后按时间丢弃最早的。
    static let retentionLimit = 200

    let id: UUID
    let correctedAt: Date
    /// 草稿正文。仅本地存储，用于用户回看与后续沉淀规则。
    let text: String
    /// Jev 当时建议的目标 id（nil 表示 Jev 未给建议，用户主动指定了目标）。
    let jevTargetID: String?
    /// Jev 建议的展示文案，例如「Google 搜索」；无建议时为「无建议」。
    let jevLabel: String
    /// 用户实际选择的目标 id，例如 "chrome" / "apple-reminders" / "apple-notes" / "app_…"。
    let chosenTargetID: String
    /// 用户所选目标的展示文案，例如「存到提醒事项」。
    let chosenLabel: String
    /// 识别来源等诊断信息，便于后续分析（不含额外正文）。
    let recognition: IntentFeedback.Recognition?

    init(id: UUID = UUID(), correctedAt: Date = Date(), text: String,
         jevTargetID: String?, jevLabel: String, chosenTargetID: String, chosenLabel: String,
         recognition: IntentFeedback.Recognition? = nil) {
        self.id = id
        self.correctedAt = correctedAt
        self.text = text
        self.jevTargetID = jevTargetID
        self.jevLabel = jevLabel
        self.chosenTargetID = chosenTargetID
        self.chosenLabel = chosenLabel
        self.recognition = recognition
    }
}

extension LauncherStore {
    /// 插入一条纠正并把总量修剪到 `retentionLimit`（按 correctedAt/id 保留最新）。
    @discardableResult
    func saveIntentCorrection(_ correction: IntentCorrection) throws -> Bool {
        let data = try JSONEncoder().encode(correction)
        return try dbQueue.write { db in
            try db.execute(sql: "INSERT INTO intent_corrections(id, correctedAt, data) VALUES (?, ?, ?) ON CONFLICT(id) DO NOTHING",
                           arguments: [correction.id.uuidString, correction.correctedAt, data])
            guard db.changesCount == 1 else { return false }
            try db.execute(sql: """
                DELETE FROM intent_corrections WHERE id NOT IN (
                    SELECT id FROM intent_corrections ORDER BY correctedAt DESC, id DESC LIMIT ?
                )
                """, arguments: [IntentCorrection.retentionLimit])
            return true
        }
    }

    /// 最近的纠正，最新在前；供设置页只读列出。
    func recentIntentCorrections(limit: Int = IntentCorrection.retentionLimit) throws -> [IntentCorrection] {
        try dbQueue.read { db in
            try Data.fetchAll(db, sql: "SELECT data FROM intent_corrections ORDER BY correctedAt DESC, id DESC LIMIT ?",
                              arguments: [max(0, limit)])
                .compactMap { try? JSONDecoder().decode(IntentCorrection.self, from: $0) }
        }
    }

    func intentCorrectionCount() throws -> Int {
        try dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM intent_corrections") ?? 0 }
    }

    /// 用户在设置页清空全部纠正记录。
    func clearIntentCorrections() throws {
        _ = try dbQueue.write { db in try db.execute(sql: "DELETE FROM intent_corrections") }
    }
}
