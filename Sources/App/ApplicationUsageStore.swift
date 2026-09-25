import Foundation
import Observation

/// 应用打开排序与持久化重试；调用方只读当前快照并记录成功打开。
@MainActor @Observable
final class ApplicationUsageStore {
    private let store: LauncherStore
    private(set) var usage: [String: ApplicationUsage] = [:]
    private var pending: [String: ApplicationUsage] = [:]

    init(store: LauncherStore) {
        self.store = store
        do {
            usage = try store.applicationUsage()
        } catch {
            fputs("[Jotway] Failed to read application usage: \(error)\n", stderr)
        }
    }

    var hasPendingChanges: Bool { !pending.isEmpty }

    @discardableResult
    func recordOpen(_ url: URL, at date: Date = Date()) -> Bool {
        let path = url.resolvingSymlinksInPath().path
        var value = usage[path] ?? ApplicationUsage(path: path, openCount: 0, lastOpenedAt: date)
        value.openCount += 1
        value.lastOpenedAt = date
        usage[path] = value
        var increment = pending[path] ?? ApplicationUsage(path: path, openCount: 0, lastOpenedAt: date)
        increment.openCount += 1
        increment.lastOpenedAt = date
        pending[path] = increment
        return save()
    }

    @discardableResult
    func save() -> Bool {
        guard !pending.isEmpty else { return true }
        do {
            usage = try store.recordApplicationOpens(Array(pending.values))
            pending.removeAll()
            return true
        } catch {
            fputs("[Jotway] Failed to save application usage; keeping data for retry: \(error)\n", stderr)
            return false
        }
    }
}
