import Foundation

struct TemplateExpansion: Equatable, Sendable {
    struct Field: Equatable, Sendable {
        let number: Int
        var range: NSRange
    }
    struct Failure: Error, LocalizedError {
        let position: Int
        var errorDescription: String? { L10n.text("templates.invalid_syntax", position + 1) }
    }
    let text: String
    let fields: [Field]
    let finalPosition: Int
    var firstSelection: NSRange { fields.first?.range ?? NSRange(location: finalPosition, length: 0) }

    static func parse(_ source: String) throws -> Self {
        let units = Array(source.utf16)
        var i = 0, output: [UInt16] = [], fields: [Field] = [], final: Int?
        var numbers = Set<Int>()
        func fail(_ position: Int) -> Failure { Failure(position: position) }
        func escaped(_ index: inout Int, into value: inout [UInt16], inDefault: Bool) -> Bool {
            guard units[index] == 92, index + 1 < units.count,
                  units[index + 1] == 36 || units[index + 1] == 92 || (inDefault && units[index + 1] == 125) else { return false }
            value.append(units[index + 1]); index += 2; return true
        }
        while i < units.count {
            if escaped(&i, into: &output, inDefault: false) { continue }
            guard units[i] == 36, i + 1 < units.count, units[i + 1] == 123 else {
                output.append(units[i]); i += 1; continue
            }
            let start = i
            i += 2
            let digits = i
            while i < units.count, (48...57).contains(units[i]) { i += 1 }
            guard i > digits, let number = Int(String(decoding: units[digits..<i], as: UTF16.self)),
                  i - digits == 1 || units[digits] != 48, i < units.count,
                  units[i] == 125 || units[i] == 58 else { throw fail(start) }
            guard numbers.insert(number).inserted else { throw fail(start) }
            let location = output.count
            if units[i] == 58 {
                guard number > 0 else { throw fail(start) }
                i += 1
                while i < units.count, units[i] != 125 {
                    if escaped(&i, into: &output, inDefault: true) { continue }
                    if units[i] == 36, i + 1 < units.count, units[i + 1] == 123 { throw fail(i) }
                    output.append(units[i]); i += 1
                }
            }
            guard i < units.count, units[i] == 125 else { throw fail(start) }
            i += 1
            if number == 0 { final = location }
            else { fields.append(Field(number: number, range: NSRange(location: location, length: output.count - location))) }
        }
        let text = String(decoding: output, as: UTF16.self)
        // Markers may sit next to combining characters. Use native composed-character boundaries.
        func safe(_ range: NSRange) -> NSRange {
            let value = text as NSString
            if range.length > 0 { return value.rangeOfComposedCharacterSequences(for: range) }
            guard range.location > 0, range.location < value.length else { return range }
            let composed = value.rangeOfComposedCharacterSequence(at: range.location)
            return NSRange(location: composed.location, length: 0)
        }
        fields = fields.map { Field(number: $0.number, range: safe($0.range)) }.sorted { $0.number < $1.number }
        return Self(text: text, fields: fields, finalPosition: safe(NSRange(location: final ?? output.count, length: 0)).location)
    }
}
