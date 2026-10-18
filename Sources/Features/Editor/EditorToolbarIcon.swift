import AppKit

/// Toolbar glyphs share a 22 pt canvas, 1.25 pt rounded strokes and a centered 14 pt footprint.
enum EditorToolbarIcon: CaseIterable {
    case stickyNote, quickInput, recentDocument, weeklyReview, monthlyReview, thinkingPrompt

    @MainActor
    func draw(in bounds: NSRect, color: NSColor, opacity: CGFloat = 1) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = AffineTransform(translationByX: bounds.midX - 11, byY: bounds.midY + 11)
        let path = NSBezierPath()
        path.lineWidth = 1.25
        path.lineJoinStyle = .round
        path.lineCapStyle = .round

        func line(_ points: NSPoint...) {
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.line(to: point) }
        }

        switch self {
        case .stickyNote:
            path.move(to: NSPoint(x: 6.5, y: 17.5))
            path.line(to: NSPoint(x: 15.5, y: 17.5))
            path.curve(to: NSPoint(x: 17, y: 16), controlPoint1: NSPoint(x: 16.4, y: 17.5), controlPoint2: NSPoint(x: 17, y: 16.9))
            line(NSPoint(x: 17, y: 16), NSPoint(x: 17, y: 9), NSPoint(x: 12.5, y: 4.5), NSPoint(x: 6.5, y: 4.5))
            path.curve(to: NSPoint(x: 5, y: 6), controlPoint1: NSPoint(x: 5.6, y: 4.5), controlPoint2: NSPoint(x: 5, y: 5.1))
            path.line(to: NSPoint(x: 5, y: 16))
            path.curve(to: NSPoint(x: 6.5, y: 17.5), controlPoint1: NSPoint(x: 5, y: 16.9), controlPoint2: NSPoint(x: 5.6, y: 17.5))
            line(NSPoint(x: 12.5, y: 4.5), NSPoint(x: 12.5, y: 9), NSPoint(x: 17, y: 9))
            line(NSPoint(x: 8, y: 13.5), NSPoint(x: 14, y: 13.5))
            line(NSPoint(x: 8, y: 10.5), NSPoint(x: 10, y: 10.5))
        case .quickInput:
            path.appendRoundedRect(NSRect(x: 4.5, y: 5.5, width: 13, height: 11), xRadius: 2, yRadius: 2)
            line(NSPoint(x: 8, y: 8.5), NSPoint(x: 8, y: 13.5))
            line(NSPoint(x: 10.5, y: 11), NSPoint(x: 14, y: 11))
        case .recentDocument:
            path.move(to: NSPoint(x: 15.5, y: 4.5))
            path.line(to: NSPoint(x: 6.5, y: 4.5))
            path.curve(to: NSPoint(x: 5, y: 6), controlPoint1: NSPoint(x: 5.6, y: 4.5), controlPoint2: NSPoint(x: 5, y: 5.1))
            path.line(to: NSPoint(x: 5, y: 16))
            path.curve(to: NSPoint(x: 6.5, y: 17.5), controlPoint1: NSPoint(x: 5, y: 16.9), controlPoint2: NSPoint(x: 5.6, y: 17.5))
            path.line(to: NSPoint(x: 12.5, y: 17.5))
            path.line(to: NSPoint(x: 17, y: 13))
            path.line(to: NSPoint(x: 17, y: 6))
            path.curve(to: NSPoint(x: 15.5, y: 4.5), controlPoint1: NSPoint(x: 17, y: 5.1), controlPoint2: NSPoint(x: 16.4, y: 4.5))
            line(NSPoint(x: 12.5, y: 17.5), NSPoint(x: 12.5, y: 13), NSPoint(x: 17, y: 13))
            line(NSPoint(x: 8, y: 10), NSPoint(x: 14, y: 10))
            line(NSPoint(x: 8, y: 7.5), NSPoint(x: 12, y: 7.5))
        case .weeklyReview, .monthlyReview:
            path.appendRoundedRect(NSRect(x: 4.5, y: 4.5, width: 13, height: 12), xRadius: 2, yRadius: 2)
            line(NSPoint(x: 8, y: 15), NSPoint(x: 8, y: 17.5))
            line(NSPoint(x: 14, y: 15), NSPoint(x: 14, y: 17.5))
            line(NSPoint(x: 4.5, y: 13), NSPoint(x: 17.5, y: 13))
            if self == .weeklyReview {
                // One continuous week; the month uses multiple rows of dates.
                line(NSPoint(x: 7.5, y: 8.5), NSPoint(x: 14.5, y: 8.5))
                line(NSPoint(x: 7.5, y: 7.5), NSPoint(x: 7.5, y: 9.5))
                line(NSPoint(x: 14.5, y: 7.5), NSPoint(x: 14.5, y: 9.5))
            } else {
                for y: CGFloat in [7, 10] {
                    for x: CGFloat in [7.5, 11, 14.5] {
                        line(NSPoint(x: x - 0.25, y: y), NSPoint(x: x + 0.25, y: y))
                    }
                }
            }
        case .thinkingPrompt:
            path.move(to: NSPoint(x: 8.5, y: 7.5))
            path.curve(to: NSPoint(x: 6, y: 12.5), controlPoint1: NSPoint(x: 8.5, y: 9.5), controlPoint2: NSPoint(x: 6, y: 9.5))
            path.curve(to: NSPoint(x: 11, y: 17.5), controlPoint1: NSPoint(x: 6, y: 15.3), controlPoint2: NSPoint(x: 8.2, y: 17.5))
            path.curve(to: NSPoint(x: 16, y: 12.5), controlPoint1: NSPoint(x: 13.8, y: 17.5), controlPoint2: NSPoint(x: 16, y: 15.3))
            path.curve(to: NSPoint(x: 13.5, y: 7.5), controlPoint1: NSPoint(x: 16, y: 9.5), controlPoint2: NSPoint(x: 13.5, y: 9.5))
            path.close()
            line(NSPoint(x: 9, y: 4.5), NSPoint(x: 13, y: 4.5))
            line(NSPoint(x: 11, y: 7.5), NSPoint(x: 11, y: 11.5))
        }
        // NSButton draws in flipped coordinates; the glyph definitions use a bottom-left origin.
        path.transform(using: AffineTransform(scaleByX: 1, byY: -1))
        path.transform(using: transform)
        color.withAlphaComponent(opacity).setStroke()
        path.stroke()
    }
}
