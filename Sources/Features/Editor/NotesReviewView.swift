import AppKit
import SwiftUI

/// Pull-only review surface for grounded findings, notable themes, and questions worth revisiting.
/// Read-only — the session opens and closes it; this view only renders.
struct NotesReviewView: View {
    let period: NotesReviewPeriod
    let summary: NotesReviewSummary?
    let preview: NotesReviewSummary?
    let requestMetadata: NotesReviewMetadata?
    let isLoading: Bool
    let failed: Bool
    let coverageIncomplete: Bool
    let unavailableReason: String?
    let maximumHeight: CGFloat
    let selectPeriod: (NotesReviewPeriod) -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(.primary.opacity(0.06)).frame(height: 1).padding(.horizontal, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let unavailableReason {
                        placeholder("moon.zzz", unavailableReason)
                    } else if failed {
                        placeholder("exclamationmark.triangle", L10n.text("notes.review.failed"))
                    } else if let displayedSummary, !displayedSummary.isEmpty {
                        content(displayedSummary)
                    } else if isLoading {
                        VStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                                .accessibilityLabel(L10n.text("notes.review.loading"))
                            Text(L10n.text("notes.review.loading"))
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                    } else {
                        placeholder("tray", L10n.text("notes.review.empty"))
                    }
                    if showsCoverageNotice {
                        Label(L10n.text("notes.review.coverage"), systemImage: "info.circle")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(size: 12))
        // Reserve one viewport for the whole request; arriving fragments only update its contents.
        .frame(height: min(maximumHeight, 300))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notes-review")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Picker(L10n.text("notes.review.title"), selection: Binding(
                get: { period }, set: { selectPeriod($0) }
            )) {
                ForEach(NotesReviewPeriod.allCases, id: \.self) { option in
                    Text(L10n.text(option.titleKey)).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .fixedSize()
            .accessibilityLabel(L10n.text("notes.review.title"))
            .accessibilityIdentifier("notes-review-period")
            if let dateRange {
                Text(dateRange).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if isLoading {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                        .accessibilityHidden(true)
                    Text(L10n.text("notes.review.generating"))
                        .font(.system(size: 10, weight: .medium))
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("notes-review-generating")
            }
            if let noteCount {
                Text(L10n.text("notes.review.note_count", noteCount))
                    .font(.system(size: 10, weight: .medium)).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.primary.opacity(0.05), in: Capsule())
            }
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 11))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(L10n.text("common.close"))
            .accessibilityLabel(L10n.text("common.close"))
            .accessibilityIdentifier("notes-review-close")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18).frame(height: 40)
    }

    @ViewBuilder private func content(_ summary: NotesReviewSummary) -> some View {
        if !summary.overview.isEmpty {
            Text(verbatim: summary.overview)
                .font(.system(size: 13)).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        if !summary.themes.isEmpty {
            section(L10n.text("notes.review.themes")) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(summary.themes) { theme in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "circle.fill").font(.system(size: 4))
                                .foregroundStyle(.secondary).accessibilityHidden(true)
                            Text(verbatim: theme.title).font(.system(size: 13)).foregroundStyle(.primary)
                            if let count = theme.count {
                                Text(L10n.text("notes.review.theme_count", count))
                                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        if !summary.unresolved.isEmpty {
            section(L10n.text("notes.review.unresolved")) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(summary.unresolved, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "circle").font(.system(size: 5))
                                .foregroundStyle(.orange).accessibilityHidden(true)
                            Text(verbatim: line).font(.system(size: 12)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func placeholder(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).accessibilityHidden(true)
            Text(text).multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity).padding(.vertical, 16)
    }

    private var displayedSummary: NotesReviewSummary? { isLoading ? preview : summary }

    private var noteCount: Int? { requestMetadata?.noteCount ?? displayedSummary?.noteCount }

    private var showsCoverageNotice: Bool {
        unavailableReason == nil && !failed && (requestMetadata?.coverageIncomplete ?? coverageIncomplete)
    }

    private var dateRange: String? {
        guard let windowStart = requestMetadata?.windowStart ?? displayedSummary?.windowStart,
              let windowEnd = requestMetadata?.windowEnd ?? displayedSummary?.windowEnd else { return nil }
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        if period == .today { return windowStart.formatted(style) }
        return windowStart.formatted(style) + " – " + windowEnd.formatted(style)
    }
}
