import SwiftUI

/// All choices write through the existing app-level binding and saved theme preference.
struct AppearanceSettingsView: View {
    @Binding var themeMode: ThemeMode
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
            } footer: {
                Text(L10n.text("settings.appearance.saved_help"))
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
                Text(mode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
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
