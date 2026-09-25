import KeyboardShortcuts
import SwiftUI

/// 菜单栏下拉菜单。
/// 记录 = 全局热键；处理 = 菜单栏点击（动作频率匹配召唤成本）。
struct MenuContent: View {
    let appState: AppState
    let panelController: PanelController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(L10n.text("menu.quick_record")) {
            panelController.showRecordPanel()
        }
        .globalKeyboardShortcut(.recordNote)

        Divider()

        Button(L10n.text("menu.getting_started")) {
            panelController.openGettingStarted { openSettings() }
        }

        // 设置入口：开机自启已迁入设置面板（docs/product/settings.md）。
        // 不用 SettingsLink：LSUIElement + MenuBarExtra 下经常无响应，改用 openSettings 环境 action。
        Button(L10n.text("menu.settings")) {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",", modifiers: [.command])

        Button(appState.updateMenuTitle) { appState.checkForUpdates() }
            .disabled(!appState.canCheckForUpdates)

        Divider()

        Button(L10n.text("menu.quit")) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

/// 菜单栏图标：启动器入口。
struct MenuBarLabel: View {
    static let icon: NSImage? = {
        let image = NSImage(named: "JotwayMenuBarTemplate")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        return image
    }()

    var body: some View {
        HStack(spacing: 2) {
            if let icon = Self.icon {
                Image(nsImage: icon)
                    .renderingMode(.template)
            } else {
                // swift run 不经过应用打包，保留可见的开发态图标。
                Image(systemName: "tray")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jotway")
    }
}
