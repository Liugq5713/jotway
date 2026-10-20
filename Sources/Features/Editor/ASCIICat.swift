import AppKit
import CoreText

/// The prototype and the app use these same literal, monospaced ASCII rows.
/// Each character keeps its shape; only the paws, tail and gaze move locally.
@MainActor
enum ASCIICat {
    static let gestureDuration: TimeInterval = 2.8
    static let restingRows = [
        #" /\_/\"#,
        #"(=^.^=)__"#,
        #"(")_(")___)~"#,
    ]
    private static let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium) as CTFont
    private static let lineHeight: CGFloat = 10
    private static let glyphMap: [CGGlyph] = {
        let characters = (0..<128).map { UniChar($0) }
        var glyphs = Array(repeating: CGGlyph(), count: characters.count)
        CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count)
        return glyphs
    }()
    private static let cellWidth: CGFloat = {
        var glyph = glyphMap[77]
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        return advance.width
    }()
    enum Expression: String {
        case curious = "( o.o )"
        case happy = "(=^.^=)"
        case surprised = "( O.O )"
        case blink = "( -.- )"
    }
    private enum Part { case face, eyes, body, tail, leftPaw, rightPaw }
    enum Layer { case head, body, paws }
    private struct Cell {
        let character: UInt8
        let column: Int
        let row: Int
        let part: Part
    }
    private static let cells: [Cell] = restingRows.enumerated().flatMap { row, text in
        text.utf8.enumerated().compactMap { column, character in
            guard character != 32 || (row == 1 && column < 7) else { return nil }
            let part: Part
            if row == 2, column == 11 { part = .tail }
            else if row == 2, (0...2).contains(column) { part = .leftPaw }
            else if row == 2, (3...6).contains(column) { part = .rightPaw }
            else if row == 1, column == 2 || column == 4 { part = .eyes }
            else if column >= 7 || row == 2 { part = .body }
            else { part = .face }
            return Cell(character: character, column: column, row: row, part: part)
        }
    }

    static func bounds(anchor: CGPoint, layer: Layer) -> CGRect {
        // Include local head dipping, paw reach and tail sweep in protection.
        switch layer {
        case .head:
            return CGRect(x: anchor.x - 23, y: anchor.y - 31, width: 46, height: 26)
        case .body:
            return CGRect(x: anchor.x - 5, y: anchor.y - 20, width: 59, height: 24)
        case .paws:
            return CGRect(x: anchor.x - 35, y: anchor.y - 12, width: 58, height: 16)
        }
    }

    static func ballBounds(anchor: CGPoint) -> CGRect {
        CGRect(x: anchor.x - 67, y: anchor.y - 12, width: 36, height: 22)
    }

    static func draw(in context: CGContext, anchor: CGPoint, layer: Layer, peek: CGFloat,
                     gestureProgress: CGFloat, gaze: CGPoint? = nil,
                     isHopping: Bool, isDark: Bool, restingFold: CGFloat = 0,
                     opacity: CGFloat = 1, expressionOverride: Expression? = nil) {
        guard opacity > 0.01 else { return }
        let progress = min(1, max(0, gestureProgress))
        let expression: Expression
        if let expressionOverride { expression = expressionOverride }
        else if isHopping { expression = .surprised }
        else if restingFold > 0.3 { expression = .blink }
        else if progress >= 0.7 && progress < 0.82 { expression = .blink }
        else if gaze != nil && progress == 0 { expression = .curious }
        else { expression = .happy }
        let face = Array(expression.rawValue.utf8)
        let envelope = pow(sin(progress * .pi), 2)
        let tailSwing = sin(progress * .pi * 2) * envelope * 3
        let reach = progress < 0.32 ? sin(progress / 0.32 * .pi) * (1 - peek) : 0
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: anchor.x, y: anchor.y)
        prepare(context)
        let parts: [Part]
        switch layer {
        case .head: parts = [.face, .eyes]
        case .body: parts = [.body, .tail]
        case .paws: parts = [.leftPaw, .rightPaw]
        }
        context.setFillColor(tint(isDark: isDark, opacity: opacity).cgColor)
        for part in parts {
            let selected = cells.filter { $0.part == part }
            let glyphs = selected.map { cell in
                glyphMap[Int(cell.row == 1 && cell.column < 7 ? face[cell.column] : cell.character)]
            }
            let positions = selected.map { cell in
                var x = (CGFloat(cell.column) - 3.5) * cellWidth
                var y = (CGFloat(cell.row) - 2) * lineHeight + 1 - envelope * peek * 1.5
                if cell.row < 2, cell.column < 7 { y += restingFold * 2 }
                if part == .tail { y += tailSwing + sin(restingFold * .pi) * 1.8 }
                if part == .leftPaw { x -= reach * 12; y -= reach * 2 }
                if part == .eyes, expression == .curious, let gaze {
                    x += gaze.x * 0.7; y += gaze.y * 0.5
                }
                return CGPoint(x: x, y: -y)
            }
            context.showGlyphs(glyphs, at: positions)
        }
    }

    static func drawBall(in context: CGContext, anchor: CGPoint, gestureProgress: CGFloat,
                         opacity: CGFloat, isDark: Bool) {
        guard opacity > 0.01 else { return }
        let progress = max(0, min(1, (gestureProgress - 0.12) / 0.88))
        let roll = pow(sin(progress * .pi), 2)
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: anchor.x - 39 - 18 * roll,
                            y: anchor.y - 3 - abs(sin(progress * .pi * 2)))
        context.rotate(by: -roll * .pi * 2)
        prepare(context)
        context.setFontSize(11)
        context.setFillColor(tint(isDark: isDark, opacity: opacity).cgColor)
        // A literal @ rolls out and back; no circle or illustration is drawn.
        context.showGlyphs([glyphMap[64]], at: [CGPoint(x: -3.3, y: -3.5)])
    }

    private static func prepare(_ context: CGContext) {
        context.setFont(CTFontCopyGraphicsFont(font, nil))
        context.setFontSize(CTFontGetSize(font))
        context.setTextDrawingMode(.fill)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    }

    private static func tint(isDark: Bool, opacity: CGFloat) -> NSColor {
        isDark ? NSColor(calibratedRed: 0.65, green: 0.72, blue: 0.79, alpha: 0.58 * opacity)
            : NSColor(calibratedRed: 0.31, green: 0.40, blue: 0.49, alpha: 0.53 * opacity)
    }
}
