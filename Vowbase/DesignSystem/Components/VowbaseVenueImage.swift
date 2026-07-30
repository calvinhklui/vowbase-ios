import SwiftUI

struct VowbaseVenueImage: View {
    let url: URL?

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let url {
                    AsyncImage(url: url) { phase in
                        if case let .success(image) = phase {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            venueImagePlaceholder
                        }
                    }
                } else {
                    venueImagePlaceholder
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }

    private var venueImagePlaceholder: some View {
        Image(systemName: "building.2")
            .font(.system(size: 36, weight: .light))
            .foregroundStyle(VowbaseTheme.rose.opacity(0.65))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(VowbaseTheme.blush)
    }
}
