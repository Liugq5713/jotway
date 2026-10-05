import SwiftUI

struct JevSettingsView: View {
    let appState: AppState
    private let settings: JevSettings

    init(appState: AppState, settings: JevSettings = .shared) {
        self.appState = appState
        self.settings = settings
    }

    var body: some View {
        Group {
            Section {
                JevServiceSettingsView(settings: settings)
            }
            IntentRulesSettingsView(appState: appState)
            OperationRecordSettings(appState: appState)
        }
    }
}
