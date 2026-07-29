import SwiftUI

/// Dynamic Type-aware typography roles. The system serif design resolves to
/// New York on iOS; interface roles use the platform's SF family.
enum VowbaseType {
    static let screenDisplay = Font.system(.largeTitle, design: .serif, weight: .regular)
    static let detailTitle = Font.system(.title, design: .serif, weight: .regular)
    static let cardTitle = Font.system(.title3, design: .serif, weight: .regular)
    static let headline = Font.system(.headline, design: .default, weight: .semibold)
    static let body = Font.system(.body, design: .default, weight: .regular)
    static let secondary = Font.system(.subheadline, design: .default, weight: .regular)
    static let caption = Font.system(.caption, design: .default, weight: .regular)
    static let badge = Font.system(.subheadline, design: .default, weight: .semibold)
    static let eyebrow = Font.system(.caption, design: .default, weight: .bold)
}

extension Text {
    func vowbaseScreenDisplay() -> some View {
        font(VowbaseType.screenDisplay)
            .foregroundStyle(VowbaseDesign.textPrimary)
    }

    func vowbaseEyebrow() -> some View {
        font(VowbaseType.eyebrow)
            .tracking(1.6)
            .foregroundStyle(VowbaseDesign.rose)
    }
}
