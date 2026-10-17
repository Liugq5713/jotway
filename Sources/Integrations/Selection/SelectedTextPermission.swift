import AppKit
@preconcurrency import ApplicationServices
import Observation

@MainActor @Observable
final class SelectedTextPermission {
    static let shared = SelectedTextPermission()
    private(set) var granted = false
    private var didShowNotice = false
    private let check: () -> Bool
    private let request: () -> Void
    init(check: @escaping () -> Bool = { AXIsProcessTrusted() }, request: @escaping () -> Void = {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }) { self.check = check; self.request = request }
    func refresh() { granted = check() }
    func requestAccess() { request(); refresh() }
    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    func takeNotice(existingMessage: String?) -> String? {
        refresh()
        guard !granted, !didShowNotice, existingMessage == nil else { return nil }
        didShowNotice = true
        return L10n.text("selected_text.notice")
    }
}
