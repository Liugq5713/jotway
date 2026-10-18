import AppKit
import Foundation

@main
@MainActor
enum JotwayBootstrap {
    /// No AppState, property wrappers, hotkey, stores or shared credential reader exists before this returns.
    static func enter(prepare: () throws -> Void, start: () -> Void) rethrows {
        try prepare()
        start()
    }

    static func main() {
        var selectedContainer: URL?
        while true {
            do {
                guard let home = StorageLocation.userHome else { throw StorageMigration.Failure.inaccessible }
                let defaults = UserDefaults.standard
                let bundleID = StorageLocation.bundleID
                try enter(prepare: {
                    try StorageMigration(paths: .init(home: home, container: selectedContainer),
                        sourceIsRunning: {
                            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                                .contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
                        }, readPreferences: { defaults.persistentDomain(forName: bundleID) ?? [:] },
                        writePreferences: { values in
                            defaults.setPersistentDomain(values, forName: bundleID)
                            guard defaults.synchronize() else { throw StorageMigration.Failure.preferences }
                        }).run()
                }, start: { JotwayApp.main() })
                return
            } catch {
                // Recovery has no business dependencies. Underlying errors may contain private paths.
                let reason = (error as? StorageMigration.Failure) ?? .inaccessible
                let alert = NSAlert()
                alert.messageText = L10n.text("migration.title")
                alert.informativeText = reason.localizedDescription + "\n\n" + L10n.text("migration.recovery")
                alert.addButton(withTitle: L10n.text("migration.retry"))
                alert.addButton(withTitle: L10n.text("migration.choose"))
                alert.addButton(withTitle: L10n.text("menu.quit"))
                NSApplication.shared.setActivationPolicy(.regular)
                NSApplication.shared.activate(ignoringOtherApps: true)
                switch alert.runModal() {
                case .alertFirstButtonReturn: continue
                case .alertSecondButtonReturn:
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true; panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url,
                       url.lastPathComponent == StorageLocation.bundleID { selectedContainer = url }
                default: return
                }
            }
        }
    }
}
