import AppKit
import SwiftUI

struct CodexRecentTasksView: View {
    let maximumHeight: CGFloat
    let composing: Bool
    let canOpen: () -> Bool
    let onOpened: () -> Void
    private let history = CodexTaskHistory.shared
    @State private var openFailed = false
    @State private var hoveredID: UUID?
    @FocusState private var focusedID: UUID?
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(L10n.text("action.codex.recent_tasks"))
                    .font(.system(size: 12, weight: .semibold))
                if !history.recentTasks.isEmpty {
                    Text(history.recentTasks.count, format: .number)
                        .font(.system(size: 10, weight: .medium)).monospacedDigit()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.primary.opacity(0.05), in: Capsule())
                        .accessibilityHidden(true)
                }
                Spacer()
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 11)).accessibilityHidden(true)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18).frame(height: 40)
            Rectangle().fill(.primary.opacity(0.06)).frame(height: 1).padding(.horizontal, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if history.recentTasks.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 22, weight: .light)).accessibilityHidden(true)
                            Text(L10n.text(history.isLoading ? "action.codex.history_loading"
                                : history.loadFailed ? "action.codex.history_failed" : "action.codex.history_empty"))
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.horizontal, 18).padding(.vertical, 18)
                    }
                    ForEach(history.recentTasks) { record in
                        taskRow(record)
                    }
                    if openFailed {
                        Label(L10n.text("action.codex.open_recent_failed"), systemImage: "exclamationmark.circle")
                            .foregroundStyle(.secondary).padding(10).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("codex-recent-open-error")
                    }
                }.padding(8)
            }
        }
        .font(.system(size: 12))
        .frame(height: min(maximumHeight, contentHeight))
        .task { await history.refreshConversationNames() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("codex-recent-tasks")
    }

    private var contentHeight: CGFloat {
        let count = history.recentTasks.count
        return 57 + (count == 0 ? 92 : CGFloat(count * 60 + (count - 1) * 2)) + (openFailed ? 54 : 0)
    }

    private func taskRow(_ record: CodexTaskRecord) -> some View {
        let title = record.displayTitle.isEmpty ? L10n.text("action.codex.untitled_task") : record.displayTitle
        let highlighted = hoveredID == record.id || focusedID == record.id
        return Button {
            guard !composing, canOpen() else { return }
            open(record)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(highlighted ? Color.accentColor : .secondary)
                    .frame(width: 32, height: 32)
                    .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary).lineLimit(1).truncationMode(.tail)
                    HStack(spacing: 6) {
                        Image(systemName: record.status.systemImage)
                            .font(.system(size: 10)).foregroundStyle(statusColor(record.status))
                            .accessibilityHidden(true)
                        Text(L10n.text(record.status.localizationKey)).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(record.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .foregroundStyle(.secondary).monospacedDigit()
                    }.font(.system(size: 11)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(highlighted ? Color.accentColor : Color.secondary.opacity(0.45))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10).frame(height: 60)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlighted ? Color.accentColor.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(focusedID == record.id ? Color.accentColor
                        : highlighted && contrast == .increased ? Color.primary.opacity(0.6) : .clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusedID, equals: record.id)
        .focusEffectDisabled()
        .disabled(composing)
        .onHover { hovering in
            if hovering { hoveredID = record.id }
            else if hoveredID == record.id { hoveredID = nil }
        }
        .help(title + "\n" + L10n.text("action.codex.open_recent"))
        .accessibilityElement(children: .combine)
        .accessibilityHint(L10n.text("action.codex.open_recent"))
        .accessibilityIdentifier("codex-recent-\(record.id.uuidString)")
    }

    private func statusColor(_ status: CodexTaskRecord.Status) -> Color {
        switch status {
        case .running: .accentColor
        case .completed: .secondary
        case .failed, .unknown: .orange
        }
    }

    private func open(_ record: CodexTaskRecord) {
        if let url = record.conversationURL, NSWorkspace.shared.open(url) {
            openFailed = false
            onOpened()
            return
        }
        let directory = history.taskDirectory(for: record)
        let result = directory.appendingPathComponent("result.md")
        if FileManager.default.fileExists(atPath: result.path), NSWorkspace.shared.open(result) {
            openFailed = false
            onOpened()
            return
        }
        openFailed = !NSWorkspace.shared.open(directory)
        if !openFailed { onOpened() }
    }
}
