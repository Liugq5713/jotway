import Foundation
import Observation

/// 独立于 AI 补充与待办的意图识别配置。密钥只在实际使用时读取，不保存在观察状态中。
@MainActor @Observable
final class JevSettings {
    private enum KeyStatus {
        case notSaved
        case saved
        case removed
        case empty
        case error(String)
    }

    private enum ConnectionStatus {
        case saveKeyFirst
        case succeeded(String)
        case error(String)
    }
    static let shared = JevSettings()
    static let didChangeNotification = Notification.Name("JotwayJevSettingsDidChange")

    private(set) var revision = UUID()
    private(set) var hasAPIKey = false
    private var keyStatus: KeyStatus = .notSaved
    var status: String {
        switch keyStatus {
        case .notSaved: L10n.text("settings.key.not_saved")
        case .saved: L10n.text("settings.key.saved")
        case .removed: L10n.text("settings.key.removed")
        case .empty: L10n.text("jev.key.empty")
        case .error(let value): value
        }
    }
    private(set) var isTesting = false
    private var connectionStatus: ConnectionStatus?
    var connectionMessage: String? {
        switch connectionStatus {
        case .saveKeyFirst: L10n.text("jev.connection.save_key_first")
        case .succeeded(let model): L10n.text("jev.connection.succeeded", model)
        case .error(let value): value
        case nil: nil
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private let readKey: @MainActor () throws -> String?
    @ObservationIgnored private let writeKey: @MainActor (String) throws -> Void
    @ObservationIgnored private let deleteKey: @MainActor () throws -> Void
    @ObservationIgnored private let checkConnection: @MainActor (String) async throws -> String
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private var connectionRevision = UUID()
    @ObservationIgnored private var connectionTrace: JevTrace?

    init(defaults: UserDefaults = .standard,
         notificationCenter: NotificationCenter = .default,
         readKey: @escaping @MainActor () throws -> String? = { try Jev.loadAPIKey() },
         writeKey: @escaping @MainActor (String) throws -> Void = { try Jev.saveAPIKey($0) },
         deleteKey: @escaping @MainActor () throws -> Void = { try Jev.removeAPIKey() },
         checkConnection: @escaping @MainActor (String) async throws -> String = { try await Jev.testConnection(apiKey: $0) }) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.readKey = readKey
        self.writeKey = writeKey
        self.deleteKey = deleteKey
        self.checkConnection = checkConnection
    }

    func currentAPIKey() throws -> String? {
        guard let value = try readKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    func refreshKeyStatus() {
        do {
            hasAPIKey = try currentAPIKey() != nil
            keyStatus = hasAPIKey ? .saved : .notSaved
        } catch {
            hasAPIKey = false
            keyStatus = .error(error.localizedDescription)
        }
    }

    /// 开始编辑也要撤销旧测试；新文字只有明确保存后才替换本地凭证。
    func beginEditingAPIKey() {
        invalidateConnectionTest()
        configurationDidChange()
    }

    @discardableResult
    func saveAPIKey(_ value: String) -> Bool {
        invalidateConnectionTest()
        defer { configurationDidChange() }
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            keyStatus = .empty
            return false
        }
        do {
            try writeKey(key)
            hasAPIKey = true
            keyStatus = .saved
            return true
        } catch {
            keyStatus = .error(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func removeAPIKey() -> Bool {
        invalidateConnectionTest()
        defer { configurationDidChange() }
        do {
            try deleteKey()
            hasAPIKey = false
            keyStatus = .removed
            return true
        } catch {
            keyStatus = .error(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func testConnection() -> Task<Void, Never>? {
        guard !isTesting else { return nil }
        invalidateConnectionTest()
        let trace = JevTrace(purpose: .connectionTest)
        connectionTrace = trace
        let key: String
        do {
            guard let savedKey = try currentAPIKey() else {
                hasAPIKey = false
                connectionStatus = .saveKeyFirst
                trace.finish(.missingKey, outcome: .discarded)
                connectionTrace = nil
                return nil
            }
            key = savedKey
        } catch {
            trace.failed(error)
            connectionTrace = nil
            connectionStatus = .error(error.localizedDescription)
            return nil
        }

        let requestRevision = connectionRevision
        let checkConnection = checkConnection
        isTesting = true
        let task = Task { [weak self] in
            guard self?.connectionRevision == requestRevision, !Task.isCancelled else { return }
            do {
                let model = try await JevTrace.$current.withValue(trace) { try await checkConnection(key) }
                guard let self, self.connectionRevision == requestRevision, !Task.isCancelled else { return }
                trace.finish(.evaluated)
                self.connectionStatus = .succeeded(model)
                self.finishConnectionTest()
            } catch {
                trace.failed(error)
                guard let self, self.connectionRevision == requestRevision, !Task.isCancelled else { return }
                self.connectionStatus = .error(error.localizedDescription)
                self.finishConnectionTest()
            }
        }
        connectionTask = task
        return task
    }

    func invalidateConnectionTest() {
        connectionTrace?.finish(.cancelled, outcome: .cancelled)
        connectionTrace = nil
        connectionRevision = UUID()
        connectionTask?.cancel()
        connectionTask = nil
        isTesting = false
        connectionStatus = nil
    }

    private func finishConnectionTest() {
        connectionTrace = nil
        isTesting = false
        connectionTask = nil
    }

    isolated deinit {
        connectionTrace?.finish(.cancelled, outcome: .cancelled)
        connectionTask?.cancel()
    }

    private func configurationDidChange() {
        revision = UUID()
        notificationCenter.post(name: Self.didChangeNotification, object: self)
    }
}
