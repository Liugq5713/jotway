import Foundation
import KeyboardShortcuts
import Observation

@MainActor @Observable
final class ShortcutTrial {
    private enum MessageState {
        case issue(String)
        case instruction(String)
        case success
    }

    private(set) var isTrying = false
    private var messageState: MessageState?
    var message: String? {
        switch messageState {
        case .issue(let issue): issue
        case .instruction(let shortcut): L10n.text("shortcut.trial.instruction", shortcut)
        case .success: L10n.text("shortcut.trial.success")
        case nil: nil
        }
    }
    private var shortcut: KeyboardShortcuts.Shortcut?
    private var leftJotway = false

    @discardableResult
    func begin(shortcut: KeyboardShortcuts.Shortcut?, issue: String?) -> Bool {
        cancel()
        guard let shortcut, issue == nil else {
            messageState = .issue(issue ?? L10n.text("shortcut.trial.setup_first"))
            return false
        }
        self.shortcut = shortcut
        isTrying = true
        messageState = .instruction(shortcut.description)
        return true
    }

    func leftApplication() {
        if isTrying { leftJotway = true }
    }

    func canComplete(shortcut: KeyboardShortcuts.Shortcut?, fromExternalApplication: Bool) -> Bool {
        isTrying && leftJotway && fromExternalApplication && shortcut == self.shortcut
    }

    @discardableResult
    func complete(shortcut: KeyboardShortcuts.Shortcut?, fromExternalApplication: Bool, presented: Bool) -> Bool {
        guard presented, canComplete(shortcut: shortcut, fromExternalApplication: fromExternalApplication) else { return false }
        cancel()
        messageState = .success
        return true
    }

    func cancel() {
        isTrying = false
        shortcut = nil
        leftJotway = false
        messageState = nil
    }

    static func status(
        shortcut: KeyboardShortcuts.Shortcut? = KeyboardShortcuts.getShortcut(for: .recordNote),
        registrationError: Int32? = KeyboardShortcuts.registrationError(for: .recordNote),
        isTakenBySystem: Bool = KeyboardShortcuts.isTakenBySystem(.recordNote),
        macOSMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
        isAvailable: @MainActor (KeyboardShortcuts.Shortcut) -> Bool = KeyboardShortcuts.isAvailableForRecommendation
    ) -> (shortcut: KeyboardShortcuts.Shortcut?, issue: String?, recommendation: KeyboardShortcuts.Shortcut?) {
        let issue: String?
        if shortcut == nil { issue = L10n.text("shortcut.issue.not_set") }
        else if let code = registrationError { issue = L10n.text("shortcut.issue.registration", code) }
        else if isTakenBySystem { issue = L10n.text("shortcut.issue.system_conflict") }
        else if macOSMajorVersion >= 27, shortcut == .init(.space, modifiers: [.command, .shift]) {
            issue = L10n.text("shortcut.issue.siri_conflict")
        } else { issue = nil }
        let candidates: [KeyboardShortcuts.Shortcut] = [
            .init(.r, modifiers: [.control, .command]),
            .init(.r, modifiers: [.control, .shift, .command]),
            .init(.space, modifiers: [.control, .option, .command]),
        ]
        return (shortcut, issue, issue == nil ? nil : candidates.first { $0 != shortcut && isAvailable($0) })
    }

    static func adopt(_ shortcut: KeyboardShortcuts.Shortcut,
                      isAvailable: @MainActor (KeyboardShortcuts.Shortcut) -> Bool = KeyboardShortcuts.isAvailableForRecommendation,
                      save: (KeyboardShortcuts.Shortcut) -> Void = { KeyboardShortcuts.setShortcut($0, for: .recordNote) }) -> String? {
        guard isAvailable(shortcut) else { return L10n.text("shortcut.issue.recommendation_unavailable") }
        save(shortcut)
        return nil
    }
}
