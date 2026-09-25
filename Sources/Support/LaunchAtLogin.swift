import ServiceManagement
import SwiftUI

/// 开机自启（SMAppService）。
enum LaunchAtLogin {
    static func currentState(status: SMAppService.Status = SMAppService.mainApp.status) -> (isEnabled: Bool, issue: String?) {
        let issue = status == .requiresApproval ? L10n.text("login.requires_approval") : nil
        return (status == .enabled, issue)
    }

    static func set(
        _ enabled: Bool,
        update: (Bool) throws -> Void = { enabled in
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        },
        readStatus: () -> SMAppService.Status = { SMAppService.mainApp.status }
    ) -> (isEnabled: Bool, issue: String?) {
        var failure: String?
        do {
            try update(enabled)
        } catch {
            failure = L10n.text("login.change_failed", error.localizedDescription)
        }
        let actual = currentState(status: readStatus())
        return (actual.isEnabled, actual.issue ?? failure
            ?? (actual.isEnabled != enabled ? L10n.text("login.not_applied") : nil))
    }
}

/// 欢迎页与设置页都以系统回读结果显示开关；刷新不会再次写入登录项。
struct LaunchAtLoginToggle: View {
    var title = L10n.text("settings.general.launch_at_login")
    var subtitle: String?
    @State private var state = LaunchAtLogin.currentState()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 12)
                Toggle(title, isOn: Binding(get: { state.isEnabled }, set: { state = LaunchAtLogin.set($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            if let issue = state.issue {
                Text(issue).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
                Button(L10n.text("login.open_settings")) { SMAppService.openSystemSettingsLoginItems() }
                    .buttonStyle(.link)
            }
        }
        .onAppear { state = LaunchAtLogin.currentState() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state = LaunchAtLogin.currentState()
        }
    }
}
