import Foundation
import KeyboardShortcuts
import Observation

@MainActor @Observable
final class OnboardingState {
    private let preferences: UserDefaults
    private(set) var needsFirstUsePresentation: Bool
    private(set) var needsCopyHint: Bool
    private(set) var hasSkippedFirstUse: Bool
    let skipsFirstUseAtLaunch: Bool

    init(preferences: UserDefaults, applicationUsageIsEmpty: Bool,
         usedPreferenceKeys: [String], hasSavedActionConfiguration: Bool) {
        self.preferences = preferences
        skipsFirstUseAtLaunch = preferences.bool(forKey: "skipFirstUseAtNextLaunch")
        preferences.removeObject(forKey: "skipFirstUseAtNextLaunch")
        let savedShortcut = preferences.object(forKey: "KeyboardShortcuts_recordNote")
        let defaults = [KeyboardShortcuts.Shortcut(.space, modifiers: [.command]),
                        KeyboardShortcuts.Shortcut(.space, modifiers: [.command, .shift])]
        let decoded = (savedShortcut as? String)?.data(using: .utf8)
            .flatMap { try? JSONDecoder().decode(KeyboardShortcuts.Shortcut.self, from: $0) }
        let hasCustomShortcut = savedShortcut != nil && !defaults.contains { $0 == decoded }
        let isNewInstallation = !preferences.bool(forKey: "hasShownFirstUse")
            && applicationUsageIsEmpty && !hasCustomShortcut
            && !hasSavedActionConfiguration
            && !usedPreferenceKeys.contains { preferences.object(forKey: $0) != nil }
        if preferences.object(forKey: "firstUseEligible") == nil {
            preferences.set(isNewInstallation, forKey: "firstUseEligible")
        }
        let eligible = preferences.bool(forKey: "firstUseEligible")
        let skipped = preferences.bool(forKey: "hasSkippedFirstUse")
        hasSkippedFirstUse = skipped
        needsFirstUsePresentation = eligible && !skipped && !preferences.bool(forKey: "hasShownFirstUse")
        needsCopyHint = eligible && !skipped && !preferences.bool(forKey: "hasShownCopyHint")
    }

    func markFirstUsePresented() {
        guard needsFirstUsePresentation else { return }
        preferences.set(true, forKey: "hasShownFirstUse")
        needsFirstUsePresentation = false
    }

    func markCopyHintPresented() {
        guard needsCopyHint else { return }
        preferences.set(true, forKey: "hasShownCopyHint")
        needsCopyHint = false
    }

    func skip() {
        preferences.set(true, forKey: "hasSkippedFirstUse")
        hasSkippedFirstUse = true
        needsFirstUsePresentation = false
        needsCopyHint = false
    }
}
