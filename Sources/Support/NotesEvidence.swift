import Foundation

/// Pure checks shared by output validation and rendering.
enum NotesEvidence {
    static func comparisonText(_ text: String) -> String {
        text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }

    static func overlaps(_ lhs: String, _ rhs: String) -> Bool {
        let a = comparisonText(lhs), b = comparisonText(rhs)
        return !a.isEmpty && !b.isEmpty && (a.contains(b) || b.contains(a))
    }

    static func hasEvidence(_ text: String) -> Bool {
        let withoutTags = text.replacingOccurrences(of: #"#[\p{L}\p{N}_-]+"#, with: "", options: .regularExpression)
        let value = comparisonText(withoutTags)
        let vague = ["可以尝试优化", "可以尝试这个优化", "尝试优化", "trytooptimize", "couldimprovethis"]
        return value.count >= 8 && !vague.contains(value)
    }
}
