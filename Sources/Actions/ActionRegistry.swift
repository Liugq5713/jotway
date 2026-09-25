import Foundation
import Observation

/// Action 模块的唯一目录。宿主从这里读取设置、配置入口、可执行快照与配置修订。
@MainActor @Observable
final class ActionRegistry {
    static let didChangeNotification = Notification.Name("ActionRegistry.didChange")

    private struct RegisteredModule {
        let module: any ActionModule
        let instanceID: UUID
    }

    private var registered: [RegisteredModule] = []
    private var disabledIDs: Set<String> = []
    private(set) var revision = 0
    private(set) var currentUserRules: [IntentRule] = []

    init(modules: [any ActionModule] = []) {
        for module in modules { register(module) }
    }

    /// 同 ID 替换保持顺序，但配置身份必须更新，旧预热结果因而不能复用。
    func register(_ module: any ActionModule) {
        let id = module.descriptor.id
        precondition(!id.isEmpty, "Action module id must not be empty")
        let entry = RegisteredModule(module: module, instanceID: UUID())
        if let index = registered.firstIndex(where: { $0.module.descriptor.id == id }) {
            registered[index].module.onChange = nil
            registered[index] = entry
        } else {
            registered.append(entry)
        }
        module.onChange = { [weak self] in self?.moduleDidChange(id: id) }
        publishChange()
    }

    func unregister(id: String) {
        guard let index = registered.firstIndex(where: { $0.module.descriptor.id == id }) else { return }
        registered[index].module.onChange = nil
        registered.remove(at: index)
        disabledIDs.remove(id)
        publishChange()
    }

    var allDescriptors: [ActionDescriptor] { registered.map(\.module.descriptor) }

    func descriptor(for id: String) -> ActionDescriptor? {
        registered.first { $0.module.descriptor.id == id }?.module.descriptor
    }

    func settingsEntries() -> [ActionSettingsEntry] {
        registered.map { entry in
            ActionSettingsEntry(descriptor: entry.module.descriptor, state: entry.module.state,
                                isEnabled: isEnabled(entry.module.descriptor.id),
                                hasSettings: entry.module.settings != nil)
        }
    }

    func settingsEntry(for id: String) -> ActionSettingsEntry? {
        settingsEntries().first { $0.id == id }
    }

    func settings(for id: String) -> ActionSettings? {
        registered.first { $0.module.descriptor.id == id }?.module.settings
    }

    func refreshAvailability() {
        for entry in registered { entry.module.refreshAvailability() }
    }

    func executionSnapshots() -> [ActionExecutionSnapshot] {
        registered.compactMap(makeExecutionSnapshot)
    }

    func executionSnapshot(for id: String) -> ActionExecutionSnapshot? {
        registered.first { $0.module.descriptor.id == id }.flatMap(makeExecutionSnapshot)
    }

    /// Configuration is a selectable route, never an executable or model-facing action.
    func setupSnapshots() -> [ActionSetupSnapshot] {
        registered.compactMap { entry in
            guard isEnabled(entry.module.descriptor.id), !entry.module.state.availability.isReady,
                  let setup = entry.module.setup else { return nil }
            return ActionSetupSnapshot(descriptor: entry.module.descriptor,
                                       moduleInstance: entry.instanceID, setup: setup)
        }
    }

    func setupSnapshot(for id: String) -> ActionSetupSnapshot? {
        setupSnapshots().first { $0.id == id }
    }

    func containsModule(id: String, instance: UUID) -> Bool {
        isEnabled(id) && registered.contains { $0.module.descriptor.id == id && $0.instanceID == instance }
    }

    var fallbackSetupActionID: String? {
        setupSnapshots().enumerated().compactMap { index, snapshot -> (Int, Int, String)? in
            snapshot.descriptor.fallbackPriority.map { ($0, index, snapshot.id) }
        }.min { lhs, rhs in
            lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
        }?.2
    }

    var fallbackActionID: String? {
        executionSnapshots().enumerated().compactMap { index, snapshot -> (Int, Int, String)? in
            snapshot.descriptor.fallbackPriority.map { ($0, index, snapshot.id) }
        }.min { lhs, rhs in
            lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
        }?.2
    }

    func isEnabled(_ id: String) -> Bool {
        guard let descriptor = descriptor(for: id) else { return false }
        switch descriptor.enablementPolicy {
        case .alwaysEnabled: return true
        case .userToggle: return !disabledIDs.contains(id)
        }
    }

    func setEnabled(_ enabled: Bool, id: String) {
        guard case .userToggle = descriptor(for: id)?.enablementPolicy else { return }
        let changed = enabled ? disabledIDs.remove(id) != nil : disabledIDs.insert(id).inserted
        if changed { publishChange() }
    }

    func setUserRules(_ rules: [IntentRule]) {
        guard rules != currentUserRules else { return }
        currentUserRules = rules
        publishChange()
    }

    /// 密钥、共享处理器等不属于单个模块的执行依赖变化时，使全部未提交快照失效。
    func invalidateSharedConfiguration() {
        publishChange()
    }

    var hasSavedModuleConfiguration: Bool {
        registered.contains { $0.module.state.hasSavedConfiguration }
    }

    private func makeExecutionSnapshot(_ entry: RegisteredModule) -> ActionExecutionSnapshot? {
        let module = entry.module
        guard isEnabled(module.descriptor.id), module.state.availability.isReady else { return nil }
        let action = module.makeAction()
        precondition(action.descriptor.id == module.descriptor.id, "Action and module ids must match")
        return ActionExecutionSnapshot(
            id: module.descriptor.id,
            descriptor: module.descriptor,
            configurationIdentity: .init(moduleInstance: entry.instanceID,
                                         revision: module.state.configurationRevision,
                                         registryRevision: revision),
            action: action)
    }

    private func moduleDidChange(id: String) {
        guard registered.contains(where: { $0.module.descriptor.id == id }) else { return }
        publishChange()
    }

    private func publishChange() {
        revision &+= 1
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
