import SwiftUI

struct ClipboardHistoryView: View {
    let history: ClipboardHistory
    let height: CGFloat
    let composing: Bool
    let select: (String) -> Void

    private func title(_ entry: ClipboardEntry) -> String {
        entry.isImage ? L10n.text("clipboard.image", String(entry.width), String(entry.height)) : String(entry.text.prefix(256))
    }
    private func status(_ entry: ClipboardEntry) -> String {
        entry.ocrState == "ready" ? String(entry.recognizedText.prefix(160)) : L10n.text("clipboard.ocr_" + entry.ocrState)
    }
    private func accessibilityLabel(_ entry: ClipboardEntry) -> String {
        entry.isImage ? title(entry) + ", " + status(entry) : L10n.text("clipboard.text") + ", " + title(entry)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(L10n.text("clipboard.title"), systemImage: "clipboard").font(.headline)
                Spacer()
                Text(L10n.text(history.enabled ? "clipboard.collecting" : "clipboard.paused"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = history.errorKey {
                Text(L10n.text(error)).font(.caption).foregroundStyle(.red)
            }
            if history.entries.isEmpty {
                Text(L10n.text(history.loading ? "clipboard.loading" : "clipboard.empty"))
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(history.entries) { entry in
                                Button {
                                    guard !composing else { return }
                                    select(entry.id)
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        if let data = entry.thumbnail, let image = NSImage(data: data) {
                                            Image(nsImage: image).resizable().scaledToFit().frame(width: 48, height: 48)
                                                .accessibilityHidden(true)
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(title(entry))
                                                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                            if entry.isImage {
                                                Text(status(entry))
                                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                            }
                                        }
                                    }
                                    .padding(8)
                                    .background(history.selectedID == entry.id ? Color.accentColor.opacity(0.15) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).focusable(false)
                                .accessibilityLabel(accessibilityLabel(entry))
                                .accessibilityAddTraits(history.selectedID == entry.id ? .isSelected : [])
                                .accessibilityHint(L10n.text("clipboard.select_hint"))
                                .id(entry.id)
                            }
                        }
                    }
                    .onChange(of: history.selectedID) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
            }
        }
        .padding(12).frame(height: height).clipped()
        .accessibilityIdentifier("clipboard-history")
    }
}
