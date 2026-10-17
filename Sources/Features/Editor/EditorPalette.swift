import AppKit

/// 同一套中性颜色供 SwiftUI 卡片与 AppKit 正文、placeholder、光标使用。
enum EditorPalette {
    static let surface = adaptive(0xF8F7F3, 0x303436)
    // 浅色描边贴近表面：卡片边缘主要靠窗口阴影托出，描边只做极淡的收边，别压在浅背景上。
    static let outline = adaptive(0xEAE8E2, 0x3B4042)
    static let text = adaptive(0x333631, 0xE5E5DE)
    static let secondary = adaptive(0x6D726C, 0x9CA19D)
    static let button = adaptive(0xE6EBEB, 0x3D474B)
    static let buttonActive = adaptive(0xDCE3E4, 0x394347)
    static let buttonText = adaptive(0x52646A, 0xC0CDD0)
    static let keycap = adaptive(0xDFE5ED, 0x3A4350)
    static let accent = adaptive(0x748D9A, 0x8AA5B2)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        }
    }
}
