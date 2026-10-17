import Foundation
import Observation

@MainActor @Observable
final class TemplateConfiguration {
    static let key = "inputTemplates.v1"
    static let didChangeNotification = Notification.Name("TemplateConfiguration.didChange")
    private struct Stored: Codable {
        let version: Int
        let templates: [InputTemplate]
        let builtInOverrides: [InputTemplate]?
    }
    private let defaults: UserDefaults
    private var builtInOverrides: [InputTemplate] = []
    private(set) var custom: [InputTemplate] = []
    private(set) var revision = 0
    private(set) var error: String?
    private(set) var isReadOnly = false
    var builtIns: [InputTemplate] {
        InputTemplate.builtIns.map { original in
            builtInOverrides.first(where: { $0.id == original.id }) ?? original
        }
    }
    var templates: [InputTemplate] { builtIns + custom }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let raw = defaults.object(forKey: Self.key) else { return }
        do {
            guard let data = raw as? Data else { throw Failure.invalidStorage }
            let stored = try JSONDecoder().decode(Stored.self, from: data)
            let overrides = stored.builtInOverrides ?? []
            let builtInIDs = Set(InputTemplate.builtIns.map(\.id))
            guard stored.version == 1, Set(stored.templates.map(\.id)).count == stored.templates.count,
                  stored.templates.allSatisfy({ UUID(uuidString: $0.id) != nil }),
                  Set(overrides.map(\.id)).count == overrides.count,
                  overrides.allSatisfy({ builtInIDs.contains($0.id) }) else { throw Failure.invalidStorage }
            let effectiveBuiltIns = InputTemplate.builtIns.map { original in
                overrides.first(where: { $0.id == original.id }) ?? original
            }
            var accepted: [InputTemplate] = []
            for item in effectiveBuiltIns + stored.templates {
                try Self.validate(item, among: accepted)
                guard item.name == item.name.trimmingCharacters(in: .whitespacesAndNewlines) else { throw Failure.invalidStorage }
                accepted.append(item)
            }
            builtInOverrides = overrides
            custom = stored.templates
        } catch { isReadOnly = true; self.error = L10n.text("templates.storage_read_failed") }
    }

    enum Failure: Error, LocalizedError {
        case invalidName, duplicateName, emptyBody, invalidStorage, writeFailed, fixed
        var errorDescription: String? {
            switch self {
            case .invalidName: L10n.text("templates.invalid_name")
            case .duplicateName: L10n.text("templates.duplicate_name")
            case .emptyBody: L10n.text("templates.empty_body")
            case .invalidStorage: L10n.text("templates.storage_read_failed")
            case .writeFailed: L10n.text("templates.storage_write_failed")
            case .fixed: L10n.text("templates.fixed")
            }
        }
    }

    private static func validate(_ item: InputTemplate, among items: [InputTemplate]) throws {
        guard !item.name.isEmpty, !item.name.contains(where: { $0.isNewline }) else { throw Failure.invalidName }
        guard !items.contains(where: { $0.id != item.id && $0.name.caseInsensitiveCompare(item.name) == .orderedSame }) else { throw Failure.duplicateName }
        let expansion = try TemplateExpansion.parse(item.body)
        guard !expansion.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.emptyBody }
    }

    func save(id: String?, name: String, body: String) throws {
        guard !isReadOnly else { throw Failure.invalidStorage }
        if let id { guard templates.contains(where: { $0.id == id }) else { throw Failure.fixed } }
        let item = InputTemplate(id: id ?? UUID().uuidString, name: name.trimmingCharacters(in: .whitespacesAndNewlines), body: body)
        try Self.validate(item, among: templates)
        if let original = InputTemplate.builtIns.first(where: { $0.id == item.id }) {
            var overrides = builtInOverrides.filter { $0.id != item.id }
            if item != original { overrides.append(item) }
            try persist(custom, builtInOverrides: overrides)
            return
        }
        var next = custom
        if let index = next.firstIndex(where: { $0.id == item.id }) { next[index] = item } else { next.append(item) }
        try persist(next, builtInOverrides: builtInOverrides)
    }

    func delete(_ id: String) throws {
        guard !isReadOnly else { throw Failure.invalidStorage }
        guard custom.contains(where: { $0.id == id }) else { throw Failure.fixed }
        try persist(custom.filter { $0.id != id }, builtInOverrides: builtInOverrides)
    }

    private func persist(_ next: [InputTemplate], builtInOverrides overrides: [InputTemplate]) throws {
        let data = try JSONEncoder().encode(Stored(version: 1, templates: next, builtInOverrides: overrides.isEmpty ? nil : overrides))
        let previous = defaults.object(forKey: Self.key)
        defaults.set(data, forKey: Self.key)
        guard defaults.data(forKey: Self.key) == data else {
            if let previous { defaults.set(previous, forKey: Self.key) } else { defaults.removeObject(forKey: Self.key) }
            error = L10n.text("templates.storage_write_failed"); throw Failure.writeFailed
        }
        builtInOverrides = overrides; custom = next; error = nil; revision &+= 1
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
