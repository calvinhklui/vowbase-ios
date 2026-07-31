import Foundation
import Testing
@testable import Vowbase

@Suite("Travel impact calculator")
struct TravelImpactCalculatorTests {
    private func cluster(_ id: String, count: Int) -> GuestCluster {
        GuestCluster(id: id, city: id, count: count, latitude: 0, longitude: 0)
    }

    private func travelTime(
        _ id: String,
        seconds: Int,
        mode: TravelMode = .drive,
        estimated: Bool = false
    ) -> TravelTime {
        TravelTime(id: id, latitude: 0, longitude: 0, durationSeconds: seconds, distanceMeters: 0, source: .googleRoutes, estimated: estimated, travelMode: mode)
    }

    @Test("Within-2h share is weighted by guest count, not cluster count")
    func withinTwoHoursIsGuestWeighted() {
        // 10 guests at 30 minutes, 1 guest at 3 hours — the lone far cluster
        // must not drag the share down to 50%.
        let readout = TravelImpactCalculator.readout(
            clusters: [cluster("near", count: 10), cluster("far", count: 1)],
            totalGuestCount: 11,
            travelTimes: [travelTime("near", seconds: 1800), travelTime("far", seconds: 10800)]
        )
        #expect(readout.withinTwoHoursFraction == 10.0 / 11.0)
        #expect(readout.uncountedGuestCount == 0)
    }

    @Test("Median is the guest-weighted midpoint, not the cluster midpoint")
    func medianIsGuestWeighted() {
        // Three clusters of equal cluster-count but wildly different guest
        // counts: the median must land in the big cluster's duration, not
        // the middle cluster's.
        let readout = TravelImpactCalculator.readout(
            clusters: [cluster("a", count: 1), cluster("b", count: 100), cluster("c", count: 1)],
            totalGuestCount: 102,
            travelTimes: [
                travelTime("a", seconds: 600),
                travelTime("b", seconds: 3600),
                travelTime("c", seconds: 36000),
            ]
        )
        #expect(readout.medianDurationSeconds == 3600)
    }

    @Test("Fly count only sums clusters resolved as flights")
    func flyCountSumsFlightClustersOnly() {
        let readout = TravelImpactCalculator.readout(
            clusters: [cluster("drive", count: 5), cluster("fly", count: 3)],
            totalGuestCount: 8,
            travelTimes: [
                travelTime("drive", seconds: 1200, mode: .drive),
                travelTime("fly", seconds: 14400, mode: .flight),
            ]
        )
        #expect(readout.flyingGuestCount == 3)
    }

    @Test("Any estimated contributor marks the whole readout estimated")
    func anyEstimatedMarksTheWholeReadout() {
        let readout = TravelImpactCalculator.readout(
            clusters: [cluster("a", count: 5), cluster("b", count: 5)],
            totalGuestCount: 10,
            travelTimes: [
                travelTime("a", seconds: 1200, estimated: false),
                travelTime("b", seconds: 1800, estimated: true),
            ]
        )
        #expect(readout.isEstimated)
    }

    @Test("Guests whose cluster has no result are uncounted, not silently dropped")
    func unresolvedClustersAreUncounted() {
        let readout = TravelImpactCalculator.readout(
            clusters: [cluster("resolved", count: 6), cluster("missing", count: 4)],
            totalGuestCount: 10,
            travelTimes: [travelTime("resolved", seconds: 1800)]
        )
        #expect(readout.uncountedGuestCount == 4)
        #expect(readout.withinTwoHoursFraction == 1.0)
    }

    @Test("Guests outside any resolved cluster at all still count as uncounted")
    func guestsWithNoClusterAtAllAreUncounted() {
        // totalGuestCount exceeds the sum of every cluster's own count —
        // guests who never resolved to city precision in the first place.
        let readout = TravelImpactCalculator.readout(
            clusters: [cluster("only", count: 6)],
            totalGuestCount: 20,
            travelTimes: [travelTime("only", seconds: 1800)]
        )
        #expect(readout.uncountedGuestCount == 14)
    }

    @Test("No clusters at all still computes without dividing by zero")
    func noClustersComputesSafely() {
        let readout = TravelImpactCalculator.readout(clusters: [], totalGuestCount: 5, travelTimes: [])
        #expect(readout.withinTwoHoursFraction == 0)
        #expect(readout.medianDurationSeconds == 0)
        #expect(readout.uncountedGuestCount == 5)
    }

    @Test("Summary text omits the fly fact when nobody flies")
    func summaryOmitsFlyWhenZero() {
        let readout = TravelImpactCalculator.readout(
            clusters: [cluster("a", count: 4)],
            totalGuestCount: 4,
            travelTimes: [travelTime("a", seconds: 3660)]
        )
        #expect(readout.summaryText == "100% of guests within 2h · 1h 1m median")
        #expect(!readout.summaryText.contains("fly"))
    }

    @Test("Summary text includes the fly fact when someone flies")
    func summaryIncludesFlyWhenPresent() {
        let readout = TravelImpactCalculator.readout(
            clusters: [cluster("drive", count: 6), cluster("fly", count: 4)],
            totalGuestCount: 10,
            travelTimes: [
                travelTime("drive", seconds: 3600),
                travelTime("fly", seconds: 14400, mode: .flight),
            ]
        )
        #expect(readout.summaryText.contains("4 fly"))
    }

    @Test("Summary text switches to the short form when some guests are uncounted")
    func summaryUsesShortFormWhenUncounted() {
        let readout = TravelImpactCalculator.readout(
            clusters: [cluster("a", count: 6)],
            totalGuestCount: 8,
            travelTimes: [travelTime("a", seconds: 1800)]
        )
        #expect(readout.summaryText == "100% within 2h · 2 guests not counted")
    }

    @Test("Duration formatter renders hours, minutes, and combined forms")
    func durationFormatting() {
        #expect(TravelDurationFormatter.string(fromSeconds: 45 * 60) == "45m")
        #expect(TravelDurationFormatter.string(fromSeconds: 60 * 60) == "1h")
        #expect(TravelDurationFormatter.string(fromSeconds: 110 * 60) == "1h 50m")
    }
}
