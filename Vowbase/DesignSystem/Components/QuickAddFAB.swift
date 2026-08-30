import SwiftUI
import UIKit

/// A reusable, floating entry point for Vowbase's core creation flows.
///
/// Pair this with `QuickAddPanel` inside `QuickAddOverlay` so the expanded
/// action has a dismissible scrim and never feels like an unanchored popover.
struct QuickAddFAB: View {
    let isExpanded: Bool
    let accessibilityHint: String
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        if #available(iOS 26, *) {
            button
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(VowbaseTheme.rose).interactive(), in: Circle())
        } else {
            button
                .buttonStyle(QuickAddPressStyle())
                .background(VowbaseTheme.rose, in: Circle())
                .shadow(color: VowbaseTheme.rose.opacity(0.32), radius: 14, y: 7)
        }
    }

    private var button: some View {
        Button {
            QuickAddHaptics.impact()
            action()
        } label: {
            Image(systemName: isExpanded ? "xmark" : "plus")
                .font(.system(size: 23, weight: .semibold))
                .frame(width: VowbaseControlMetric.fabDiameter, height: VowbaseControlMetric.fabDiameter)
                .foregroundStyle(.white)
                .contentShape(Circle())
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .accessibilityLabel(isExpanded ? "Close quick add" : "Quick add")
        .accessibilityHint(isExpanded ? "Dismisses quick add actions" : accessibilityHint)
    }
}

/// A lens-specific FAB that opens its creation flow immediately.
///
/// Lenses with a single creation choice use this control so their action and
/// accessibility semantics stay explicit.
struct DirectAddFAB: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        if #available(iOS 26, *) {
            button
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(VowbaseTheme.rose).interactive(), in: Circle())
        } else {
            button
                .buttonStyle(QuickAddPressStyle())
                .background(VowbaseTheme.rose, in: Circle())
                .shadow(color: VowbaseTheme.rose.opacity(0.32), radius: 14, y: 7)
        }
    }

    private var button: some View {
        Button {
            QuickAddHaptics.impact()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: VowbaseControlMetric.fabDiameter, height: VowbaseControlMetric.fabDiameter)
                .foregroundStyle(.white)
                .contentShape(Circle())
        }
        .accessibilityLabel(title)
        .accessibilityHint("Opens the \(title.lowercased()) form")
    }
}

/// High-confidence actions shown above `QuickAddFAB`.
///
/// The actions dismiss the panel before invoking their closures, allowing the
/// caller to present its destination sheet without competing presentations.
struct QuickAddPanel: View {
    @Binding var isPresented: Bool
    let actions: [QuickAddAction]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                if index > 0 {
                    Divider()
                        .padding(.leading, 64)
                }

                quickAddRow(
                    title: action.title,
                    icon: action.icon,
                    tint: action.tint,
                    action: action.action
                )
            }
        }
        .padding(8)
        .frame(minWidth: 240, maxWidth: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(VowbaseTheme.border.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick add actions")
        .transition(reduceMotion ? .opacity : .scale(scale: 0.92, anchor: .bottomTrailing).combined(with: .opacity))
    }

    private func quickAddRow(
        title: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            dismissThenPerform(action)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(title)
                    .font(.headline)
                    .foregroundStyle(VowbaseTheme.ink)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 56)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(QuickAddRowStyle())
        .accessibilityLabel(title)
    }

    private func dismissThenPerform(_ action: @escaping () -> Void) {
        QuickAddHaptics.selection()
        withAnimation(reduceMotion ? .linear(duration: 0.12) : .snappy(duration: 0.24, extraBounce: 0.06)) {
            isPresented = false
        }

        // Presenting on the next main-loop cycle prevents a sheet and the
        // panel's dismissal animation from fighting over the same transaction.
        DispatchQueue.main.async(execute: action)
    }
}

struct QuickAddAction: Identifiable {
    let id: String
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void
}

/// A compact control that keeps its panel anchored directly above the FAB.
///
/// The parent owns any full-screen dismissal backdrop so this view retains its
/// intrinsic size when used with `.overlay(alignment: .bottomTrailing)`.
struct QuickAddOverlay: View {
    @Binding var isPresented: Bool
    let actions: [QuickAddAction]

    init(
        isPresented: Binding<Bool>,
        onAddVenue: @escaping () -> Void,
        onAddGuest: @escaping () -> Void,
        onAddTask: @escaping () -> Void
    ) {
        _isPresented = isPresented
        actions = [
            QuickAddAction(id: "venue", title: "Add Venue", icon: "mappin.and.ellipse", tint: VowbaseTheme.rose, action: onAddVenue),
            QuickAddAction(id: "guest", title: "Add Guest", icon: "person.badge.plus", tint: VowbaseTheme.guestBlue, action: onAddGuest),
            QuickAddAction(id: "task", title: "Add Task", icon: "checkmark.circle.badge.plus", tint: VowbaseTheme.rose, action: onAddTask),
        ]
    }

    init(isPresented: Binding<Bool>, actions: [QuickAddAction]) {
        _isPresented = isPresented
        self.actions = actions
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        QuickAddFAB(
            isExpanded: isPresented,
            accessibilityHint: "Shows actions to \(actions.map(\.title).joined(separator: ", ").lowercased())",
            action: toggle
        )
        .overlay(alignment: .bottomTrailing) {
            if isPresented {
                QuickAddPanel(
                    isPresented: $isPresented,
                    actions: actions
                )
                .fixedSize(horizontal: true, vertical: false)
                .padding(.bottom, VowbaseControlMetric.fabDiameter + VowbaseSpace.medium)
            }
        }
        .animation(reduceMotion ? .linear(duration: 0.12) : .snappy(duration: 0.28, extraBounce: 0.08), value: isPresented)
    }

    private func toggle() {
        withAnimation(reduceMotion ? .linear(duration: 0.12) : .snappy(duration: 0.28, extraBounce: 0.08)) {
            isPresented.toggle()
        }
    }

}

private struct QuickAddPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct QuickAddRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? VowbaseTheme.rose.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

@MainActor
private enum QuickAddHaptics {
    static func impact() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred()
    }

    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}
