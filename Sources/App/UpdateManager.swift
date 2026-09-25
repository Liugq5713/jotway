import AppKit
import Foundation
import Observation
import Sparkle

@MainActor @Observable
final class UpdateManager: NSObject {
    private let preferences: UserDefaults
    @ObservationIgnored private var updaterController: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored var prepareForUpdate: (@MainActor () -> String?)?
    private(set) var updatesAvailable = false
    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecksForUpdates = false
    private(set) var availableUpdateVersion: String?
    private(set) var updateDownloadURL: URL?
    private(set) var message: String?

    init(preferences: UserDefaults) {
        self.preferences = preferences
    }

    var currentVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? L10n.text("updates.development_version")) (\(info["CFBundleVersion"] as? String ?? "—"))"
    }

    var menuTitle: String {
        availableUpdateVersion.map { L10n.text("updates.available", $0) }
            ?? L10n.text("updates.check")
    }

    func start() {
        guard updaterController == nil else { return }
        if let reason = Self.configurationIssue(Bundle.main.infoDictionary ?? [:]) {
            message = reason
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false,
            updaterDelegate: self, userDriverDelegate: self)
        updaterController = controller
        observations = [
            controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
            },
            controller.updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates }
            }
        ]
        do {
            try controller.updater.start()
            updatesAvailable = true
        } catch {
            message = L10n.text("updates.unavailable", error.localizedDescription)
            canCheckForUpdates = false
            observations = []
            updaterController = nil
        }
    }

    static func configurationIssue(_ info: [String: Any]) -> String? {
        guard info["JotwayUpdatesEnabled"] as? Bool == true else {
            return L10n.text("updates.local_build")
        }
        guard let feed = info["SUFeedURL"] as? String, let url = URL(string: feed),
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              let key = info["SUPublicEDKey"] as? String, Data(base64Encoded: key)?.count == 32 else {
            return L10n.text("updates.not_configured")
        }
        return nil
    }

    func check() {
        guard canCheckForUpdates else { return }
        message = nil
        updaterController?.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        guard updatesAvailable else { return }
        updaterController?.updater.automaticallyChecksForUpdates = enabled
    }
}

extension UpdateManager: SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    func feedParameters(for updater: SPUUpdater, sendingSystemProfile: Bool) -> [[String: String]] {
        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1_000))
        return [["key": "t", "value": timestamp,
                 "displayKey": L10n.text("updates.check_time"), "displayValue": timestamp]]
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                               andInImmediateFocus immediateFocus: Bool) -> Bool { false }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                    state: SPUUserUpdateState) {
        message = nil
        availableUpdateVersion = update.displayVersionString
        updateDownloadURL = update.fileURL.flatMap { $0.scheme == "https" ? $0 : nil }
        if !handleShowingUpdate && !state.userInitiated { updaterController?.checkForUpdates(nil) }
    }

    func standardUserDriverWillFinishUpdateSession() { availableUpdateVersion = nil }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        guard let error = error as NSError? else { return }
        guard error.domain != SUSparkleErrorDomain || error.code != SUError.noUpdateError.rawValue else {
            switch (error.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.intValue {
            case Int(SPUNoUpdateFoundReason.onLatestVersion.rawValue):
                message = L10n.text("updates.latest")
            case Int(SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue):
                message = L10n.text("updates.newer_than_latest")
            default:
                message = L10n.text("updates.none_for_device")
            }
            return
        }
        message = L10n.text("updates.failed", error.localizedDescription)
        fputs("[Jotway] Update failed (current \(currentVersion), target \(availableUpdateVersion ?? "unknown"), \(error.domain):\(error.code)): \(error.localizedDescription)\n", stderr)
    }

    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        let reason: String?
        if let prepareForUpdate { reason = prepareForUpdate() }
        else { reason = L10n.text("update.blocked.cannot_confirm_draft") }
        guard let reason else { return true }
        message = reason
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = L10n.text("updates.install_blocked")
            alert.informativeText = L10n.text("updates.install_blocked.detail", reason)
            alert.addButton(withTitle: L10n.text("common.ok"))
            alert.runModal()
        }
        return false
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        preferences.set(true, forKey: "skipFirstUseAtNextLaunch")
    }
}
