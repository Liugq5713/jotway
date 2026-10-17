import Foundation

/// Shared visible labels for writing Notes and recognizing an unverified generated boundary.
enum NotesContentFormat {
    static let divider = "────────────────────────────"
    static let chineseInsights = "AI 洞察"
    static let englishInsights = "AI Insights"
    static let chineseRelated = "相关内容"
    static let englishRelated = "Related Content"

    static func isHeading(_ text: String) -> Bool {
        [chineseInsights, englishInsights, chineseRelated, englishRelated].contains(text)
    }

    /// A divider followed by a blank line and a heading signals an uncertain tail,
    /// not a safe place to truncate. Ordinary headings alone are user content.
    static func hasUnverifiedBoundary(in text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        for index in lines.indices where lines[index] == divider {
            var next = index + 1
            guard next < lines.count, lines[next].isEmpty else { continue }
            while next < lines.count, lines[next].isEmpty { next += 1 }
            if next < lines.count, isHeading(lines[next]) { return true }
        }
        return false
    }
}
