import SwiftUI

/// Visual choices apply immediately through bindings or shared local preferences.
struct AppearanceSettingsView: View {
    @Binding var themeMode: ThemeMode
    @Binding var submissionEffect: SubmissionEffect
    @AppStorage(EditorBackgroundStyle.defaultsKey) private var editorBackground: EditorBackgroundStyle = .cat
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(ThemeMode.allCases, id: \.self) { mode in
                        themeChoice(mode)
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text(L10n.text("settings.general.theme"))
            }
            Section {
                Picker(L10n.text("settings.appearance.background"), selection: $editorBackground) {
                    ForEach(EditorBackgroundStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .help(L10n.text("settings.appearance.background.help"))
                .accessibilityHint(L10n.text("settings.appearance.background.help"))
                .accessibilityIdentifier("editor-background-style")
            }
            Section {
                Picker(L10n.text("settings.general.submission_effect"), selection: $submissionEffect) {
                    ForEach(SubmissionEffect.allCases, id: \.self) { effect in
                        Text(effect.title).tag(effect)
                    }
                }
                .pickerStyle(.menu)
                .help(L10n.text("settings.general.submission_effect.help"))
                .accessibilityHint(L10n.text("settings.general.submission_effect.help"))
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func themeChoice(_ mode: ThemeMode) -> some View {
        let isSelected = themeMode == mode
        return Button {
            themeMode = mode
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    Spacer(minLength: 4)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                Text(mode.title)
                    .font(.body.weight(.semibold))
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .padding(14)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.025),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(contrast == .increased ? 0.7 : 0.15),
                                  lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help(mode.detail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode.title)
        .accessibilityHint(mode.detail)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("theme-\(mode.rawValue)")
    }
}
