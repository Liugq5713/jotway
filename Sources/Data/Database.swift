import Foundation
import GRDB

/// App 数据落盘位置。
enum StorageLocation {
    /// Sandbox 容器内 Application Support/Jotway
    static var appSupport: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Jotway", isDirectory: true)
    }
}

/// Jotway 的独立数据库定义；后续 schema 变更追加迁移。
enum Database {
    static func makeQueue(inMemory: Bool = false) throws -> DatabaseQueue {
        let queue: DatabaseQueue
        if inMemory {
            queue = try DatabaseQueue()
        } else {
            let dir = StorageLocation.appSupport
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            queue = try DatabaseQueue(path: dir.appendingPathComponent("jotway.sqlite").path)
        }
        try migrate(queue)
        return queue
    }

    static func migrate(_ queue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_launcher") { db in
            try db.create(table: ApplicationUsage.databaseTableName) { t in
                t.column("path", .text).primaryKey()
                t.column("openCount", .integer).notNull()
                t.column("lastOpenedAt", .datetime).notNull()
            }
            try db.execute(sql: """
                CREATE TABLE intent_feedback (id TEXT PRIMARY KEY, sample BLOB NOT NULL, execution BLOB NOT NULL);
                CREATE TABLE intent_corrections (
                    id TEXT PRIMARY KEY,
                    correctedAt DATETIME NOT NULL,
                    data BLOB NOT NULL
                );
                CREATE INDEX intent_corrections_recent ON intent_corrections(correctedAt DESC, id DESC);
                """)
        }
        try migrator.migrate(queue)
    }
}
