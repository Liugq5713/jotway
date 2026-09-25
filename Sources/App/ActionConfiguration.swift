import Foundation
import Observation

/// 所有 action 共用的启用偏好与用户分流规则。专用配置由各模块自行拥有。
@MainActor @Observable
final class ActionConfiguration {
    private static let intentRulesKey = "intentRules"

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

        let rules = preferences.data(forKey: Self.intentRulesKey)
            .flatMap { try? JSONDecoder().decode([IntentRule].self, from: $0) } ?? []
        removeInvalidActionConfiguration(rules: rules)
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

    var intentRules: [IntentRule] {
        _ = configurationRevision
        return registry.currentUserRules
    }

    func addIntentRule(phrase: String, actionID: String) {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, registry.descriptor(for: actionID) != nil else { return }
        var rules = registry.currentUserRules.filter { $0.phrase.caseInsensitiveCompare(trimmed) != .orderedSame }
        rules.append(IntentRule(phrase: trimmed, actionID: actionID))
        persistIntentRules(rules)
    }

    func removeIntentRule(id: UUID) {
        persistIntentRules(registry.currentUserRules.filter { $0.id != id })
    }

    var hasSavedActionConfiguration: Bool {
        if registry.hasSavedModuleConfiguration || preferences.object(forKey: Self.intentRulesKey) != nil { return true }
        return registry.allDescriptors.contains { descriptor in
            guard case .userToggle = descriptor.enablementPolicy else { return false }
            return preferences.object(forKey: "actionEnabled.\(descriptor.id)") != nil
        }
    }

    private func persistIntentRules(_ rules: [IntentRule]) {
        if let data = try? JSONEncoder().encode(rules) { preferences.set(data, forKey: Self.intentRulesKey) }
        registry.setUserRules(rules)
        configurationRevision &+= 1
    }

    private func removeInvalidActionConfiguration(rules: [IntentRule]) {
        let registeredIDs = Set(registry.allDescriptors.map(\.id))
        let prefix = "actionEnabled."
        for key in preferences.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            let id = String(key.dropFirst(prefix.count))
            if !registeredIDs.contains(id) { preferences.removeObject(forKey: key) }
        }
        let validRules = rules.filter { registeredIDs.contains($0.actionID) }
        if validRules.count != rules.count, let value = try? JSONEncoder().encode(validRules) {
            preferences.set(value, forKey: Self.intentRulesKey)
        }
        registry.setUserRules(validRules)
    }
}
