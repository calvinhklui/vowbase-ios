import CoreLocation
import MapKit
import SwiftUI

// MARK: - Map

/// The persistent canvas. Present behind every lens, not just Overview — see
/// `docs/vowbase-ios-map-command-center-ux-spec.md` §2. `consoleInset` is the
/// active console's resolved height (spec §6.4), applied as safe-area padding
/// so the map's own centering keeps the selected pin clear of the sheet.
///
/// Every lens still renders at full weight regardless of selection — §6.2's
/// focus/context dimming (70% scale, 55% opacity for non-focused layers) is
/// not built yet. That's real remaining canvas work, not a Phase 2 goal.
@MainActor
struct MapWorkspaceView: View {
    let store: VowbaseWorkspaceStore
    let consoleInset: CGFloat
    @State private var position = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.2, longitude: -74.4),
            span: MKCoordinateSpan(latitudeDelta: 11.5, longitudeDelta: 13.0)
        )
    )

    var body: some View {
        Map(position: $position) {
            ForEach(store.venues) { venue in
                if let coordinate = venue.coordinate {
                    Annotation(venue.name, coordinate: coordinate, anchor: .bottom) {
                        Button {
                            store.selectedVenueID = venue.id
                        } label: {
                            VenueMapAnnotation(
                                venue: venue,
                                selected: store.selectedVenueID == venue.id
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(venue.name), \(venue.status.title)")
                    }
                }
            }

            ForEach(store.clusters) { cluster in
                Annotation("\(cluster.count) guests in \(cluster.city)", coordinate: cluster.coordinate) {
                    GuestClusterAnnotation(cluster: cluster)
                        .accessibilityLabel("\(cluster.count) guests in \(cluster.city)")
                }
            }
        }
        .mapControlVisibility(.hidden)
        .ignoresSafeArea()
        .safeAreaPadding(.bottom, consoleInset)
    }
}

private struct VenueMapAnnotation: View {
    let venue: MVPVenue
    let selected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: selected ? 30 : 25))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, VowbaseTheme.rose)
            if selected {
                Text(venue.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.thinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(VowbaseTheme.rose.opacity(0.45), lineWidth: 1))
            }
        }
        .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
    }
}

private struct GuestClusterAnnotation: View {
    let cluster: GuestCluster

    var body: some View {
        Text("\(cluster.count)")
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(VowbaseTheme.guestBlue, in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 4))
            .shadow(color: VowbaseTheme.guestBlue.opacity(0.36), radius: 8, y: 3)
    }
}
