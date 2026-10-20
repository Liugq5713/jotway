import AppKit
import SwiftUI

/// Preparation feedback shares the fixed action row with the target selector.
struct ActionPlanResultRow: View {
    let state: LauncherViewState
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack(alignment: .leading) {
            Color.clear.accessibilityHidden(true)
            if let failure = state.preparationFailure {
                issueText(failure)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(contrast == .increased ? Color.secondary : Color(nsColor: EditorPalette.secondary))
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: LauncherMetrics.actionRowHeight)
        .allowsHitTesting(state.preparationFailure != nil)
        .accessibilityHidden(state.preparationFailure == nil)
    }

    private func issueText(_ message: String) -> some View {
        Text(message)
            .editorDecorationExclusion()
            .foregroundStyle(contrast == .increased ? Color.secondary : Color(nsColor: EditorPalette.secondary))
            .help(message)
            .accessibilityLabel(message)
            .accessibilityIdentifier("launcher-preparation-issue")
    }

}
