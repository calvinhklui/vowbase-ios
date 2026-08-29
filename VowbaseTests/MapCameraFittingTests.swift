import CoreLocation
import Testing
@testable import Vowbase

/// The canvas camera used to be one hardcoded region, which put every pin
/// off-screen for any wedding outside it. These cover the fitting maths that
/// replaced it — the part that decides what the couple actually sees.
@MainActor
@Suite("Map camera fitting")
struct MapCameraFittingTests {
    private func coordinate(_ latitude: Double, _ longitude: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    @Test("Nothing to frame leaves the camera alone")
    func emptyReturnsNil() {
        #expect(MapWorkspaceView.region(fitting: []) == nil)
    }

    @Test("A single pin centres on itself at the minimum span")
    func singleCoordinateUsesMinimumSpan() throws {
        let region = try #require(MapWorkspaceView.region(fitting: [coordinate(39.5, -98.35)]))

        #expect(abs(region.center.latitude - 39.5) < 0.0001)
        #expect(abs(region.center.longitude - (-98.35)) < 0.0001)
        // A zero-extent bound must not collapse to a zero span, or the map
        // would zoom to a rooftop.
        #expect(abs(region.span.latitudeDelta - 0.08) < 0.0001)
        #expect(abs(region.span.longitudeDelta - 0.08) < 0.0001)
    }

    @Test("Several pins centre on the midpoint of their bounds")
    func multipleCoordinatesCentreOnBounds() throws {
        let region = try #require(MapWorkspaceView.region(fitting: [
            coordinate(40.0, -74.0),
            coordinate(42.0, -70.0),
        ]))

        #expect(abs(region.center.latitude - 41.0) < 0.0001)
        #expect(abs(region.center.longitude - (-72.0)) < 0.0001)
    }

    @Test("Bounds are padded so pins never sit flush to an edge")
    func spanIsPadded() throws {
        let region = try #require(MapWorkspaceView.region(fitting: [
            coordinate(40.0, -74.0),
            coordinate(41.0, -72.0),
        ]))

        // 1° of latitude and 2° of longitude, each padded by 1.6×.
        #expect(abs(region.span.latitudeDelta - 1.6) < 0.0001)
        #expect(abs(region.span.longitudeDelta - 3.2) < 0.0001)
    }

    @Test("Tightly clustered pins still get a readable span")
    func closeCoordinatesFallBackToMinimumSpan() throws {
        let region = try #require(MapWorkspaceView.region(fitting: [
            coordinate(40.0000, -74.0000),
            coordinate(40.0010, -74.0010),
        ]))

        #expect(abs(region.span.latitudeDelta - 0.08) < 0.0001)
        #expect(abs(region.span.longitudeDelta - 0.08) < 0.0001)
    }

    @Test("Cluster titles omit the redundant count and country")
    func clusterTitlesShowGuestsInCityAndState() {
        let alone = GuestCluster(id: "northvale", city: "Northvale", count: 1, latitude: 0, longitude: 0)
        let several = GuestCluster(
            id: "brooklyn",
            city: "Brooklyn, New York, United States",
            count: 4,
            latitude: 0,
            longitude: 0
        )

        #expect(MapWorkspaceView.clusterTitle(for: alone) == "Guests in Northvale")
        #expect(MapWorkspaceView.clusterTitle(for: several) == "Guests in Brooklyn, New York")
        #expect(MapWorkspaceView.clusterAccessibilityTitle(for: alone) == "1 guest in Northvale")
        #expect(MapWorkspaceView.clusterAccessibilityTitle(for: several) == "4 guests in Brooklyn, New York")
    }

    @Test("Order of the coordinates doesn't change the frame")
    func orderIndependent() throws {
        let forward = try #require(MapWorkspaceView.region(fitting: [
            coordinate(30.0, -100.0),
            coordinate(45.0, -70.0),
            coordinate(38.0, -85.0),
        ]))
        let reversed = try #require(MapWorkspaceView.region(fitting: [
            coordinate(38.0, -85.0),
            coordinate(45.0, -70.0),
            coordinate(30.0, -100.0),
        ]))

        #expect(abs(forward.center.latitude - reversed.center.latitude) < 0.0001)
        #expect(abs(forward.center.longitude - reversed.center.longitude) < 0.0001)
        #expect(abs(forward.span.latitudeDelta - reversed.span.latitudeDelta) < 0.0001)
        #expect(abs(forward.span.longitudeDelta - reversed.span.longitudeDelta) < 0.0001)
    }

    @Test("Route labels sit midway between a guest origin and venue")
    func routeMidpoint() {
        let midpoint = MapWorkspaceView.midpoint(
            from: coordinate(46.8, -92.3),
            to: coordinate(46.6, -92.1)
        )

        #expect(abs(midpoint.latitude - 46.7) < 0.0001)
        #expect(abs(midpoint.longitude - (-92.2)) < 0.0001)
    }

    @Test("Focused coordinate stays central while the frame expands around related pins")
    func focusedCoordinateAnchorsFrame() throws {
        let focus = coordinate(40.0, -74.0)
        let region = try #require(MapWorkspaceView.region(
            fitting: [focus, coordinate(42.0, -70.0)],
            centeredOn: focus
        ))

        #expect(abs(region.center.latitude - focus.latitude) < 0.0001)
        #expect(abs(region.center.longitude - focus.longitude) < 0.0001)
        #expect(abs(region.span.latitudeDelta - 6.4) < 0.0001)
        #expect(abs(region.span.longitudeDelta - 12.8) < 0.0001)
    }

    @Test("Focused coordinate renders at the centre of the map above the console")
    func consoleObstructionOffsetsCameraCenter() throws {
        let focus = coordinate(40.0, -74.0)
        let region = try #require(MapWorkspaceView.region(
            fitting: [focus],
            centeredOn: focus,
            bottomObstruction: 600,
            viewportHeight: 1_000
        ))

        // The 0.08-degree minimum span moves south by half of the 60% covered
        // fraction, placing the focused pin halfway through the visible 40%.
        #expect(abs(region.center.latitude - 39.976) < 0.0001)
        #expect(abs(region.center.longitude - focus.longitude) < 0.0001)
    }

    @Test("Cluster drill-in only returns guests in that city-level group")
    func clusterGuestMembership() throws {
        let store = VowbaseWorkspaceStore(testingWorkspace: true)
        let duluth = try #require(store.clusters.first { $0.city == "Duluth, MN" })
        let guests = store.guests(in: duluth)

        #expect(guests.count == 14)
        #expect(guests.filter { $0.rsvp == .accepted }.count == 9)
        #expect(guests.filter { $0.rsvp == .maybe }.count == 2)
        #expect(guests.filter { $0.rsvp == .pending }.count == 3)
    }

    @Test("Venue map drill-in starts unselected and computes guest reach")
    func venueReachFixture() async throws {
        let store = VowbaseWorkspaceStore(testingWorkspace: true)
        #expect(store.selectedVenueID == nil)

        let venue = try #require(store.venues.first { $0.name == "Riverside Pavilion" })
        store.selectedVenueID = venue.id
        await store.refreshTravelImpact()

        guard case let .ready(readout) = store.travelImpact else {
            Issue.record("Expected fixture guest reach to be ready")
            return
        }
        #expect(readout.durationsByClusterID.count == 4)
        #expect(readout.summaryText == "18% of guests within 2h · 2h 18m median")
        #expect(readout.isEstimated)
    }
}
