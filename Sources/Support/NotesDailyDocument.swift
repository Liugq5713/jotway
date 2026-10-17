import Foundation
import NaturalLanguage

/// A transient view of the note. Text is recovered from Notes, never from a local content copy.
struct NotesDailyDocument: Sendable {
    struct Entry: Sendable {
        let identity: NotesDailyGroupingStore.Entry
        let text: String
    }
    struct Rendered: Sendable {
        let content: AppleNotes.Content
        let boundary: NotesDailyBoundary
    }
    struct Generated: Sendable {
        let text: String
        let html: String?
    }
    let title: String
    let scope: NotesDailyScope
    let entries: [Entry]
    var generated: Generated? = nil
    var layout: NotesDailyGroupingStore.Layout = .grouped

    var original: String { entries.map(\.text).joined(separator: "\n\n") }

    var retrievalQuery: String {
        let heading = String(title.prefix(256))
        let latest = String((entries.last?.text ?? "").prefix(3_000))
        let prefix = heading + "\n" + latest + "\n"
        let earlier = entries.dropLast().map(\.text).joined(separator: "\n\n")
        return prefix + String(earlier.suffix(max(0, 4_000 - prefix.count)))
    }

    /// Rendering delegates supplement filtering and source-link construction to the existing path.
    /// Fingerprints cover display metadata separately, so neither timestamps nor titles are indexed.
    private func timeline() -> [NotesDailyBoundary.Part] {
        var parts: [NotesDailyBoundary.Part] = [.init(kind: .title, text: title),
            .init(kind: .metadata, text: "\n\n")]
        for (index, entry) in entries.enumerated() {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: entry.identity.timeZoneID) ?? .gmt
            formatter.dateFormat = "HH:mm"
            let separator = index == 0 ? "" : "\n\n"
            if layout == .grouped {
                parts.append(.init(kind: .metadata, text: separator + "- " + formatter.string(from: entry.identity.submittedAt) + "\n\n"))
            }
            parts.append(.init(kind: .original, entryID: entry.identity.id,
                               text: NotesDailyBoundary.normalizedLines(entry.text)))
        }
        return parts
    }

    func render(supplement: NotesSupplement = .empty) -> Rendered {
        var parts = timeline()
        let prefix = parts.map(\.text).joined()
        let rendered = AppleNotes.content(fromPlainText: prefix, supplement: supplement)
        let tail = String(rendered.plaintext.dropFirst(prefix.count))
        parts.append(.init(kind: rendered.itemCount + rendered.historyCount > 0 ? .generated : .metadata, text: tail))
        // Legacy extraction must reject this version without a complete local boundary.
        let content = AppleNotes.Content(html: rendered.html.replacingOccurrences(
            of: "data-jotway-region=\"original\"", with: "data-jotway-region=\"daily-originals\""),
            plaintext: rendered.plaintext, itemCount: rendered.itemCount, historyCount: rendered.historyCount)
        return .init(content: content, boundary: .init(parts: parts))
    }

    func renderRetainingGenerated(coveredAt: Date?) -> Rendered {
        guard let generated, let coveredAt else { return render() }
        var parts = timeline()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: scope.timeZoneID) ?? .gmt
        formatter.dateFormat = "HH:mm:ss ZZZZZ"
        let language = NLLanguageRecognizer.dominantLanguage(for: original)
        let chinese = language == .simplifiedChinese || language == .traditionalChinese
        let time = formatter.string(from: coveredAt)
        let status = chinese ? "\n\nAI 内容截至 \(time)，尚未包含最新想法。"
            : "\n\nAI content covers entries through \(time). Latest ideas not included."
        parts.append(.init(kind: .metadata, text: status))
        let prefix = parts.map(\.text).joined()
        let base = AppleNotes.content(fromPlainText: prefix)
        let generatedText = "\n\n" + generated.text.drop(while: { $0 == "\n" })
        let generatedHTML = generated.html ?? AppleNotes.content(fromPlainText: generatedText).html
            .replacingOccurrences(of: "data-jotway-region=\"original\"", with: "data-jotway-region=\"generated\"")
        parts.append(.init(kind: .generated, text: generatedText))
        let content = AppleNotes.Content(html: base.html.replacingOccurrences(
            of: "data-jotway-region=\"original\"", with: "data-jotway-region=\"daily-originals\"") + generatedHTML,
            plaintext: prefix + generatedText)
        return .init(content: content, boundary: .init(parts: parts))
    }

    /// Preserve every non-title region byte-for-byte, including stale-AI coverage metadata.
    static func replacingTitle(_ title: String, snapshot: NotesDailyGroupingStore.Snapshot,
                               body: NotesSourceBody) throws -> Rendered {
        guard NotesInitialTitleGenerator.valid(title), body.attachments == 0,
              var parts = snapshot.boundary.extract(from: NotesOriginalText.readableText(body)),
              parts.first?.kind == .title else { throw NotesHistoryError.ambiguous }
        parts[0] = .init(kind: .title, text: title)
        let plaintext = parts.map(\.text).joined()
        func escaped(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        // Keep the original/generated HTML byte-for-byte when our title span survives.
        // Re-rendering a pre block from its readback would add its terminating newline twice.
        var html = body.html
        if let marker = html.range(of: "<pre data-jotway-region=\"daily-originals\""),
           let span = html.range(of: "<span>", range: marker.lowerBound..<html.endIndex),
           let oldTitle = snapshot.boundary.extract(from: NotesOriginalText.readableText(body))?.first?.text,
           html[span.upperBound...].hasPrefix(escaped(oldTitle)) {
            let end = html.index(span.upperBound, offsetBy: escaped(oldTitle).count)
            html.replaceSubrange(span.upperBound..<end, with: escaped(title))
        } else {
            // Lost markup is recovered only from the already verified complete plaintext.
            // Link presentation cannot be recovered without trustworthy original markup.
            let text = plaintext.hasSuffix("\n") ? String(plaintext.dropLast()) : plaintext
            html = AppleNotes.content(fromPlainText: text).html.replacingOccurrences(
                of: "data-jotway-region=\"original\"", with: "data-jotway-region=\"daily-originals\"")
        }
        return .init(content: .init(html: html, plaintext: plaintext), boundary: .init(parts: parts))
    }

    static func recover(snapshot: NotesDailyGroupingStore.Snapshot, body: NotesSourceBody) throws -> Self {
        let text = NotesOriginalText.readableText(body)
        guard body.attachments == 0, let parts = snapshot.boundary.extract(from: text),
              let title = parts.first(where: { $0.kind == .title })?.text else { throw NotesHistoryError.ambiguous }
        let originals = parts.filter { $0.kind == .original }
        guard originals.map(\.entryID) == snapshot.entries.map({ Optional($0.id) }) else { throw NotesHistoryError.ambiguous }
        let tail = parts.first(where: { $0.kind == .generated })
        let html = body.html.range(of: "<div data-jotway-region=\"generated\"").map { String(body.html[$0.lowerBound...]) }
        return .init(title: title, scope: snapshot.scope,
                     entries: zip(snapshot.entries, originals).map { .init(identity: $0, text: $1.text) },
                     generated: tail.map { .init(text: $0.text, html: html) }, layout: snapshot.layout)
    }
}
