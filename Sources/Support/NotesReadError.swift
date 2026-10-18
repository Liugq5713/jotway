import Foundation


enum NotesReadError: Error, LocalizedError, RuntimeLogError {
    case response, unavailable, stale, tooLarge, ambiguous
    var errorDescription: String? { L10n.text("notes.read.error.\(self)") }
    var runtimeLogCode: RuntimeLog.Code {
        switch self {
        case .stale: .stale
        case .response, .ambiguous: .validation
        case .tooLarge: .inputTooLarge
        case .unavailable: .unavailable
        }
    }
}
