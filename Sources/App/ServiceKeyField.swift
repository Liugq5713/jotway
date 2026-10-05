import SwiftUI

struct ServiceKeyField: View {
    let accessibilityTitle: String
    let keyURL: URL
    let hasKey: Bool
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.text("settings.key.section"))
                    .font(.callout.weight(.medium))
                Spacer(minLength: 8)
                Link(destination: keyURL) {
                    HStack(spacing: 4) {
                        Text(L10n.text("settings.key.get_short"))
                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            HStack(spacing: 10) {
                Image(systemName: "key.horizontal")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                SecureField(L10n.text("settings.key.section"), text: $text,
                            prompt: Text(L10n.text(hasKey ? "settings.key.replace_placeholder" : "settings.key.placeholder")))
                    .textFieldStyle(.plain)
                    .labelsHidden()
                    .font(.system(size: 13))
                    .textContentType(.password)
                    .accessibilityLabel(accessibilityTitle)
                    .focused(isFocused)
                    .onSubmit(save)
                    .frame(maxWidth: .infinity)

                Button(L10n.text(hasKey ? "settings.key.replace" : "settings.key.save"), action: save)
                    .buttonStyle(ServiceSettingsButtonStyle(prominent: true))
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(6)
            .padding(.leading, 8)
            .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isFocused.wrappedValue ? Color.accentColor.opacity(0.65) : .primary.opacity(0.1),
                                  lineWidth: isFocused.wrappedValue ? 1.5 : 1)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct ServiceKeyStatus: View {
    let hasKey: Bool

    var body: some View {
        Label(L10n.text(hasKey ? "settings.key.saved_badge" : "settings.key.not_saved"),
              systemImage: hasKey ? "checkmark.circle.fill" : "key")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.primary.opacity(0.04), in: Capsule())
            .fixedSize()
            .accessibilityAddTraits(.updatesFrequently)
    }
}

struct ServiceSettingsButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(height: 30)
            .foregroundStyle(prominent && isEnabled ? Color.white : .primary.opacity(isEnabled ? 0.8 : 0.3))
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(prominent && isEnabled ? Color.accentColor : .primary.opacity(isEnabled ? 0.06 : 0.035))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.primary.opacity(isEnabled && (isHovered || configuration.isPressed) ? 0.06 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onHover { isHovered = $0 }
    }
}
