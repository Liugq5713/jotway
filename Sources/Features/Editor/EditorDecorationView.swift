import AppKit
import SwiftUI

/// The active decoration shares the editor's existing activity and visibility hooks.
@MainActor
protocol EditorDecorationView: AnyObject {
    func invalidateGeometry()
    func noteActivity()
    func setSelecting(_ selecting: Bool)
    func suspend()
    func resume()
}

struct EditorDecorationBounds {
    var controls: [Anchor<CGRect>] = []
    var target: Anchor<CGRect>?
}

struct EditorDecorationBoundsKey: PreferenceKey {
    static var defaultValue: EditorDecorationBounds { .init() }

    static func reduce(value: inout EditorDecorationBounds, nextValue: () -> EditorDecorationBounds) {
        let next = nextValue()
        value.controls.append(contentsOf: next.controls)
        if let target = next.target { value.target = target }
    }
}

extension View {
    /// Keep the visible control or label clear of background decoration.
    func editorDecorationExclusion() -> some View {
        anchorPreference(key: EditorDecorationBoundsKey.self, value: .bounds) { .init(controls: [$0]) }
    }

    func editorDecorationPerch() -> some View {
        anchorPreference(key: EditorDecorationBoundsKey.self, value: .bounds) { .init(controls: [$0], target: $0) }
    }
}

