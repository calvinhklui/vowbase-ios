import Foundation
import Testing
@testable import Vowbase

@Suite("Shared metric configuration")
struct MetricConfigurationTests {
    @Test("Count edits preserve unsupported and web-only tiles")
    func countMergePreservesUnprojectableTiles() {
        let existing = [
            SharedMetricTile(id: "supported-a", type: .count, label: "A", field: "rsvp_status", value: "pending"),
            SharedMetricTile(id: "web-pie", type: .pie, label: "Pie", field: "rsvp_status", value: nil),
            SharedMetricTile(id: "deleted-custom-field", type: .count, label: "Legacy", field: "cf:removed", value: "yes"),
            SharedMetricTile(id: "supported-b", type: .count, label: "B", field: "rsvp_status", value: "accepted"),
            SharedMetricTile(id: "web-bar", type: .bar, label: "Bar", field: "rsvp_status", value: nil),
        ]
        let replacement = [
            SharedMetricTile(id: "supported-b", type: .count, label: "B", field: "rsvp_status", value: "accepted"),
            SharedMetricTile(id: "supported-a", type: .count, label: "A", field: "rsvp_status", value: "pending"),
        ]

        let merged = MetricConfigurationProjection.replacingCountTiles(
            in: existing,
            with: replacement,
            replacingCountTileIDs: ["supported-a", "supported-b"]
        )

        #expect(merged.map(\.id) == ["supported-b", "web-pie", "deleted-custom-field", "supported-a", "web-bar"])
    }

    @Test("Checkbox metrics use web yes and no values")
    func checkboxMetricsSerializeAsYesNo() {
        let tile = MetricConfigurationProjection.tile(from: GuestMetric(
            id: "guest-plus-one",
            name: "Plus one",
            condition: .customCheckbox(key: "plus_one", expected: true),
            isEnabled: true,
            isCustom: true
        ))

        #expect(tile?.field == "cf:plus_one")
        #expect(tile?.value == "yes")
    }

    @Test("New native count metrics are serializable without dropping web charts")
    func newNativeMetricsPreserveWebCharts() throws {
        var configuration = GuestMetricConfiguration.default(columns: [])
        let addedID = configuration.addCustom(
            name: "Has email",
            condition: .email(.present)
        )
        let id = try #require(addedID)
        let metric = try #require(configuration.shownMetrics.first(where: { $0.id == id }))
        let nativeTile = try #require(MetricConfigurationProjection.tile(from: metric))
        let existing = [
            SharedMetricTile(id: "guest-total", type: .count, label: "Total", field: "__total", value: nil),
            SharedMetricTile(id: "web-pie", type: .pie, label: "RSVP", field: "rsvp_status", value: nil),
        ]

        let merged = MetricConfigurationProjection.replacingCountTiles(
            in: existing,
            with: [nativeTile],
            replacingCountTileIDs: ["guest-total"]
        )

        #expect(nativeTile.field == "email")
        #expect(nativeTile.value == "yes")
        #expect(merged.map(\.id) == [nativeTile.id, "web-pie"])
    }

    @Test("Configuration decodes web snake case metadata")
    func configurationDecodesWebMetadata() throws {
        let json = """
        {
          "id":"00000000-0000-0000-0000-000000000001",
          "wedding_id":"00000000-0000-0000-0000-000000000002",
          "user_id":"00000000-0000-0000-0000-000000000003",
          "surface":"guests",
          "tiles":[],
          "schema_version":1,
          "revision":4,
          "updated_by":"00000000-0000-0000-0000-000000000003",
          "updated_at":"2026-08-31T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let configuration = try decoder.decode(SharedMetricConfiguration.self, from: Data(json.utf8))

        #expect(configuration.surface == .guests)
        #expect(configuration.schemaVersion == 1)
        #expect(configuration.revision == 4)
    }
}
