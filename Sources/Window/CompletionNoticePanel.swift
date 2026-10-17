import AppKit
import SwiftUI

/// A short-lived result notice. Showing or dismissing it never activates an app or takes editor focus.
@MainActor
final class CompletionNoticePanel: NSPanel {
    private var dismissalTask: Task<Void, Never>?
    private var isHovered = false
    private var noticeID = UUID()

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
    }

    func show(message: String, onOpen: (@MainActor () -> Void)? = nil, openHint: String? = nil, isError: Bool = false) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let width = min(320, max(0, visible.width - 32))
        let height = min(68, max(0, visible.height - 32))
        guard width > 0, height > 0 else { return }
        let frame = NSRect(x: visible.maxX - width - 16, y: visible.maxY - height - 16, width: width, height: height)
        let id = UUID()
        noticeID = id
        var open: (@MainActor () -> Void)?
        if let onOpen {
            open = { [weak self] in
                guard let self, self.isVisible, self.noticeID == id else { return }
                self.dismiss()
                onOpen()
            }
        }
        contentView = CompletionNoticeHostingView(rootView: CompletionNoticeContent(message: message,
            isError: isError, open: open, openHint: openHint ?? L10n.text("completion.open_app"),
            dismiss: { [weak self] in self?.dismiss() },
            hoverChanged: { [weak self] hovering in self?.setHovered(hovering) }))
        setFrame(frame, display: true)
        isHovered = frame.contains(NSEvent.mouseLocation)
        animateIn(to: frame)
        scheduleDismissal()
    }

    /// 右上角滑入 + 淡入，与面板入场同族缓动；Reduce Motion 时只做短促淡入。
    private func animateIn(to frame: NSRect) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        alphaValue = 0
        if !reduceMotion { setFrameOrigin(NSPoint(x: frame.origin.x + 16, y: frame.origin.y)) }
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = reduceMotion ? 0.10 : 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            animator().alphaValue = 1
            if !reduceMotion { animator().setFrameOrigin(frame.origin) }
        }
    }

    func dismiss() {
        dismissalTask?.cancel()
        dismissalTask = nil
        isHovered = false
        guard isVisible else { orderOut(nil); return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let id = noticeID
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = reduceMotion ? 0.10 : 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
            if !reduceMotion { animator().setFrameOrigin(NSPoint(x: frame.origin.x + 8, y: frame.origin.y)) }
        } completionHandler: { [weak self] in
            // 淡出期间若来了新提示（noticeID 变化），不要越俎把新窗口关掉。
            MainActor.assumeIsolated {
                guard let self, self.noticeID == id else { return }
                self.orderOut(nil)
                self.alphaValue = 1
            }
        }
    }

    private func setHovered(_ hovering: Bool) {
        isHovered = hovering
        scheduleDismissal()
    }

    private func scheduleDismissal() {
        dismissalTask?.cancel()
        dismissalTask = nil
        guard isVisible, !isHovered else { return }
        dismissalTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    isolated deinit { dismissalTask?.cancel() }
}

private final class CompletionNoticeHostingView: NSHostingView<CompletionNoticeContent> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct CompletionNoticeContent: View {
    let message: String
    let isError: Bool
    let open: (@MainActor () -> Void)?
    let openHint: String
    let dismiss: () -> Void
    let hoverChanged: (Bool) -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 0) {
            if let open {
                Button(action: open) { messageLabel }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .accessibilityLabel(message)
                    .accessibilityHint(openHint)
                    .help(openHint)
            } else {
                messageLabel
            }
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel(L10n.text("common.close"))
            .help(L10n.text("common.close"))
            .padding(.trailing, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.primary.opacity(contrast == .increased ? 0.7 : 0.12), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .onHover(perform: hoverChanged)
        .accessibilityElement(children: .contain)
    }

    private var messageLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(isError ? Color.orange : Color.green)
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}
