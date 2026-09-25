import AppKit

/// Google 搜索的纯发送函数：拼 URL、用 Chrome 打开。发送即结束，无落库与状态机。
enum ChromeConnector {
    typealias Open = @MainActor @Sendable (URL, URL, NSWorkspace.OpenConfiguration) async throws -> Void

    static func searchURL(for content: String) throws -> URL {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ActionFailure(localized: "error.chrome.empty_query", code: .validation)
        }
        // Chromium url::kMaxURLChars limits URLs sent between processes (url/url_constants.h).
        let maximumURLLength = 2 * 1024 * 1024
        let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        guard content.utf8.count <= maximumURLLength,
              let query = content.addingPercentEncoding(withAllowedCharacters: unreserved) else {
            throw ActionFailure(localized: "error.chrome.encoding", code: .validation)
        }
        let address = "https://www.google.com/search?q=" + query
        guard address.utf8.count <= maximumURLLength else {
            throw ActionFailure(localized: "error.chrome.url_too_long", code: .inputTooLarge)
        }
        guard let url = URL(string: address) else {
            throw ActionFailure(localized: "error.chrome.url_failed", code: .validation)
        }
        return url
    }

    @MainActor
    static func openSearch(_ url: URL, application: URL, using open: Open) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        configuration.allowsRunningApplicationSubstitution = false
        configuration.promptsUserIfNeeded = false
        try await open(url, application, configuration)
    }
}
