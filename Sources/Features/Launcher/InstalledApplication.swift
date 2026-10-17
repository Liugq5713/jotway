import Foundation
import CryptoKit

/// 搜索结果直接来自本机应用包；只保留名称和路径，图标由 NSWorkspace 按需读取。
struct InstalledApplication: Identifiable, Sendable {
    let url: URL
    let name: String
    let searchNames: [String]
    let bundleIdentifier: String?
    let searchProfile: ApplicationSearchProfile
    let launcherID: String
    var id: URL { url }
    /// 目录扫描时预计算的检索词（原名、拼音全拼与首字母），主输入的分级匹配复用这份结果。
    var searchTexts: [String] { searchProfile.terms.map(\.compact) }

    init(url: URL, name: String, searchNames: [String], bundleIdentifier: String? = nil) {
        self.url = url.resolvingSymlinksInPath()
        self.name = name
        self.searchNames = searchNames
        self.bundleIdentifier = bundleIdentifier
        searchProfile = ApplicationSearchProfile(names: [name] + searchNames)
        let digest = SHA256.hash(data: Data(self.url.path.utf8))
        launcherID = "app_" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    func matches(_ query: String) -> Bool {
        matchedName(for: query) != nil
    }

    func matchedName(for query: String) -> String? {
        let query = ApplicationSearchProfile.compact(ApplicationSearchProfile.normalize(query))
        guard !query.isEmpty else { return name }
        return searchProfile.terms.first { $0.compact.contains(query) }?.name
    }
}
