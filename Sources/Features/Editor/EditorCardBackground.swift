import AppKit
import SwiftUI

/// Each card owns its material and tint, leaving the space between cards transparent.
struct EditorCardBackground: View {
    let cornerRadius: CGFloat
    let colorScheme: ColorScheme
    let reduceTransparency: Bool
    let increasesContrast: Bool

    var usesMaterial: Bool {
        colorScheme == .dark && !reduceTransparency && !increasesContrast
    }

    var body: some View {
        ZStack {
            if usesMaterial { EditorCardMaterial(cornerRadius: cornerRadius) }
            Color(nsColor: EditorPalette.surface).opacity(usesMaterial ? 0.95 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct EditorCardMaterial: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> EditorCardMaterialView {
        let view = EditorCardMaterialView()
        view.configure(cornerRadius: cornerRadius)
        return view
    }

    func updateNSView(_ view: EditorCardMaterialView, context: Context) {
        view.configure(cornerRadius: cornerRadius)
    }
}

final class EditorCardMaterialView: NSVisualEffectView {
    func configure(cornerRadius: CGFloat) {
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        setAccessibilityElement(false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
