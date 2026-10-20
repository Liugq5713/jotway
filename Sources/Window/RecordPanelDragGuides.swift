import AppKit

/// Output-only guides. One reusable window belongs to the record panel's drag lifecycle.
@MainActor
final class RecordPanelDragGuides {
    private var panel: GuidePanel?
    private var drawing: GuideView?

    func update(_ alignment: RecordPanelPlacement.DragAlignment, around frame: CGRect, for owner: NSWindow) {
        let panel: GuidePanel
        let drawing: GuideView
        if let existing = self.panel, let view = self.drawing {
            panel = existing
            drawing = view
        } else {
            panel = GuidePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            panel.isExcludedFromWindowsMenu = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.animationBehavior = .none
            panel.setAccessibilityElement(false)
            panel.setAccessibilityChildren([])
            drawing = GuideView(frame: .zero)
            drawing.setAccessibilityElement(false)
            drawing.setAccessibilityChildren([])
            panel.contentView = drawing
            self.panel = panel
            self.drawing = drawing
        }
        let usable = alignment.screen.visibleFrame
        panel.level = owner.level
        panel.appearance = owner.effectiveAppearance
        if panel.frame != usable { panel.setFrame(usable, display: false) }
        drawing.update(.init(
            centerX: alignment.defaultFrame.midX - usable.minX,
            topY: alignment.defaultFrame.maxY - usable.minY,
            excludedFrame: frame.offsetBy(dx: -usable.minX, dy: -usable.minY).insetBy(dx: -6, dy: -6),
            alignsCenter: alignment.alignsCenter, alignsTop: alignment.alignsTop,
            increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast))
        if !panel.isVisible { panel.order(.above, relativeTo: owner.windowNumber) }
    }

    func hide() { panel?.orderOut(nil) }

    isolated deinit { panel?.close() }

    private final class GuidePanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class GuideView: NSView {
        struct Geometry: Equatable {
            let centerX: CGFloat
            let topY: CGFloat
            let excludedFrame: CGRect
            let alignsCenter: Bool
            let alignsTop: Bool
            let increasedContrast: Bool
        }
        private var geometry: Geometry?
        override var acceptsFirstResponder: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            needsDisplay = true
        }

        func update(_ geometry: Geometry) {
            guard geometry != self.geometry else { return }
            self.geometry = geometry
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            guard let geometry, let context = NSGraphicsContext.current?.cgContext else { return }
            context.saveGState()
            defer { context.restoreGState() }
            // Mask the entire panel, including the transparent gap between its cards.
            context.addRect(bounds)
            let excluded = geometry.excludedFrame.intersection(bounds)
            if !excluded.isNull { context.addRect(excluded) }
            context.clip(using: .evenOdd)
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let ink = dark ? NSColor.white : NSColor.black
            let halo = dark ? NSColor.black : NSColor.white
            func line(from start: CGPoint, to end: CGPoint, active: Bool) {
                context.setLineDash(phase: 0, lengths: active ? [] : [5, 5])
                context.setLineCap(.round)
                context.move(to: start)
                context.addLine(to: end)
                context.setLineWidth(geometry.increasedContrast ? 4 : 3)
                context.setStrokeColor(halo.withAlphaComponent(geometry.increasedContrast ? 0.85 : 0.55).cgColor)
                context.strokePath()
                context.move(to: start)
                context.addLine(to: end)
                context.setLineWidth(geometry.increasedContrast ? 2 : 1)
                context.setStrokeColor(ink.withAlphaComponent(active ? 0.9 : (geometry.increasedContrast ? 0.8 : 0.5)).cgColor)
                context.strokePath()
            }
            line(from: CGPoint(x: geometry.centerX, y: bounds.minY),
                 to: CGPoint(x: geometry.centerX, y: bounds.maxY), active: geometry.alignsCenter)
            line(from: CGPoint(x: bounds.minX, y: geometry.topY),
                 to: CGPoint(x: bounds.maxX, y: geometry.topY), active: geometry.alignsTop)
        }
    }
}
