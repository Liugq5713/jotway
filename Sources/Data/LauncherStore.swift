import Foundation
import GRDB
/// 每个应用路径的使用累计值；不属于收件箱，也不保留逐次打开日志。
struct ApplicationUsage: Codable, FetchableRecord, TableRecord, Sendable {
    static let databaseTableName = "application_usage"
    let path: String
    var openCount: Int
    var lastOpenedAt: Date
}

/// 启动器数据层：应用使用统计、意图反馈和纠正。
struct LauncherStore: Sendable {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// 默认存储：App 容器内 Application Support/Jotway/jotway.sqlite
    static func makeDefault() throws -> LauncherStore {
        LauncherStore(dbQueue: try Database.makeQueue())
    }

    /// 降级方案：数据库初始化失败时的内存存储（进程退出即丢）
    static func inMemory() -> LauncherStore {
        // 全新内存库的迁移失败在实际中不可达
        // swiftlint:disable:next force_try
        try! LauncherStore(dbQueue: Database.makeQueue(inMemory: true))
    }

    // MARK: - 应用使用统计

    func applicationUsage() throws -> [String: ApplicationUsage] {
        try dbQueue.read { db in
            try Dictionary(uniqueKeysWithValues: ApplicationUsage.fetchAll(db).map { ($0.path, $0) })
        }
    }

    /// 增量与读取在同一事务中；失败保留调用方的增量，重试不会重复累计已提交数据。
    func recordApplicationOpens(_ increments: [ApplicationUsage]) throws -> [String: ApplicationUsage] {
        try dbQueue.write { db in
            for usage in increments {
                try db.execute(sql: """
                    INSERT INTO application_usage (path, openCount, lastOpenedAt) VALUES (?, ?, ?)
                    ON CONFLICT(path) DO UPDATE SET
                        openCount = application_usage.openCount + excluded.openCount,
                        lastOpenedAt = MAX(application_usage.lastOpenedAt, excluded.lastOpenedAt)
                    """, arguments: [usage.path, usage.openCount, usage.lastOpenedAt])
            }
            return try Dictionary(uniqueKeysWithValues: ApplicationUsage.fetchAll(db).map { ($0.path, $0) })
        }
    }
}
