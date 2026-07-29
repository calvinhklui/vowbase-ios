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
