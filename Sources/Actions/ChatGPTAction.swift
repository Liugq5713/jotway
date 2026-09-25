import AppKit
import Observation

@MainActor @Observable
final class ChatGPTModule: ActionModule {
    nonisolated static let moduleDescriptor = ActionDescriptor(
        id: "chatgpt", title: "Open in ChatGPT", settingsName: "ChatGPT",
        summary: "Open a new chat with your text, then send it in ChatGPT.",
        titleKey: "action.chatgpt.title", settingsNameKey: "action.chatgpt.settings_name",
        summaryKey: "action.chatgpt.summary", systemImageName: "bubble.left.and.bubble.right", tint: .blue,
        settingsGroup: .init(id: "conversation", title: "Conversations", order: 200,
                             titleKey: "actions.group.conversation"),
        enablementPolicy: .userToggle(defaultEnabled: true), fallbackPriority: nil,
        intentHints: IntentHints(localKeywords: ["问 ChatGPT ", "问ChatGPT ", "ChatGPT:", "ChatGPT：",
                                                "Codex:", "Codex："], modelBinding: .none),
        presentationPolicy: .keepDestinationFrontmost)

    let descriptor = ChatGPTModule.moduleDescriptor
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    private let locate: ChatGPTAction.Locate
    private let isCompatible: ChatGPTAction.CheckCompatibility
    private let open: ChatGPTAction.Open
    private(set) var isAvailable: Bool

    init(locate: @escaping ChatGPTAction.Locate = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
         }, isCompatible: @escaping ChatGPTAction.CheckCompatibility = { application in
            // Read metadata afresh so replacement or removal after preparation is detected.
            let infoURL = application.appendingPathComponent("Contents/Info.plist")
            guard let data = try? Data(contentsOf: infoURL),
                  let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  info["CFBundleIdentifier"] as? String == "com.openai.codex",
                  let types = info["CFBundleURLTypes"] as? [[String: Any]] else { return false }
            return types.contains { type in
                (type["CFBundleURLSchemes"] as? [String])?.contains {
                    $0.caseInsensitiveCompare("codex") == .orderedSame
                } == true
            }
         }, open: @escaping ChatGPTAction.Open = { url, application, configuration in
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: application, configuration: configuration)
         }) {
        self.locate = locate
        self.isCompatible = isCompatible
        self.open = open
        isAvailable = locate().map(isCompatible) ?? false
    }

    var state: ActionModuleState {
        .init(configurationRevision: 0,
              availability: isAvailable ? .ready : .unavailable(message: L10n.text("action.chatgpt.missing")),
              summary: isAvailable ? descriptor.localizedSummary : L10n.text("action.chatgpt.missing"),
              hasSavedConfiguration: false)
    }

    var settings: ActionSettings? { nil }

    func refreshAvailability() {
        let next = locate().map(isCompatible) ?? false
        guard next != isAvailable else { return }
        isAvailable = next
        onChange?()
    }

    func makeAction() -> any LauncherAction {
        ChatGPTAction(locate: locate, isCompatible: isCompatible, open: open)
    }
}

/// Preparation freezes the full prompt; only confirmation opens the destination application.
struct ChatGPTAction: LauncherAction {
    typealias Locate = @MainActor @Sendable () -> URL?
    typealias CheckCompatibility = @MainActor @Sendable (URL) -> Bool
    typealias Open = @MainActor @Sendable (URL, URL, NSWorkspace.OpenConfiguration) async throws -> Void

    let descriptor = ChatGPTModule.moduleDescriptor
    let locate: Locate
    let isCompatible: CheckCompatibility
    let open: Open

    func prepare(_ input: ActionInput) async throws -> PreparedAction {
        let url = try chatGPTURL(for: input.text)
        return PreparedAction(actionID: descriptor.id, inputIdentity: input.identity) {
            guard let application = locate(), isCompatible(application) else {
                throw ActionFailure(localized: "action.chatgpt.missing", code: .unavailable)
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.createsNewApplicationInstance = false
            configuration.allowsRunningApplicationSubstitution = false
            configuration.promptsUserIfNeeded = false
            do {
                try await open(url, application, configuration)
                return ActionOutcome(messageKey: "action.chatgpt.opened")
            } catch {
                throw ActionFailure(localized: "action.chatgpt.open_failed", code: RuntimeLog.code(error))
            }
        }
    }
}

private func chatGPTURL(for content: String) throws -> URL {
    let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let prompt = content.addingPercentEncoding(withAllowedCharacters: unreserved),
          let url = URL(string: "codex://new?prompt=" + prompt),
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let items = components.queryItems, items.count == 1,
          items[0].name == "prompt", let decoded = items[0].value,
          decoded.utf8.elementsEqual(content.utf8) else {
        throw ActionFailure(localized: "action.chatgpt.invalid_text", code: .validation)
    }
    return url
}
