import SwiftUI

enum ActionAvailability: Sendable, Equatable {
    case ready
    case needsConfiguration(message: String)
    case unavailable(message: String)

    var message: String? {
        switch self {
        case .ready: nil
        case .needsConfiguration(let message), .unavailable(let message): message
        }
    }

    var isReady: Bool { self == .ready }
}

struct ActionModuleState: Sendable, Equatable {
    let configurationRevision: Int
    let availability: ActionAvailability
    let summary: String
    let hasSavedConfiguration: Bool
}

@MainActor
struct ActionSettings {
    let makeView: @MainActor () -> AnyView
}

@MainActor
protocol ActionModule: AnyObject {
    var descriptor: ActionDescriptor { get }
    var state: ActionModuleState { get }
    var settings: ActionSettings? { get }
    var onChange: (@MainActor () -> Void)? { get set }

    func refreshAvailability()
    func makeAction() -> any LauncherAction
}

struct ActionConfigurationIdentity: Hashable, Sendable {
    let moduleInstance: UUID
    let revision: Int
    let registryRevision: Int

    init(moduleInstance: UUID, revision: Int, registryRevision: Int = 0) {
        self.moduleInstance = moduleInstance
        self.revision = revision
        self.registryRevision = registryRevision
    }
}

struct ActionExecutionSnapshot: Sendable {
    let id: String
    let descriptor: ActionDescriptor
    let configurationIdentity: ActionConfigurationIdentity
    let action: any LauncherAction
}

struct ActionSettingsEntry: Identifiable, Equatable {
    let descriptor: ActionDescriptor
    let state: ActionModuleState
    let isEnabled: Bool
    let hasSettings: Bool

    var id: String { descriptor.id }
}
