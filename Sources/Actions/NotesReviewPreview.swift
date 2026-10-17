import Foundation

/// Bounded scanner for the review's JSON prefix. Only overview may be incomplete;
/// array items are exposed after a complete JSON value, never by repairing JSON.
enum NotesReviewPreview {
    static func object(in text: String) -> [String: Any]? {
        guard text.utf8.count <= 65_536 else { return nil }
        var scanner = Scanner(input: Array(text.unicodeScalars))
        return scanner.review()
    }

    private struct Scanner {
        enum ScanError: Error { case incomplete, invalid }
        let input: [Unicode.Scalar]
        var offset = 0

        mutating func whitespace() {
            while offset < input.count, [" ", "\n", "\r", "\t"].contains(input[offset]) { offset += 1 }
        }
        mutating func take(_ character: Unicode.Scalar) throws {
            whitespace()
            guard offset < input.count else { throw ScanError.incomplete }
            guard input[offset] == character else { throw ScanError.invalid }
            offset += 1
        }
        mutating func review() -> [String: Any]? {
            var result: [String: Any] = [:]
            var keys = Set<String>()
            do {
                try take("{")
                whitespace()
                if offset < input.count, input[offset] == "}" { return result }
                while true {
                    let key = try string().text
                    guard keys.insert(key).inserted else { throw ScanError.invalid }
                    try take(":")
                    whitespace()
                    guard offset < input.count else { return result }
                    if key == "overview", input[offset] == "\"" {
                        let value = try string(allowPrefix: true)
                        result[key] = value.text
                        if !value.complete { return result }
                    } else if ["themes", "unresolved"].contains(key), input[offset] == "[" {
                        offset += 1
                        var items: [Any] = []
                        result[key] = items
                        whitespace()
                        if offset < input.count, input[offset] == "]" { offset += 1 }
                        else {
                            while true {
                                let start = offset
                                do { try value(depth: 0) }
                                catch ScanError.incomplete { return result }
                                let raw = String(String.UnicodeScalarView(input[start..<offset]))
                                guard let item = try? JSONSerialization.jsonObject(with: Data(raw.utf8), options: [.fragmentsAllowed]) else {
                                    throw ScanError.invalid
                                }
                                items.append(item)
                                result[key] = items
                                whitespace()
                                guard offset < input.count else { return result }
                                if input[offset] == "]" { offset += 1; break }
                                try take(",")
                            }
                        }
                    } else { try value(depth: 0) }
                    whitespace()
                    guard offset < input.count else { return result }
                    if input[offset] == "}" {
                        offset += 1
                        whitespace()
                        return offset == input.count ? result : nil
                    }
                    try take(",")
                }
            } catch ScanError.incomplete { return result }
            catch { return nil }
        }

        mutating func string(allowPrefix: Bool = false) throws -> (text: String, complete: Bool) {
            try take("\"")
            var text = ""
            do {
                while offset < input.count {
                    let character = input[offset]
                    offset += 1
                    if character == "\"" { return (text, true) }
                    guard character.value >= 0x20 else { throw ScanError.invalid }
                    if character != "\\" { text.unicodeScalars.append(character); continue }
                    guard offset < input.count else { throw ScanError.incomplete }
                    let escape = input[offset]
                    offset += 1
                    switch escape {
                    case "\"", "\\", "/": text.unicodeScalars.append(escape)
                    case "b": text.append("\u{08}")
                    case "f": text.append("\u{0C}")
                    case "n": text.append("\n")
                    case "r": text.append("\r")
                    case "t": text.append("\t")
                    case "u":
                        let first = try hex()
                        var scalar = first
                        if (0xD800...0xDBFF).contains(first) {
                            guard offset + 2 <= input.count else { throw ScanError.incomplete }
                            guard input[offset] == "\\", input[offset + 1] == "u" else { throw ScanError.invalid }
                            offset += 2
                            let second = try hex()
                            guard (0xDC00...0xDFFF).contains(second) else { throw ScanError.invalid }
                            scalar = 0x10000 + (first - 0xD800) * 0x400 + second - 0xDC00
                        }
                        guard let decoded = Unicode.Scalar(scalar) else { throw ScanError.invalid }
                        text.unicodeScalars.append(decoded)
                    default: throw ScanError.invalid
                    }
                }
                throw ScanError.incomplete
            } catch ScanError.incomplete where allowPrefix { return (text, false) }
        }
        mutating func hex() throws -> UInt32 {
            var result: UInt32 = 0
            for _ in 0..<4 {
                guard offset < input.count else { throw ScanError.incomplete }
                guard let digit = UInt32(String(input[offset]), radix: 16) else { throw ScanError.invalid }
                result = result * 16 + digit
                offset += 1
            }
            return result
        }
        mutating func value(depth: Int) throws {
            guard depth < 64 else { throw ScanError.invalid }
            whitespace()
            guard offset < input.count else { throw ScanError.incomplete }
            switch input[offset] {
            case "\"": _ = try string()
            case "{", "[":
                let object = input[offset] == "{"
                let end: Unicode.Scalar = object ? "}" : "]"
                offset += 1
                whitespace()
                if offset < input.count, input[offset] == end { offset += 1; return }
                while true {
                    if object { _ = try string(); try take(":") }
                    try value(depth: depth + 1)
                    whitespace()
                    guard offset < input.count else { throw ScanError.incomplete }
                    if input[offset] == end { offset += 1; return }
                    try take(",")
                }
            default:
                let start = offset
                while offset < input.count, ![",", "}", "]", " ", "\n", "\r", "\t"].contains(input[offset]) { offset += 1 }
                guard offset < input.count else { throw ScanError.incomplete }
                let raw = String(String.UnicodeScalarView(input[start..<offset]))
                guard !raw.isEmpty,
                      (try? JSONSerialization.jsonObject(with: Data(raw.utf8), options: [.fragmentsAllowed])) != nil else { throw ScanError.invalid }
            }
        }
    }
}
