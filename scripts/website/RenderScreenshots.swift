// Render the production EditorView in an offscreen, isolated host. Never starts JotwayApp.
import AppKit
import SwiftUI
@testable import Jotway

@main
struct RenderScreenshots {
    @MainActor
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let captureSize = NSSize(width: LauncherMetrics.panelWidth, height: LauncherMetrics.inputCardMinHeight)
        let captureScale: CGFloat = 2
        for dark in [false, true] {
            for empty in [true, false] {
                let state = LauncherViewState()
                let draft = empty ? "" : "Google search macOS keyboard shortcuts"
                state.draftContent = draft
                state.displayedActionTitle = empty ? nil : L10n.text("action.chrome.title")
                let content = EditorView(text: .constant(draft), focusTarget: EditorFocusTarget(), state: state, send: { _ in })
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .frame(width: captureSize.width, height: captureSize.height)
                let host = NSHostingView(rootView: content)
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: captureSize), styleMask: .borderless, backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.backgroundColor = .clear
                window.isOpaque = false
                window.contentView = host
                host.frame = window.contentView!.bounds
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                host.displayIfNeeded()
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(captureSize.width * captureScale), pixelsHigh: Int(captureSize.height * captureScale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                bitmap.size = captureSize
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let name = empty ? "launcher-empty-\(dark ? "dark" : "light").png" : "launcher-\(dark ? "dark" : "light").png"
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
            }
        }
    }
}
