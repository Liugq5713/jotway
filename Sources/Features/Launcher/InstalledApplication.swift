import Foundation

/// 搜索结果直接来自本机应用包；只保留名称和路径，图标由 NSWorkspace 按需读取。
struct InstalledApplication: Identifiable, Sendable {
    let url: URL
    let name: String
    let searchNames: [String]
    let bundleIdentifier: String?
    private let searchTerms: [(name: String, text: String)]
    var id: URL { url }
    /// 目录扫描时预计算的检索词（原名、拼音全拼与首字母），主输入的前缀匹配复用这份结果。
    var searchTexts: [String] { searchTerms.map(\.text) }

    init(url: URL, name: String, searchNames: [String], bundleIdentifier: String? = nil) {
        self.url = url.resolvingSymlinksInPath()
        self.name = name
        self.searchNames = searchNames
        self.bundleIdentifier = bundleIdentifier
        // 读取目录时生成拼音，避免每次按键都重新转写全部应用名称。
        searchTerms = ([name] + searchNames).flatMap { alias in
            var terms = [(name: alias, text: alias)]
            if alias.range(of: "\\p{Han}", options: .regularExpression) != nil,
               let latin = alias.applyingTransform(.toLatin, reverse: false) {
                let syllables = latin.folding(options: .diacriticInsensitive, locale: nil)
                    .split(whereSeparator: \.isWhitespace)
                terms.append((name: alias, text: syllables.joined()))
                terms.append((name: alias, text: syllables.compactMap(\.first).map(String.init).joined()))
            }
            return terms.map { term in
                (name: term.name, text: term.text.filter { !$0.isWhitespace && $0 != "'" && $0 != "’" })
            }
        }
    }

    func matches(_ query: String) -> Bool {
        matchedName(for: query) != nil
    }

    func matchedName(for query: String) -> String? {
        let query = query.filter { !$0.isWhitespace && $0 != "'" && $0 != "’" }
        guard !query.isEmpty else { return name }
        return searchTerms.first {
            $0.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }?.name
    }
}
