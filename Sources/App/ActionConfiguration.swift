import Foundation
import Observation

/// 所有 action 共用的启用偏好。专用配置由各模块自行拥有。
@MainActor @Observable
final class ActionConfiguration {
    let registry: ActionRegistry
    private let preferences: UserDefaults
    private var configurationRevision = 0

    init(preferences: UserDefaults, modules: [any ActionModule]) {
        self.preferences = preferences
        registry = ActionRegistry(modules: modules)

        for descriptor in registry.allDescriptors {
            guard case .userToggle(let defaultEnabled) = descriptor.enablementPolicy else { continue }
            let key = "actionEnabled.\(descriptor.id)"
            let enabled = preferences.object(forKey: key) == nil ? defaultEnabled : preferences.bool(forKey: key)
            registry.setEnabled(enabled, id: descriptor.id)
        }

    }

    func isActionEnabled(_ id: String) -> Bool {
        _ = configurationRevision
        return registry.isEnabled(id)
    }

    func setActionEnabled(_ enabled: Bool, for id: String) {
        guard case .userToggle = registry.descriptor(for: id)?.enablementPolicy else { return }
        preferences.set(enabled, forKey: "actionEnabled.\(id)")
        registry.setEnabled(enabled, id: id)
        configurationRevision &+= 1
    }

    var hasSavedActionConfiguration: Bool {
        if registry.hasSavedModuleConfiguration { return true }
        return registry.allDescriptors.contains { descriptor in
            guard case .userToggle = descriptor.enablementPolicy else { return false }
            return preferences.object(forKey: "actionEnabled.\(descriptor.id)") != nil
        }
    }

}
