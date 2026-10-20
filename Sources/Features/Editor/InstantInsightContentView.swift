import SwiftUI

/// A small, display-only Markdown subset. No links, attachments, HTML, or executable content.
struct InstantInsightContentView: View {
    private let blocks: [Block]

    init(text: String) { blocks = Self.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks.indices, id: \.self) { index in
                blockView(blocks[index])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .paragraph(let text):
            Text(Self.inline(text)).fixedSize(horizontal: false, vertical: true)
        case .literal(let text):
            Text(verbatim: text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        case .heading(let level, let text):
            Text(Self.inline(text, size: CGFloat(20 - level), bold: true))
                .fixedSize(horizontal: false, vertical: true)
        case .list(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 7) {
                        Text(verbatim: items[index].marker).font(.system(size: 13)).foregroundStyle(.secondary)
                        Text(Self.inline(items[index].text)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .code(let text):
            ScrollView(.horizontal) {
                Text(verbatim: text).font(.system(size: 12, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: true).padding(8)
            }
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 5))
        case .table(let rows):
            ScrollView(.horizontal) {
                Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 6) {
                    ForEach(rows.indices, id: \.self) { row in
                        GridRow {
                            ForEach(rows[row].indices, id: \.self) { column in
                                Text(Self.inline(rows[row][column], bold: row == 0))
                                    .fixedSize(horizontal: true, vertical: true)
                            }
                        }
                        if row == 0 { Divider().gridCellUnsizedAxes(.horizontal) }
                    }
                }.padding(8)
            }
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 5))
        }
    }

    private enum Block {
        case paragraph(String), literal(String), heading(Int, String), list([ListItem]), code(String), table([[String]])
    }
    private struct ListItem { let marker: String; let text: String }

    private static func parse(_ text: String) -> [Block] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [Block] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { index += 1; continue }
            if let fence = fenceStart(line) {
                let start = index
                index += 1
                let bodyStart = index
                while index < lines.count, !closesFence(lines[index], fence: fence) { index += 1 }
                if index == lines.count {
                    blocks.append(.literal(lines[start...].joined(separator: "\n")))
                } else {
                    blocks.append(.code(lines[bodyStart..<index].joined(separator: "\n")))
                    index += 1
                }
                continue
            }
            if let heading = heading(line) {
                blocks.append(.heading(heading.0, heading.1)); index += 1; continue
            }
            if index + 1 < lines.count, line.contains("|"), isTableSeparator(lines[index + 1]) {
                let start = index
                var rows = [tableCells(line)]
                let columns = tableCells(lines[index + 1]).count
                index += 2
                while index < lines.count, lines[index].contains("|"), fenceStart(lines[index]) == nil {
                    rows.append(tableCells(lines[index])); index += 1
                }
                // Complex/escaped pipes and malformed rows remain intact as literal content.
                let original = lines[start..<index]
                if columns > 0, rows.allSatisfy({ $0.count == columns }),
                   !original.contains(where: { $0.contains("\\|") || $0.contains("`") }) {
                    blocks.append(.table(rows))
                } else { blocks.append(.literal(original.joined(separator: "\n"))) }
                continue
            }
            if listItem(line.trimmingCharacters(in: .whitespaces)) != nil {
                let start = index
                var items: [ListItem] = []
                var flat = true
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    let current = lines[index]
                    if let item = listItem(current) { items.append(item) }
                    else if current.first?.isWhitespace == true { flat = false }
                    else { break }
                    index += 1
                }
                blocks.append(flat ? .list(items) : .literal(lines[start..<index].joined(separator: "\n")))
                continue
            }
            let start = index
            index += 1
            while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty,
                  fenceStart(lines[index]) == nil, heading(lines[index]) == nil,
                  listItem(lines[index].trimmingCharacters(in: .whitespaces)) == nil {
                if index + 1 < lines.count, lines[index].contains("|"), isTableSeparator(lines[index + 1]) { break }
                index += 1
            }
            blocks.append(.paragraph(lines[start..<index].joined(separator: "\n")))
        }
        return blocks
    }

    private static func fenceStart(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let marker = String(trimmed.prefix(while: { $0 == first }))
        return marker.count >= 3 ? marker : nil
    }

    private static func closesFence(_ line: String, fence: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let marker = trimmed.prefix(while: { $0 == fence.first })
        return marker.count >= fence.count && marker.count == trimmed.count
    }

    private static func heading(_ line: String) -> (Int, String)? {
        let marker = line.prefix(while: { $0 == "#" })
        let remainder = line.dropFirst(marker.count)
        guard (1...6).contains(marker.count), remainder.first?.isWhitespace == true else { return nil }
        return (marker.count, String(remainder.drop(while: { $0.isWhitespace })))
    }

    private static func listItem(_ line: String) -> ListItem? {
        let marker: String
        if let first = line.first, "-*+".contains(first) { marker = String(first) }
        else {
            let digits = line.prefix(while: { $0.isASCII && $0.isNumber })
            guard !digits.isEmpty, line.dropFirst(digits.count).first == "." else { return nil }
            marker = String(digits) + "."
        }
        let remainder = line.dropFirst(marker.count)
        guard remainder.first?.isWhitespace == true else { return nil }
        return ListItem(marker: marker.count == 1 ? "•" : marker,
            text: String(remainder.drop(while: { $0.isWhitespace })))
    }

    private static func tableCells(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        line.contains("|") && tableCells(line).allSatisfy {
            $0.range(of: "^:?-{3,}:?$", options: .regularExpression) != nil
        }
    }

    /// Build styled text directly, so even links/images never acquire an action or attachment.
    private static func inline(_ text: String, size: CGFloat = 13, bold: Bool = false,
                               italic: Bool = false, depth: Int = 0) -> AttributedString {
        var result = AttributedString()
        func append(_ value: String, code: Bool = false) {
            var run = AttributedString(value)
            let font = Font.system(size: size, weight: bold ? .semibold : .regular,
                                   design: code ? .monospaced : .default)
            run.font = italic && !code ? font.italic() : font
            result.append(run)
        }
        // Unsupported HTML or deep nesting keeps every original character visible.
        if depth > 2 || (text.contains("<") && text.contains(">")) { append(text); return result }
        var cursor = text.startIndex
        while cursor < text.endIndex {
            let rest = text[cursor...]
            if rest.hasPrefix("!["), let end = rest.range(of: ")") {
                append(String(text[cursor..<end.upperBound])); cursor = end.upperBound; continue
            }
            if rest.hasPrefix("["), let middle = rest.range(of: "]("),
               let end = text[middle.upperBound...].firstIndex(of: ")"),
               !text[text.index(after: cursor)..<middle.lowerBound].contains(where: { $0 == "[" || $0 == "]" }) {
                let name = text[text.index(after: cursor)..<middle.lowerBound]
                let address = text[middle.upperBound..<end]
                append("\(name) (\(address))"); cursor = text.index(after: end); continue
            }
            if rest.first == "`" {
                let marker = String(rest.prefix(while: { $0 == "`" }))
                let start = text.index(cursor, offsetBy: marker.count)
                if let end = closingMarker(marker, in: text, after: start) {
                    append(String(text[start..<end.lowerBound]), code: true)
                    cursor = end.upperBound; continue
                }
            }
            if rest.first == "*" || rest.first == "_" {
                let marker = String(rest.prefix(while: { $0 == rest.first }))
                let start = text.index(cursor, offsetBy: marker.count)
                let insideWord = rest.first == "_" && cursor > text.startIndex
                    && text[text.index(before: cursor)].isLetter
                if marker.count <= 2, !insideWord, let end = closingMarker(marker, in: text, after: start), end.lowerBound > start {
                    result.append(inline(String(text[start..<end.lowerBound]), size: size,
                        bold: bold || marker.count == 2, italic: italic || marker.count == 1, depth: depth + 1))
                    cursor = end.upperBound; continue
                }
                append(marker); cursor = start; continue
            }
            if rest.first == "\\" {
                let next = text.index(after: cursor)
                if next < text.endIndex, "\\`*_[]()".contains(text[next]) {
                    append(String(text[next])); cursor = text.index(after: next); continue
                }
            }
            append(String(text[cursor])); cursor = text.index(after: cursor)
        }
        return result
    }

    private static func closingMarker(_ marker: String, in text: String, after start: String.Index) -> Range<String.Index>? {
        var cursor = start
        while let range = text[cursor...].range(of: marker) {
            let previous = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : nil
            let next = range.upperBound < text.endIndex ? text[range.upperBound] : nil
            if previous != marker.first, next != marker.first,
               marker.first == "`" || previous != "\\" { return range }
            cursor = range.upperBound
        }
        return nil
    }
}
