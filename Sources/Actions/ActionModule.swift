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

enum ActionSetupResult: Sendable, Equatable {
    case completed
    case cancelled
}

@MainActor
struct ActionSetup {
    let title: String
    let invalidate: @MainActor () -> Void
    let makeView: @MainActor (@escaping @MainActor (ActionSetupResult) -> Void) -> AnyView

    init(title: String, invalidate: @escaping @MainActor () -> Void = {},
         makeView: @escaping @MainActor (@escaping @MainActor (ActionSetupResult) -> Void) -> AnyView) {
        self.title = title
        self.invalidate = invalidate
        self.makeView = makeView
    }
}

@MainActor
struct ActionSetupSnapshot {
    let descriptor: ActionDescriptor
    let moduleInstance: UUID
    let setup: ActionSetup

    var id: String { descriptor.id }
}

@MainActor
struct ActionSetupRequest {
    let id: UUID
    let snapshot: ActionSetupSnapshot
}

@MainActor
protocol ActionModule: AnyObject {
    var descriptor: ActionDescriptor { get }
    var state: ActionModuleState { get }
    var settings: ActionSettings? { get }
    var setup: ActionSetup? { get }
    var onChange: (@MainActor () -> Void)? { get set }

    func refreshAvailability()
    func makeAction() -> any LauncherAction
}

extension ActionModule {
    var setup: ActionSetup? { nil }
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
