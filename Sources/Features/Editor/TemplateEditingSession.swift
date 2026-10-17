import Foundation

/// Native UTF-16 positions only; the editor owns this transient value.
struct TemplateEditingSession {
    private(set) var fields: [TemplateExpansion.Field]
    private(set) var index = 0
    private(set) var finalPosition: Int
    var currentRange: NSRange { fields[index].range }

    init?(_ expansion: TemplateExpansion) {
        guard !expansion.fields.isEmpty else { return nil }
        fields = expansion.fields; finalPosition = expansion.finalPosition
    }

    func contains(_ selection: NSRange) -> Bool {
        selection.location >= currentRange.location && NSMaxRange(selection) <= NSMaxRange(currentRange)
    }

    /// Returns false for crossing fields or edits outside the selected field and its preceding text.
    mutating func replace(_ range: NSRange, withUTF16Length length: Int) -> Bool {
        let current = currentRange
        let inside = contains(range)
        let before = NSMaxRange(range) <= current.location && range.location < current.location
        guard inside || before else { return false }
        for (offset, field) in fields.enumerated() where offset != index {
            if NSIntersectionRange(range, field.range).length > 0 ||
                (field.range.length == 0 && range.location < field.range.location && NSMaxRange(range) > field.range.location) { return false }
        }
        let delta = length - range.length
        for offset in fields.indices {
            if offset == index, inside { fields[offset].range.length += delta }
            else if fields[offset].range.location >= NSMaxRange(range) {
                fields[offset].range.location += delta
            }
        }
        if finalPosition >= NSMaxRange(range) { finalPosition += delta }
        else if finalPosition > range.location { finalPosition = range.location + length }
        return true
    }

    mutating func move(forward: Bool) -> (selection: NSRange, finished: Bool) {
        if forward, index + 1 == fields.count { return (NSRange(location: finalPosition, length: 0), true) }
        index = max(0, min(fields.count - 1, index + (forward ? 1 : -1)))
        return (currentRange, false)
    }
}
