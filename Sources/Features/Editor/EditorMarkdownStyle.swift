import Foundation

/// Display-only ranges in one physical line; offsets use the editor's UTF-16 coordinates.
struct EditorMarkdownStyle {
    var markers: [NSRange] = []
    var heading: NSRange?

    static func parse(_ line: NSString) -> EditorMarkdownStyle {
        let newline = line.rangeOfCharacter(from: .newlines)
        let end = newline.location == NSNotFound ? line.length : newline.location
        guard end > 0 else { return EditorMarkdownStyle() }
        func isSpace(_ index: Int) -> Bool {
            index < end && (line.character(at: index) == 32 || line.character(at: index) == 9)
        }
        func boundary(_ index: Int) -> Bool { index == end || isSpace(index) }
        func skipSpace(_ start: Int) -> Int {
            var index = start
            while isSpace(index) { index += 1 }
            return index
        }
        func taskMarker(at start: Int) -> NSRange? {
            guard start + 3 <= end,
                  line.character(at: start) == 91, line.character(at: start + 1) == 32,
                  line.character(at: start + 2) == 93, boundary(start + 3) else { return nil }
            return NSRange(location: start, length: 3)
        }

        if line.character(at: 0) == 35 {
            let count = end > 1 && line.character(at: 1) == 35 ? 2 : 1
            guard isSpace(count) else { return EditorMarkdownStyle() }
            let start = skipSpace(count)
            return EditorMarkdownStyle(markers: [NSRange(location: 0, length: count)],
                                       heading: start < end ? NSRange(location: start, length: end - start) : nil)
        }
        if let task = taskMarker(at: 0) { return EditorMarkdownStyle(markers: [task]) }

        var prefixEnd = 0
        if line.character(at: 0) == 45 {
            prefixEnd = 1
        } else {
            while prefixEnd < end, (48...57).contains(line.character(at: prefixEnd)) { prefixEnd += 1 }
            guard prefixEnd > 0, prefixEnd < end, line.character(at: prefixEnd) == 46 else {
                return EditorMarkdownStyle()
            }
            prefixEnd += 1
        }
        guard boundary(prefixEnd) else { return EditorMarkdownStyle() }
        var result = EditorMarkdownStyle(markers: [NSRange(location: 0, length: prefixEnd)])
        if let task = taskMarker(at: skipSpace(prefixEnd)) { result.markers.append(task) }
        return result
    }
}
