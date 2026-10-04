import AppKit
import SwiftUI

/// A dedicated result row keeps exact schedule values above the fixed action row.
struct ActionPlanResultRow: View {
    let state: LauncherViewState
    let send: (LauncherEvent) -> Void

    var body: some View {
        Group {
            if let summary = state.planSummary, let context = state.planContext,
               let planID = state.currentPlanID {
                let value = ActionPlanSummaryFormatter(summary: summary, context: context)
                let panelSessionID = state.panelSessionID
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        Text(value.targetName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(minWidth: 40, maxWidth: .infinity, alignment: .leading)
                        Text("·").foregroundStyle(.secondary)
                        Text(value.timeText).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(value.targetName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(value.timeText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .monospacedDigit()
                .help(value.detail)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(value.detail)
                .accessibilityIdentifier("launcher-time-result")
                .background {
                    PlanPresentation {
                        send(.planPresented(planID: planID, panelSessionID: panelSessionID))
                    }
                    .id(PresentationIdentity(planID: planID, sessionID: panelSessionID))
                }
            } else if let issue = state.timeIssue {
                let message = L10n.text(issue.localizationKey)
                    + " " + L10n.text("schedule.example", issue.example)
                issueText(message)
            } else if let failure = state.preparationFailure {
                issueText(failure)
            } else if state.isCheckingActionPlan {
                Text(L10n.text("schedule.checking"))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("launcher-time-checking")
            }
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: LauncherMetrics.planResultMaxHeight, alignment: .topLeading)
    }

    private func issueText(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .help(message)
            .accessibilityLabel(message)
            .accessibilityIdentifier("launcher-time-issue")
    }

    private struct PresentationIdentity: Hashable {
        let planID: UUID
        let sessionID: UUID
    }
}

/// Reports only after the result's native backing view was drawn in a visible window.
/// A new plan/session gets a fresh view, so an old queued callback keeps its old identity.
private struct PlanPresentation: NSViewRepresentable {
    let onPresented: () -> Void

    func makeNSView(context: Context) -> PresentationView { PresentationView() }
    func updateNSView(_ view: PresentationView, context: Context) {
        view.onPresented = onPresented
        view.needsDisplay = true
    }

    final class PresentationView: NSView {
        var onPresented: (() -> Void)?
        private var hasDrawn = false
        private var didReport = false
        private var notification: NSObjectProtocol?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let notification { NotificationCenter.default.removeObserver(notification) }
            notification = nil
            guard let window else { return }
            notification = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.needsDisplay = true
                }
            }
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            hasDrawn = true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.hasDrawn, !self.didReport, let window = self.window,
                      window.isVisible, window.occlusionState.contains(.visible), window.alphaValue > 0,
                      !self.isHiddenOrHasHiddenAncestor, !self.visibleRect.isEmpty else { return }
                self.didReport = true
                self.onPresented?()
            }
        }

        isolated deinit {
            if let notification { NotificationCenter.default.removeObserver(notification) }
        }
    }
}
