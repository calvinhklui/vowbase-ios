import CoreLocation
import MapKit
import SwiftUI
import UIKit

// MARK: - Map

/// The persistent canvas. Present behind every lens, not just Overview — see
/// `docs/vowbase-ios-map-command-center-ux-spec.md` §2. `consoleInset` is the
/// active console's resolved height (spec §6.4), applied as safe-area padding
/// so the map's own centering keeps the selected pin clear of the sheet.
///
/// The camera is derived, never fixed: it re-frames whenever the lens, the
/// selection, or the underlying data changes, so each lens gets the frame its
/// own content deserves (see `focusCoordinates`). It previously held one
/// hardcoded region, which meant a wedding outside that region rendered a map
/// with every pin off-screen.
///
/// Every lens still renders at full weight regardless of selection — §6.2's
/// focus/context dimming (70% scale, 55% opacity for non-focused layers) is
/// not built yet. That's real remaining canvas work.
@MainActor
struct MapWorkspaceView: View {
    let store: VowbaseWorkspaceStore
    let lens: PlanLens
    let consoleInset: CGFloat
    let selectedGuestID: UUID?
    let onSelectVenue: (MVPVenue) -> Void
    let onClearFocus: () -> Void

    /// Roughly a few kilometres across — the floor so a single pin lands on a
    /// readable neighbourhood rather than a maximum-zoom rooftop.
    private static let minimumSpan: CLLocationDegrees = 0.08
    /// Breathing room around the fitted bounds so pins never sit flush to an edge.
    private static let spanPadding: CLLocationDegrees = 1.6

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            ForEach(store.venues) { venue in
                if let coordinate = venue.coordinate {
                    Annotation(venue.name, coordinate: coordinate, anchor: .bottom) {
                        Button { onSelectVenue(venue) } label: {
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
                let badge = travelBadge(for: cluster)
                Annotation(Self.clusterTitle(for: cluster), coordinate: cluster.coordinate) {
                    GuestClusterAnnotation(cluster: cluster, badge: badge)
                        .accessibilityLabel(accessibilityLabel(for: cluster, badge: badge))
                }
            }
        }
        .background {
            MapBackgroundTapObserver(bottomExclusion: consoleInset, onTap: onClearFocus)
        }
        // Points of interest are pure noise here — every restaurant and shop
        // competes with the couple's own pins, and the console's glass sits
        // directly on top of it.
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .ignoresSafeArea()
        .safeAreaPadding(.bottom, consoleInset)
        // A canvas-optional lens (Tasks, spec §2.1) contributes nothing to the
        // map, so the live map behind it is noise. Frosting it keeps the sense
        // of place without competing with the console's content.
        .overlay {
            if lens.isCanvasOptional {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: lens.isCanvasOptional)
        .onAppear { updateCamera(animated: false) }
        .onChange(of: cameraKey) { updateCamera(animated: true) }
    }

    // MARK: Camera

    /// Everything the frame depends on, collapsed into one value so a single
    /// `onChange` covers lens switches, selection changes, and the moment the
    /// data finishes loading.
    private var cameraKey: String {
        [
            lens.rawValue,
            store.selectedVenueID?.uuidString ?? "none",
            selectedGuestID?.uuidString ?? "none",
            String(store.venues.count),
            String(store.clusters.count),
        ].joined(separator: "|")
    }

    private var selectedVenueCoordinate: CLLocationCoordinate2D? {
        store.venues.first { $0.id == store.selectedVenueID }?.coordinate
    }

    private var selectedGuestCoordinate: CLLocationCoordinate2D? {
        guard let selectedGuestID,
              let guest = store.guestRecord(id: selectedGuestID),
              guest.originPrecision == "city",
              let latitude = guest.originLatitude,
              let longitude = guest.originLongitude else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }

    /// What each lens wants in frame.
    ///
    /// Venues zooms to the venue you're inspecting; Guests frames where people
    /// are travelling from; Overview holds both at once, because the whole
    /// point of that lens is the relationship between them.
    private var focusCoordinates: [CLLocationCoordinate2D] {
        let venueCoordinates = store.venues.compactMap(\.coordinate)
        let clusterCoordinates = store.clusters.map(\.coordinate)

        switch lens {
        case .venues:
            if let selectedVenueCoordinate { return [selectedVenueCoordinate] }
            return venueCoordinates
        case .guests:
            if let selectedGuestCoordinate { return [selectedGuestCoordinate] }
            return clusterCoordinates.isEmpty ? venueCoordinates : clusterCoordinates
        case .overview, .tasks:
            if let selectedVenueCoordinate { return [selectedVenueCoordinate] + clusterCoordinates }
            return venueCoordinates + clusterCoordinates
        }
    }

    private func updateCamera(animated: Bool) {
        guard let region = Self.region(fitting: focusCoordinates) else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.55)) { position = .region(region) }
        } else {
            position = .region(region)
        }
    }

    /// `nil` when there's nothing to frame — the caller leaves the camera
    /// where it is rather than snapping to an arbitrary default.
    static func region(fitting coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }

        var minLatitude = first.latitude, maxLatitude = first.latitude
        var minLongitude = first.longitude, maxLongitude = first.longitude
        for coordinate in coordinates.dropFirst() {
            minLatitude = min(minLatitude, coordinate.latitude)
            maxLatitude = max(maxLatitude, coordinate.latitude)
            minLongitude = min(minLongitude, coordinate.longitude)
            maxLongitude = max(maxLongitude, coordinate.longitude)
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLatitude - minLatitude) * spanPadding, minimumSpan),
                longitudeDelta: max((maxLongitude - minLongitude) * spanPadding, minimumSpan)
            )
        )
    }

    /// Only ever real for the selected venue's own readout — spec §8: "cluster
    /// badges show on the canvas only when the readout is showing a real
    /// number." No venue selected, no `.ready` state, no badges.
    private func travelBadge(for cluster: GuestCluster) -> String? {
        guard case let .ready(readout) = store.travelImpact,
              let travelTime = readout.durationsByClusterID[cluster.id] else { return nil }
        return travelTime.travelMode == .flight
            ? "✈︎ Flight"
            : TravelDurationFormatter.string(fromSeconds: travelTime.durationSeconds)
    }

    /// The label under each cluster pin. A single guest reads "1 guest in
    /// Northvale", not "1 guests" — it's the most prominent text on the
    /// canvas, and a wedding with one guest per city is entirely normal.
    static func clusterTitle(for cluster: GuestCluster) -> String {
        "\(cluster.count) \(cluster.count == 1 ? "guest" : "guests") in \(cluster.city)"
    }

    private func accessibilityLabel(for cluster: GuestCluster, badge: String?) -> String {
        guard let badge else { return Self.clusterTitle(for: cluster) }
        return "\(Self.clusterTitle(for: cluster)), \(badge) to selected venue"
    }
}

/// SwiftUI's `Map` does not report a basemap tap or clear custom selection.
/// This observer installs a non-cancelling recognizer on the underlying
/// `MKMapView`, ignores annotation views, and leaves MapKit's own gestures intact.
private struct MapBackgroundTapObserver: UIViewRepresentable {
    let bottomExclusion: CGFloat
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(bottomExclusion: bottomExclusion, onTap: onTap)
    }

    func makeUIView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.isUserInteractionEnabled = false
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateUIView(_ view: AttachmentView, context: Context) {
        context.coordinator.bottomExclusion = bottomExclusion
        context.coordinator.onTap = onTap
        context.coordinator.attach(to: view.window)
    }

    static func dismantleUIView(_ view: AttachmentView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class AttachmentView: UIView {
        var onWindowChange: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindowChange?(window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var bottomExclusion: CGFloat
        var onTap: () -> Void
        private weak var mapView: MKMapView?
        private var recognizer: UITapGestureRecognizer?

        init(bottomExclusion: CGFloat, onTap: @escaping () -> Void) {
            self.bottomExclusion = bottomExclusion
            self.onTap = onTap
        }

        func attach(to window: UIWindow?) {
            guard let window, let mapView = findMap(in: window), self.mapView !== mapView else { return }
            detach()
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(didTapMap(_:)))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            mapView.addGestureRecognizer(recognizer)
            self.mapView = mapView
            self.recognizer = recognizer
        }

        func detach() {
            if let recognizer { mapView?.removeGestureRecognizer(recognizer) }
            recognizer = nil
            mapView = nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let mapView,
                  touch.location(in: mapView).y < mapView.bounds.maxY - bottomExclusion else { return false }
            var touchedView: UIView? = touch.view
            while let view = touchedView, view !== mapView {
                if view is MKAnnotationView { return false }
                touchedView = view.superview
            }
            return true
        }

        @objc private func didTapMap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let mapView,
                  recognizer.location(in: mapView).y < mapView.bounds.maxY - bottomExclusion else { return }
            onTap()
        }

        private func findMap(in view: UIView) -> MKMapView? {
            if let map = view as? MKMapView { return map }
            for subview in view.subviews {
                if let map = findMap(in: subview) { return map }
            }
            return nil
        }
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
    let badge: String?

    var body: some View {
        VStack(spacing: 4) {
            Text("\(cluster.count)")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(VowbaseTheme.guestBlue, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 4))
                .shadow(color: VowbaseTheme.guestBlue.opacity(0.36), radius: 8, y: 3)

            if let badge {
                Text(badge)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
            }
        }
    }
}
