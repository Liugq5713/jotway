import Foundation

struct InputTemplate: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var body: String
    var isBuiltIn: Bool { id.hasPrefix("builtin.") }

    /// Display only: use the same expansion rules as insertion without changing its text or fields.
    var preview: String {
        guard let expanded = try? TemplateExpansion.parse(body).text else {
            return L10n.text("templates.no_preview")
        }
        let lines = expanded.components(separatedBy: .newlines).compactMap { source -> String? in
            var line = source.trimmingCharacters(in: .whitespaces)
            while let last = line.last, last == ":" || last == "：" {
                line.removeLast()
                line = line.trimmingCharacters(in: .whitespaces)
            }
            return line.isEmpty ? nil : line
        }
        return lines.isEmpty ? L10n.text("templates.no_preview") : lines.joined(separator: " · ")
    }

    static let builtIns = [
        InputTemplate(id: "builtin.idea", name: "记录想法", body: "想法：${1}\n\n为什么值得做：${2}\n\n下一步：${3}\n${0}"),
        InputTemplate(id: "builtin.problem", name: "梳理问题", body: "遇到的问题：${1}\n\n预期结果：${2}\n\n实际情况：${3}\n\n已经尝试：${4}\n${0}")
    ]
}
