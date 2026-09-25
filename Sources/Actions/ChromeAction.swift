import AppKit
import Observation

@MainActor @Observable
final class ChromeModule: ActionModule {
    nonisolated static let moduleDescriptor = ActionDescriptor(
        id: "chrome", title: "Google Search", settingsName: "Chrome Search",
        summary: "Open a Google search in Chrome.",
        titleKey: "action.chrome.title", settingsNameKey: "action.chrome.settings_name",
        summaryKey: "action.chrome.summary", systemImageName: "globe", tint: .green,
        settingsGroup: .init(id: "search", title: "Search", order: 100),
        enablementPolicy: .userToggle(defaultEnabled: true), fallbackPriority: nil,
        intentHints: IntentHints(localKeywords: ["google 搜", "谷歌搜", "chrome 搜",
                                                       "search google", "google search"], modelBinding: .webSearch),
        presentationPolicy: .keepDestinationFrontmost)

    let descriptor = ChromeModule.moduleDescriptor
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    private let locate: @MainActor @Sendable () -> URL?
    private let open: ChromeConnector.Open
    private(set) var chromeIsAvailable: Bool

    init(locate: @escaping @MainActor @Sendable () -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome")
         }, open: @escaping ChromeConnector.Open = { url, application, configuration in
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: application, configuration: configuration)
         }) {
        self.locate = locate
        self.open = open
        chromeIsAvailable = locate() != nil
    }

    var state: ActionModuleState {
        let availability: ActionAvailability = chromeIsAvailable
            ? .ready : .unavailable(message: L10n.text("action.state.chrome_missing"))
        return .init(configurationRevision: 0, availability: availability,
              summary: chromeIsAvailable ? descriptor.localizedSummary : L10n.text("action.state.chrome_missing"),
              hasSavedConfiguration: false)
    }
    var settings: ActionSettings? { nil }
    func refreshAvailability() {
        let next = locate() != nil
        guard next != chromeIsAvailable else { return }
        chromeIsAvailable = next
        onChange?()
    }
    func makeAction() -> any LauncherAction {
        ChromeAction(descriptor: descriptor, locate: locate, open: open)
    }
}

/// Google 搜索（连接器归一后的 fire-and-forget action）。
///
/// 与备忘录 / 提醒事项一样是 `LauncherAction`；执行时复用 `ChromeConnector` 的纯发送函数
/// （`searchURL(for:)` + `openSearch`）拼出搜索 URL 并用 Chrome 打开，成功即结束。
/// 搜索 action 在准备阶段冻结 URL，执行阶段只负责交给 Chrome。
struct ChromeAction: LauncherAction {
    let descriptor: ActionDescriptor

    /// Chrome 定位注入点：默认按 bundle id 查找，测试时替换。
    let locate: @MainActor @Sendable () -> URL?
    /// 打开注入点：默认走 `NSWorkspace`，测试时替换。
    let open: ChromeConnector.Open

    init(
        descriptor: ActionDescriptor = ChromeModule.moduleDescriptor,
        locate: @escaping @MainActor @Sendable () -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome")
        },
        open: @escaping ChromeConnector.Open = { url, application, configuration in
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: application, configuration: configuration)
        }
    ) {
        self.descriptor = descriptor
        self.locate = locate
        self.open = open
    }

    func prepare(_ input: ActionInput) async throws -> PreparedAction {
        let url = try ChromeConnector.searchURL(for: input.text)
        return PreparedAction(actionID: descriptor.id, inputIdentity: input.identity) {
            guard let application = locate() else {
                throw ActionFailure(localized: "error.chrome.not_found")
            }
            do {
                try await ChromeConnector.openSearch(url, application: application, using: open)
                return ActionOutcome(messageKey: "result.chrome.opened")
            } catch let failure as ActionFailure {
                throw failure
            } catch {
                throw ActionFailure(localized: "error.chrome.open_failed", code: RuntimeLog.code(error))
            }
        }
    }
}
