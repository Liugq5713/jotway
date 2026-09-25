// Compose actual captured UI images with annotations outside the product UI.
import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let width = 720.0, height = 620.0
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = NSSize(width: width, height: height)
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
context.cgContext.translateBy(x: 0, y: height)
context.cgContext.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
let ink = NSColor(srgbRed: 0.09, green: 0.13, blue: 0.22, alpha: 1)
let muted = NSColor(srgbRed: 0.34, green: 0.39, blue: 0.48, alpha: 1)
let blue = NSColor(srgbRed: 0.14, green: 0.36, blue: 0.92, alpha: 1)
NSColor(srgbRed: 0.96, green: 0.975, blue: 0.995, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
func text(_ content: String, x: Double, y: Double, size: Double, color: NSColor, bold: Bool = false) {
    (content as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular), .foregroundColor: color])
}
func image(_ name: String, x: Double, y: Double, width: Double) {
    let source = NSImage(contentsOf: directory.appendingPathComponent(name))!
    let height = width * source.size.height / source.size.width
    source.draw(in: NSRect(x: x, y: y, width: width, height: height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
}
text("Jotway", x: 32, y: 23, size: 21, color: ink, bold: true)
text("Type. Check the Action. Press Enter.", x: 127, y: 28, size: 13, color: muted)
let labels = ["Open / 唤起", "Type & check / 输入并查看目标", "Enter → Google Search in Chrome"]
let details = ["Your shortcut · Menu bar · Dock", "Google Search is the selected Action", "The same text reaches the selected app"]
for index in 0..<3 {
    let top = 80.0 + Double(index) * 167
    blue.setFill()
    NSBezierPath(roundedRect: NSRect(x: 32, y: top, width: 30, height: 30), xRadius: 8, yRadius: 8).fill()
    text(String(index + 1), x: 43, y: top + 5, size: 16, color: .white, bold: true)
    text(labels[index], x: 78, y: top - 1, size: 17, color: ink, bold: true)
    text(details[index], x: 78, y: top + 24, size: 12, color: muted)
    if index < 2 {
        image(index == 0 ? "launcher-empty-light.png" : "launcher-dark.png", x: 78, y: top + 51, width: 560)
    } else {
        NSColor(srgbRed: 0.13, green: 0.14, blue: 0.16, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 78, y: top + 51, width: 560, height: 88), xRadius: 12, yRadius: 12).fill()
        image("chrome-search.png", x: 87, y: top + 56, width: 542)
    }
}
text("Current UI · Synthetic text · Separate steps, not a history view", x: 78, y: 588, size: 12, color: muted)
NSGraphicsContext.current = nil
try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("README-flow.png"))
