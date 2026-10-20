import Foundation

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
        /// The verified trailing metadata and generated regions, in their original order.
        let parts: [NotesDailyBoundary.Part]
        let html: String?
        var text: String { parts.map(\.text).joined() }
    }
    let title: String
    let scope: NotesDailyScope
    let entries: [Entry]
    var generated: Generated? = nil
    var layout: NotesDailyGroupingStore.Layout = .grouped

    var original: String { entries.map(\.text).joined(separator: "\n\n") }

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

    func render() -> Rendered {
        var parts = timeline()
        let original = parts.map(\.text).joined()
        let base = AppleNotes.content(fromPlainText: original)
        guard let generated else {
            parts.append(.init(kind: .metadata, text: "\n"))
            let content = AppleNotes.Content(html: base.html.replacingOccurrences(
                of: "data-jotway-region=\"original\"", with: "data-jotway-region=\"daily-originals\""),
                plaintext: original + "\n")
            return .init(content: content, boundary: .init(parts: parts))
        }
        // Existing coverage text belongs to the old tail. Never manufacture a new notice.
        parts.append(contentsOf: generated.parts)
        let plaintext = parts.map(\.text).joined()
        let html: String
        if let retained = generated.html,
           let firstGenerated = generated.parts.firstIndex(where: { $0.kind == .generated }) {
            let metadata = generated.parts[..<firstGenerated].map(\.text).joined()
            html = AppleNotes.content(fromPlainText: original + metadata).html.replacingOccurrences(
                of: "data-jotway-region=\"original\"", with: "data-jotway-region=\"daily-originals\"") + retained
        } else {
            // All text was boundary-verified. Missing markup cannot authorize link reconstruction.
            let text = plaintext.hasSuffix("\n") ? String(plaintext.dropLast()) : plaintext
            html = AppleNotes.content(fromPlainText: text).html.replacingOccurrences(
                of: "data-jotway-region=\"original\"", with: "data-jotway-region=\"daily-originals\"")
        }
        return .init(content: .init(html: html, plaintext: plaintext), boundary: .init(parts: parts))
    }

    /// Preserve every non-title region byte-for-byte, including stale-AI coverage metadata.
    static func replacingTitle(_ title: String, snapshot: NotesDailyGroupingStore.Snapshot,
                               body: NotesSourceBody) throws -> Rendered {
        guard NotesInitialTitleGenerator.valid(title), body.attachments == 0,
              var parts = snapshot.boundary.extract(from: NotesOriginalText.readableText(body)),
              parts.first?.kind == .title else { throw NotesReadError.ambiguous }
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
              let title = parts.first(where: { $0.kind == .title })?.text else { throw NotesReadError.ambiguous }
        let originals = parts.filter { $0.kind == .original }
        guard originals.map(\.entryID) == snapshot.entries.map({ Optional($0.id) }) else { throw NotesReadError.ambiguous }
        let tail: Generated?
        if let lastOriginal = parts.lastIndex(where: { $0.kind == .original }),
           parts[(lastOriginal + 1)...].contains(where: {
               $0.kind == .generated || !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
           }) {
            let trailing = Array(parts[(lastOriginal + 1)...])
            guard trailing.allSatisfy({ $0.kind == .metadata || $0.kind == .generated }) else {
                throw NotesReadError.ambiguous
            }
            let marker = "<div data-jotway-region=\"generated\""
            var verifiedHTML: String?
            if body.html.components(separatedBy: marker).count == 2,
               let range = body.html.range(of: marker),
               let firstGenerated = trailing.firstIndex(where: { $0.kind == .generated }) {
                let html = String(body.html[range.lowerBound...])
                let expected = trailing[firstGenerated...].map(\.text).joined()
                // Structural div/pre terminators may add boundary newlines. All interior text,
                // including spaces and legacy source labels, must match the verified region.
                // The legacy writer's empty div contains <br>; count that one blank row once,
                // rather than both the br and the closing div in the generic HTML reader.
                let rows = html.replacingOccurrences(of: #"(?i)<div>\s*<br\s*/?>\s*</div>"#,
                    with: "<div></div>", options: .regularExpression)
                let rendered = NotesOriginalText.readableText(.init(text: "", html: rows, attachments: 0))
                if rendered.trimmingCharacters(in: .newlines) == expected.trimmingCharacters(in: .newlines) {
                    verifiedHTML = html
                }
            }
            tail = .init(parts: trailing, html: verifiedHTML)
        } else { tail = nil }
        return .init(title: title, scope: snapshot.scope,
                     entries: zip(snapshot.entries, originals).map { .init(identity: $0, text: $1.text) },
                     generated: tail, layout: snapshot.layout)
    }
}
