import SwiftUI

struct VowbaseCardModifier: ViewModifier {
    var padding: CGFloat = VowbaseSpace.standard

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(VowbaseDesign.surface, in: RoundedRectangle(cornerRadius: VowbaseRadius.standard, style: .continuous))
    }
}

extension View {
    func vowbaseCard(padding: CGFloat = VowbaseSpace.standard) -> some View {
        modifier(VowbaseCardModifier(padding: padding))
    }

    /// Bottom breathing room for scrollable screens above the app navigation bar.
    /// The contextual Quick Add action now occupies the bar's standalone trailing
    /// circle instead of consuming additional vertical space above it.
    func vowbaseScrollClearance(includesQuickAdd: Bool = true) -> some View {
        contentMargins(
            .bottom,
            includesQuickAdd ? VowbaseControlMetric.quickAddClearance : VowbaseSpace.large,
            for: .scrollContent
        )
    }
}

struct VowbaseStatusBadge: View {
    let title: LocalizedStringKey
    var foreground: Color = VowbaseDesign.rose
    var background: Color = VowbaseDesign.blush

    var body: some View {
        Text(title)
            .font(VowbaseType.badge)
            .foregroundStyle(foreground)
            .padding(.horizontal, VowbaseSpace.medium)
            .padding(.vertical, VowbaseSpace.small)
            .background(background, in: Capsule())
            .accessibilityAddTraits(.isStaticText)
    }
}

struct VowbasePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(VowbaseType.headline)
            .foregroundStyle(VowbaseDesign.onRose)
            .frame(minHeight: VowbaseControlMetric.minimumTapTarget)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, VowbaseSpace.standard)
            .background(VowbaseDesign.rose.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: VowbaseRadius.standard, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: VowbaseRadius.standard, style: .continuous))
    }
}

/// A semantic confirmation action for the system navigation bar.
///
/// The toolbar owns sizing, hit testing, material, and pressed appearance so
/// the control follows the current OS instead of drawing a parallel button.
struct VowbaseConfirmationToolbarButton: View {
    let accessibilityLabel: LocalizedStringKey
    let isDisabled: Bool
    let action: () -> Void

    init(
        _ accessibilityLabel: LocalizedStringKey = "Save",
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.accessibilityLabel = accessibilityLabel
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
        }
        .tint(VowbaseTheme.rose)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
    }
}
