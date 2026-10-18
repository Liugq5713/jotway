import Foundation

/// Local provenance stores only fingerprints, never a second copy of a draft.
struct NotesOrigin: Sendable {
    let hash: String
    let length: Int
    let tailHash: String
    let tailLength: Int
    let formatVersion: Int

    init(original: String, generated: String = "", formatVersion: Int = 2) {
        let text = NotesOriginalText.canonical(original)
        let tail = NotesOriginalText.canonical(generated)
        hash = NotesTextHash.hash(text)
        length = text.count
        tailHash = NotesTextHash.hash(tail)
        tailLength = tail.count
        self.formatVersion = formatVersion
    }

    init(hash: String, length: Int, tailHash: String, tailLength: Int, formatVersion: Int) {
        self.hash = hash
        self.length = length
        self.tailHash = tailHash
        self.tailLength = tailLength
        self.formatVersion = formatVersion
    }

    func matchesOriginal(_ text: String) -> Bool {
        let value = NotesOriginalText.canonical(text)
        return value.count == length && NotesTextHash.hash(value) == hash
    }

    /// Both regions must account for the entire body. A prefix alone is not a boundary.
    func original(in text: String) -> String? {
        let value = NotesOriginalText.canonical(text)
        guard value.count == length + (tailLength > 0 ? 1 + tailLength : 0),
              tailLength == 0 || matchesTail(in: text) else { return nil }
        return originalPrefix(in: text)
    }

    private func originalPrefix(in text: String) -> String? {
        guard length > 0 else { return nil }
        var count = 0
        // Match normalized tokens, but return the corresponding raw prefix so paragraphs,
        // indentation and chunk offsets survive format-preserving readback.
        for word in text.split(whereSeparator: \.isWhitespace) {
            count += (count == 0 ? 0 : 1) + word.count
            if count > length { return nil }
            if count == length {
                let prefix = String(text[..<word.endIndex])
                return NotesTextHash.hash(NotesOriginalText.canonical(prefix)) == hash ? prefix : nil
            }
        }
        return nil
    }

    func matchesTail(in text: String) -> Bool {
        let value = NotesOriginalText.canonical(text)
        return tailLength > 0 && value.count >= tailLength
            && NotesTextHash.hash(String(value.suffix(tailLength))) == tailHash
    }
}

/// Display markup is not a persistence contract. Known notes need a complete fingerprint
/// match; surviving original regions must also agree. Ambiguous content is never embedded.
enum NotesOriginalText {
    static let headings = ["AI 补充", "历史相关思考（AI 整理）", "AI Suggestions", "AI Supplement", "Related History (AI)"]

    static func canonical(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func extract(_ body: NotesSourceBody, origin: NotesOrigin? = nil) throws -> String {
        guard body.text.utf8.count <= 2_000_000, body.html.utf8.count <= 4_000_000 else {
            throw NotesReadError.tooLarge
        }
        let text = readableText(body)
        let pattern = #"<pre\s+data-jotway-region="original"[^>]*><span>([\s\S]*?)</span></pre>"#
        let matches = try NSRegularExpression(pattern: pattern).matches(in: body.html, range: NSRange(body.html.startIndex..., in: body.html))
        if matches.count == 1, let range = Range(matches[0].range(at: 1), in: body.html) {
            let raw = String(body.html[range])
            // The writer escapes every literal angle bracket; nested markup means damage.
            guard !raw.contains("<") else { throw NotesReadError.ambiguous }
            let original = decodeEntities(raw)
            // A known marker may not silently expand over generated text, or conceal an
            // edited original behind its previously stored prefix. Skip uncertain edits.
            if let origin {
                guard origin.matchesOriginal(original), origin.original(in: text) != nil else {
                    throw NotesReadError.ambiguous
                }
            }
            // Compare the complete representations, not merely the old original prefix.
            if !body.text.isEmpty, canonical(text) != canonical(readableHTML(body.html)) {
                throw NotesReadError.ambiguous
            }
            return original
        }
        if body.html.contains("data-jotway-region=\"original\"") { throw NotesReadError.ambiguous }
        if let origin {
            guard let original = origin.original(in: text) else { throw NotesReadError.ambiguous }
            return original
        }
        // Daily titles can themselves look like legacy generated headings. Without the
        // complete daily ledger, none of this new format may enter legacy tail heuristics.
        if body.html.contains("data-jotway-region=\"daily-originals\"") { throw NotesReadError.ambiguous }
        if NotesContentFormat.hasUnverifiedBoundary(in: text) { throw NotesReadError.ambiguous }
        // Exact whole-line legacy headings, including generated-only notes starting at zero.
        // They are a compatibility fallback, not proof that arbitrary pasted AI is detectable.
        let lines = text.components(separatedBy: "\n")
        if let boundary = lines.firstIndex(where: { headings.contains($0.trimmingCharacters(in: .whitespaces)) }) {
            return lines[..<boundary].joined(separator: "\n")
        }
        if body.html.contains("data-jotway-region") || body.html.contains("jotway://notes/open") {
            throw NotesReadError.ambiguous
        }
        return text
    }

    static func readableText(_ body: NotesSourceBody) -> String {
        body.text.isEmpty ? readableHTML(body.html) : normalizedLines(body.text)
    }

    static func hasBoundaryEvidence(_ body: NotesSourceBody) -> Bool {
        body.html.contains("data-jotway-region") || body.html.contains("jotway://notes/open")
            || NotesContentFormat.hasUnverifiedBoundary(in: readableText(body))
            || normalizedLines(body.text.isEmpty ? readableHTML(body.html) : body.text).components(separatedBy: "\n")
                .contains { headings.contains($0.trimmingCharacters(in: .whitespaces)) }
    }

    private static func normalizedLines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    private static func readableHTML(_ html: String) -> String {
        let breaks = html.replacingOccurrences(of: #"(?i)<br\s*/?>|</(?:div|p|h[1-6]|pre|li|blockquote)\s*>"#,
                                               with: "\n", options: .regularExpression)
        return decodeEntities(breaks.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression))
    }

    private static func decodeEntities(_ text: String) -> String {
        var value = text
        if let regex = try? NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#) {
            for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
                guard let digits = Range(match.range(at: 1), in: value), let range = Range(match.range, in: value) else { continue }
                let token = String(value[digits])
                let number = token.hasPrefix("x") ? UInt32(token.dropFirst(), radix: 16) : UInt32(token)
                if let number, let scalar = UnicodeScalar(number) { value.replaceSubrange(range, with: String(scalar)) }
            }
        }
        return value.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'").replacingOccurrences(of: "&amp;", with: "&")
    }
}
