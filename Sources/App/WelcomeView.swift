import SwiftUI

/// 单页欢迎只配置基础选项，不创建记录或准备编辑器。
struct WelcomeView: View {
    let onGetStarted: () -> Void
    let onPresented: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image(nsImage: NSImage(named: "AppIcon") ?? NSApplication.shared.applicationIconImage)
                            .resizable().scaledToFit().frame(width: 72, height: 72)
                            .accessibilityHidden(true)
                        Text(L10n.text("welcome.title"))
                            .font(.system(size: 27, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text(L10n.text("welcome.subtitle"))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        RecordShortcutOptions(title: L10n.text("welcome.shortcut.title"),
                                              subtitle: L10n.text("welcome.shortcut.subtitle"))
                        Divider()
                        LaunchAtLoginToggle(title: L10n.text("welcome.login.title"),
                                            subtitle: L10n.text("welcome.login.subtitle"))
                    }
                    .padding(20)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 32)
                .padding(.top, 32)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
            }
            Divider()
            VStack(spacing: 14) {
                Text(L10n.text("welcome.change_later"))
                    .font(.callout).foregroundStyle(.secondary)
                Button(L10n.text("welcome.start"), action: onGetStarted)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint(L10n.text("welcome.start.hint"))
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .background(HintPresentation(onVisible: onPresented))
    }

}
