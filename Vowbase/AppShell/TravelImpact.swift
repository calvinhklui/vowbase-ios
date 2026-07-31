import Foundation

/// The console header's second line when a venue is selected — spec §8.
/// Distinct from a plain `String?` because each case routes a tap
/// differently and `.ready` still needs to render even when some guests
/// weren't counted.
enum TravelImpactState: Equatable {
    /// No venue selected. The header falls back to the lens summary.
    case idle
    case loading
    case unavailable(TravelUnavailableReason)
    case ready(TravelReadout)
}

/// The four ways the readout can fail to compute — spec §8.1. Never shown as
/// a dead "Unavailable"; each names the fix and where the tap goes.
enum TravelUnavailableReason: Equatable {
    case venueMissingCoordinate
    case noMappableGuests
    case requestFailed
}

/// A computed guest-travel summary for one selected venue.
///
/// `uncountedGuestCount > 0` doesn't make this a failure — it's the "some
/// guests unlocated" row from spec §8.1, folded into `.ready` rather than
/// treated as a fourth kind of unavailable, since a real number is still
/// being shown for the guests that were counted.
struct TravelReadout: Equatable {
    /// Guest-weighted, not cluster-weighted — a cluster of 40 counts 40 times
    /// what a cluster of 1 does.
    let withinTwoHoursFraction: Double
    let flyingGuestCount: Int
    let medianDurationSeconds: Int
    let isEstimated: Bool
    let uncountedGuestCount: Int
    let durationsByClusterID: [String: TravelTime]

    /// The console header's second line, matching spec §8's two worked
    /// examples exactly. "N fly" is omitted when nobody flies — a "0 fly"
    /// fact adds nothing spec's own guest-subtitle resolver already treats
    /// absence as silence, not as a noisy zero elsewhere in this document.
    var summaryText: String {
        let percent = Int((withinTwoHoursFraction * 100).rounded())
        if uncountedGuestCount > 0 {
            let guestWord = uncountedGuestCount == 1 ? "guest" : "guests"
            return "\(percent)% within 2h · \(uncountedGuestCount) \(guestWord) not counted"
        }
        var text = "\(percent)% of guests within 2h"
        if flyingGuestCount > 0 {
            text += " · \(flyingGuestCount) fly"
        }
        text += " · \(TravelDurationFormatter.string(fromSeconds: medianDurationSeconds)) median"
        return text
    }
}

enum TravelDurationFormatter {
    static func string(fromSeconds seconds: Int) -> String {
        let totalMinutes = max(0, seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }
}

/// Turns a raw `travelTimes` response into the readout the console header
/// and the canvas's cluster badges both read from. Pure and synchronous —
/// the network call happens in `VowbaseWorkspaceStore`; this just does the
/// arithmetic, which is what makes it worth testing on its own.
enum TravelImpactCalculator {
    static func readout(
        clusters: [GuestCluster],
        totalGuestCount: Int,
        travelTimes: [TravelTime]
    ) -> TravelReadout {
        let travelTimesByClusterID = Dictionary(uniqueKeysWithValues: travelTimes.map { ($0.id, $0) })

        var withinTwoHoursGuestCount = 0
        var flyingGuestCount = 0
        var countedGuestCount = 0
        var isEstimated = false
        var durationsWeightedByGuestCount: [(duration: Int, guestCount: Int)] = []

        for cluster in clusters {
            guard let travelTime = travelTimesByClusterID[cluster.id] else { continue }
            countedGuestCount += cluster.count
            durationsWeightedByGuestCount.append((travelTime.durationSeconds, cluster.count))
            if travelTime.durationSeconds <= 7200 {
                withinTwoHoursGuestCount += cluster.count
            }
            if travelTime.travelMode == .flight {
                flyingGuestCount += cluster.count
            }
            if travelTime.estimated {
                isEstimated = true
            }
        }

        let uncountedGuestCount = max(0, totalGuestCount - countedGuestCount)
        let withinTwoHoursFraction = countedGuestCount > 0
            ? Double(withinTwoHoursGuestCount) / Double(countedGuestCount)
            : 0

        return TravelReadout(
            withinTwoHoursFraction: withinTwoHoursFraction,
            flyingGuestCount: flyingGuestCount,
            medianDurationSeconds: weightedMedian(durationsWeightedByGuestCount) ?? 0,
            isEstimated: isEstimated,
            uncountedGuestCount: uncountedGuestCount,
            durationsByClusterID: travelTimesByClusterID
        )
    }

    /// The duration at the 50th percentile of cumulative guest weight, not
    /// the 50th percentile of clusters — a cluster's duration counts once
    /// per guest it represents.
    private static func weightedMedian(_ entries: [(duration: Int, guestCount: Int)]) -> Int? {
        let totalWeight = entries.reduce(0) { $0 + $1.guestCount }
        guard totalWeight > 0 else { return nil }

        let sorted = entries.sorted { $0.duration < $1.duration }
        let halfway = Double(totalWeight) / 2.0
        var cumulative = 0
        for entry in sorted {
            cumulative += entry.guestCount
            if Double(cumulative) >= halfway {
                return entry.duration
            }
        }
        return sorted.last?.duration
    }
}
