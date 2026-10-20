import Foundation

/// Parsing primitives used by bounded Notes review responses.
enum NotesReviewResponseParser {
    static func normalizedParagraph(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func validLine(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && text.count <= 240 && text.utf8.count <= 960
            && !text.contains("://") && !text.contains("www.")
            && !text.contains("<") && !text.contains(">")
            && text.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0)
                && !CharacterSet.newlines.contains($0) }
    }

    /// Decode JSON directly, or find a balanced object/array inside Markdown or explanatory prose.
    /// Strings and escapes are tracked so braces inside generated text do not end the payload.
    static func jsonPayload(_ text: String) -> Any? {
        func decode(_ value: String) -> Any? {
            try? JSONSerialization.jsonObject(with: Data(value.utf8), options: [.fragmentsAllowed])
        }
        if let value = decode(text) { return value }
        var start: String.Index?
        var closing: [Character] = []
        var inString = false
        var escaped = false
        for index in text.indices {
            let character = text[index]
            if start == nil {
                guard character == "{" || character == "[" else { continue }
                start = index
                closing = [character == "{" ? "}" : "]"]
                continue
            }
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                continue
            }
            if character == "\"" { inString = true }
            else if character == "{" { closing.append("}") }
            else if character == "[" { closing.append("]") }
            else if character == "}" || character == "]" {
                guard character == closing.last else { start = nil; closing = []; continue }
                closing.removeLast()
                if closing.isEmpty, let beginning = start {
                    if let value = decode(String(text[beginning...index])) { return value }
                    start = nil
                }
            }
        }
        return nil
    }
}
