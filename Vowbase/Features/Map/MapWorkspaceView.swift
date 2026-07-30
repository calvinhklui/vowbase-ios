import CoreLocation
import MapKit
import SwiftUI

// MARK: - Map

@MainActor
struct MapWorkspaceView: View {
    let store: VowbaseWorkspaceStore
    let onSignOut: () -> Void
    @State private var showsVenues = true
    @State private var showsGuests = true
    @State private var position = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.2, longitude: -74.4),
            span: MKCoordinateSpan(latitudeDelta: 11.5, longitudeDelta: 13.0)
        )
    )

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position) {
                if showsVenues {
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
                }

                if showsGuests {
                    ForEach(store.clusters) { cluster in
                        Annotation("\(cluster.count) guests in \(cluster.city)", coordinate: cluster.coordinate) {
                            GuestClusterAnnotation(cluster: cluster)
                                .accessibilityLabel("\(cluster.count) guests in \(cluster.city)")
                        }
                    }
                }
            }
            .mapControlVisibility(.hidden)
            .ignoresSafeArea(edges: .top)

            VStack(alignment: .leading, spacing: 20) {
                IdentityBar(weddingTitle: store.weddingTitle, onSignOut: onSignOut)
                HStack(spacing: 10) {
                    LayerChip(title: "Venues", icon: "mappin", isOn: $showsVenues, tint: VowbaseTheme.rose)
                    LayerChip(title: "Guests", icon: "person.2", isOn: $showsGuests, tint: VowbaseTheme.guestBlue)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ShortlistPanel(store: store)
            .padding(.bottom, 8)
        }
    }
}

private struct LayerChip: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    let tint: Color

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                Text(title)
                Image(systemName: isOn ? "checkmark" : "eye.slash")
                    .font(.system(size: 12, weight: .bold))
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(isOn ? tint : VowbaseTheme.mutedInk)
            .padding(.horizontal, 18)
            .frame(minHeight: 52)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(isOn ? tint.opacity(0.38) : VowbaseTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "Visible" : "Hidden")
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

@MainActor
private struct ShortlistPanel: View {
    let store: VowbaseWorkspaceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(VowbaseTheme.border)
                .frame(width: 76, height: 7)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            HStack {
                Text("Shortlist")
                    .font(.system(size: 34, weight: .regular, design: .serif))
                Spacer()
                Text("\(store.venues.count) venues")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }

            if let selectedVenue = store.venues.first(where: { $0.id == store.selectedVenueID }) ?? store.venues.first {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(store.venues) { venue in
                            Button { store.selectedVenueID = venue.id } label: {
                                MapVenueCard(venue: venue, selected: venue.id == selectedVenue.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .contentMargins(.trailing, 18, for: .scrollContent)
            } else {
                Text("Add a venue to start your shortlist.")
                    .font(.system(size: 16))
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 34, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 34, style: .continuous))
    }
}

private struct MapVenueCard: View {
    let venue: MVPVenue
    let selected: Bool

    var body: some View {
        HStack(spacing: 0) {
            VowbaseVenueImage(url: venue.photoURL)
                .frame(width: 106, height: 148)
            VStack(alignment: .leading, spacing: 10) {
                Text(venue.name)
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .lineLimit(2)
                StatusCapsule(status: venue.status)
                Label(venue.location, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 14))
                    .foregroundStyle(VowbaseTheme.mutedInk)
                Divider()
                Label("\(venue.travel) median guest travel", systemImage: "airplane")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(VowbaseTheme.ink)
                    .lineLimit(2)
            }
            .padding(16)
            .frame(width: 165, height: 148, alignment: .leading)
        }
        .background(VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(selected ? VowbaseTheme.rose : VowbaseTheme.border, lineWidth: selected ? 1.5 : 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
    }
}

