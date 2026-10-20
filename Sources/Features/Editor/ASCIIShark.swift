import AppKit
import CoreText

/// Original top-down character mesh. Glyphs keep their identity as the body bends,
/// so swimming does not flicker between raster frames or mirror the typography.
@MainActor
struct ASCIIShark {
    static let size = CGSize(width: 96, height: 36)
    private static let scale: CGFloat = 0.66
    private static let length: CGFloat = 116
    private static let jointCount = 16
    private static let font = NSFont.monospacedSystemFont(ofSize: 5.2, weight: .medium) as CTFont
    private static let skin = makeSkin()

    private var position: CGPoint?
    private var bearings = Array(repeating: CGFloat.zero, count: jointCount)
    private var phase: CGFloat = 0
    private var effort: CGFloat = 0
    private var turn: CGFloat = 0
    private var hasHeading = false

    mutating func advance(to point: CGPoint, delta: TimeInterval) {
        guard let previous = position else { position = point; return }
        position = point
        guard delta > 0 else { return }
        let dt = CGFloat(delta)
        let dx = point.x - previous.x
        let dy = point.y - previous.y
        let speed = hypot(dx, dy) / dt
        effort += (min(speed / 65, 1.5) - effort) * (1 - exp(-dt * 3))
        phase += dt * (3.4 + effort * 2.3)

        let oldHeading = bearings[0]
        if speed > 0.5 {
            let direction = atan2(dy, dx)
            if !hasHeading {
                bearings = Array(repeating: direction, count: Self.jointCount)
                hasHeading = true
            }
            let difference = Self.angle(direction - bearings[0])
            // Even a sudden retreat has a round turn; never squash or flip the sprite.
            bearings[0] += max(-dt * 3.2, min(dt * 3.2, difference * (1 - exp(-dt * 9))))
        }
        let turning = max(-3.2, min(3.2, Self.angle(bearings[0] - oldHeading) / dt))
        turn += (turning - turn) * (1 - exp(-dt * 4))
        for index in 1..<bearings.count {
            let difference = Self.angle(bearings[index - 1] - bearings[index])
            let remaining = difference * exp(-dt * 16)
            bearings[index] = bearings[index - 1] - max(-0.17, min(0.17, remaining))
        }
    }

    func draw(color: NSColor, in context: CGContext) {
        guard let position else { return }
        let spine = centerline()
        let anchor = spine[7]
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: position.x, y: position.y)
        context.scaleBy(x: Self.scale, y: Self.scale)
        context.setFont(CTFontCopyGraphicsFont(Self.font, nil))
        context.setFontSize(CTFontGetSize(Self.font))
        context.setTextDrawingMode(.fill)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        // Batch the whole mesh in three shades instead of laying out a string per cell per frame.
        for shade in 0..<3 {
            var glyphs: [CGGlyph] = []
            var points: [CGPoint] = []
            for cell in Self.skin where cell.shade == shade {
                let joint = cell.along * CGFloat(Self.jointCount - 1)
                let index = min(Int(joint), spine.count - 2)
                let fraction = joint - CGFloat(index)
                let a = spine[index]
                let b = spine[index + 1]
                let bearing = bearings[index]
                // The inside pectoral fin folds slightly into a turn.
                let bank = cell.isFin ? 1 - max(-0.18, min(0.18, turn * cell.across / 100)) : 1
                let across = cell.across * bank
                points.append(CGPoint(
                    x: a.x + (b.x - a.x) * fraction - anchor.x
                        - sin(bearing) * across - 1.5,
                    y: -(a.y + (b.y - a.y) * fraction - anchor.y
                        + cos(bearing) * across + 1.8)))
                glyphs.append(cell.glyph)
            }
            context.setFillColor(color.withAlphaComponent(color.alphaComponent * [0.56, 0.78, 1][shade]).cgColor)
            context.showGlyphs(glyphs, at: points)
        }
    }

    private func centerline() -> [CGPoint] {
        var points = [CGPoint.zero]
        let segment = Self.length / CGFloat(Self.jointCount - 1)
        for index in 1..<Self.jointCount {
            let bearing = bearings[index]
            let previous = points[index - 1]
            points.append(CGPoint(x: previous.x - cos(bearing) * segment,
                                  y: previous.y - sin(bearing) * segment))
        }
        return points.enumerated().map { index, point in
            let along = CGFloat(index) / CGFloat(Self.jointCount - 1)
            // A travelling wave grows through the flexible rear body into the tail.
            let swing = sin(phase - along * 7.4) * along * along * (4.5 + effort * 3)
            return CGPoint(x: point.x - sin(bearings[index]) * swing,
                           y: point.y + cos(bearings[index]) * swing)
        }
    }

    private struct Cell {
        let along: CGFloat
        let across: CGFloat
        let glyph: CGGlyph
        let shade: Int
        let isFin: Bool
    }

    private static func makeSkin() -> [Cell] {
        // Snout, broad shoulders and a narrow tail stalk, drawn in body coordinates.
        let widths: [(CGFloat, CGFloat)] = [
            (0, 0.8), (0.09, 6.4), (0.22, 11), (0.36, 11.5),
            (0.52, 8.2), (0.7, 4.2), (0.88, 1.8), (1, 0.8),
        ]
        func halfWidth(_ along: CGFloat) -> CGFloat {
            guard along <= 1 else { return 0 }
            for index in 1..<widths.count where along <= widths[index].0 {
                let a = widths[index - 1]
                let b = widths[index]
                return a.1 + (b.1 - a.1) * (along - a.0) / (b.0 - a.0)
            }
            return 0
        }
        func insideTriangle(_ x: CGFloat, _ y: CGFloat, _ vertices: [(CGFloat, CGFloat)]) -> Bool {
            let signs = (0..<3).map { index -> CGFloat in
                let a = vertices[index]
                let b = vertices[(index + 1) % 3]
                return (x - a.0) * (b.1 - a.1) - (y - a.1) * (b.0 - a.0)
            }
            return !signs.contains(where: { $0 < 0 }) || !signs.contains(where: { $0 > 0 })
        }
        func isFin(_ along: CGFloat, _ across: CGFloat) -> Bool {
            let side = abs(across)
            return insideTriangle(along, side, [(0.27, 5), (0.51, 24), (0.44, 5)])
                || insideTriangle(along, side, [(0.64, 3), (0.77, 12), (0.75, 2)])
                || insideTriangle(along, side, [(0.95, 0), (1.15, across > 0 ? 21 : 17), (1.07, 0)])
        }
        let characters = Array(".:-=+*#%".utf16)
        var glyphs = Array(repeating: CGGlyph(), count: characters.count)
        CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count)
        var cells: [Cell] = []
        for column in 0...44 {
            let along = CGFloat(column) * 3 / length
            for row in -5...5 {
                let across = CGFloat(row) * 4.3
                let body = along <= 1 && abs(across) <= halfWidth(along)
                let fin = isFin(along, across)
                guard body || fin else { continue }
                let middle = body ? max(0, 1 - abs(across) / max(1, halfWidth(along))) : 0
                var density = body ? 3 + Int(middle * 4) : 3 + (column + abs(row)) % 3
                // Small gill cuts and a dark central ridge give the silhouette depth.
                if (8...11).contains(column), row != 0, column % 2 == 0 { density = 1 }
                if column == 4 && abs(row) == 1 { density = 7 }
                cells.append(Cell(along: along, across: across, glyph: glyphs[density],
                                  shade: body ? (middle > 0.45 ? 2 : 1) : (abs(across) > 17 ? 0 : 1),
                                  isFin: !body))
            }
        }
        return cells
    }

    private static func angle(_ value: CGFloat) -> CGFloat {
        atan2(sin(value), cos(value))
    }
}
