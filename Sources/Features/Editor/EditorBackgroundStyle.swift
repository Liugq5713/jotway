import Foundation

enum EditorBackgroundStyle: String, CaseIterable {
    case cat
    case shark
    case none

    static let defaultsKey = "editorBackgroundStyle"

    var title: String { L10n.text("settings.appearance.background.\(rawValue)") }
}
