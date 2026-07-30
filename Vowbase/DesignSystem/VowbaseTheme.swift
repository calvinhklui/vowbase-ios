import SwiftUI
import UIKit

/// Semantic, appearance-aware values for all Vowbase surfaces and accents.
///
/// Use these names instead of raw RGB values in feature views. Neutral colors
/// deliberately come from UIKit's semantic palette so they also respond to
/// Increased Contrast and system appearance changes.
enum VowbaseDesign {
    // MARK: - Surfaces

    static let background = Color(uiColor: .systemBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let elevatedSurface = Color(uiColor: .tertiarySystemBackground)
    static let fill = Color(uiColor: .tertiarySystemFill)
    static let separator = Color(uiColor: .separator)

    // MARK: - Content

    static let textPrimary = Color(uiColor: .label)
    static let textSecondary = Color(uiColor: .secondaryLabel)
    static let textTertiary = Color(uiColor: .tertiaryLabel)

    // MARK: - Brand

    static let rose = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.41, blue: 0.59, alpha: 1)
            : UIColor(red: 0.76, green: 0.15, blue: 0.35, alpha: 1)
    })

    static let blush = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.24, green: 0.11, blue: 0.16, alpha: 1)
            : UIColor(red: 1.0, green: 0.93, blue: 0.95, alpha: 1)
    })

    static let guestBlue = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.38, green: 0.60, blue: 1.0, alpha: 1)
            : UIColor(red: 0.08, green: 0.31, blue: 0.80, alpha: 1)
    })

    /// Foreground color for text or symbols placed on the rose accent.
    static let onRose = Color.white
}

// MARK: - Feature-facing aliases and title/eyebrow helpers moved from ContentView.swift's split (Phase 0)
enum VowbaseTheme {
    static let background = VowbaseDesign.background
    static let groupedBackground = VowbaseDesign.groupedBackground
    static let ink = VowbaseDesign.textPrimary
    static let mutedInk = VowbaseDesign.textSecondary
    static let rose = VowbaseDesign.rose
    static let blush = VowbaseDesign.blush
    static let border = VowbaseDesign.separator
    static let guestBlue = VowbaseDesign.guestBlue
}

extension Text {
    func displayTitle() -> some View {
        font(VowbaseType.screenDisplay)
            .foregroundStyle(VowbaseTheme.ink)
    }

    func eyebrow() -> some View {
        font(VowbaseType.eyebrow)
            .tracking(1.6)
            .foregroundStyle(VowbaseTheme.rose)
    }
}
