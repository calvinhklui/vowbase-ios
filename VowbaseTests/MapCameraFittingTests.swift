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
}
