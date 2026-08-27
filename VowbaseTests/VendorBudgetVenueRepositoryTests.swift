import Foundation
import Testing
@testable import Vowbase
@Suite("Vendor budget and venue domain contracts") struct VendorBudgetVenueRepositoryTests {
    @Test("venue photo metadata carries wedding and venue identity") func venuePhotoShape() throws {
        let photo = try DatabaseDecoding.decoder.decode(VenuePhoto.self, from: Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"venue_id\":\"00000000-0000-0000-0000-000000000002\",\"wedding_id\":\"00000000-0000-0000-0000-000000000003\",\"url\":\"https://example.invalid/photo\",\"created_at\":\"2026-07-01T00:00:00Z\"}".utf8))
        #expect(photo.sortOrder == nil)
    }

    @Test("venue notes patch sets, clears, and omits notes correctly") func venueNotesPatchEncoding() throws {
        let encoder = JSONEncoder()

        let set = try JSONSerialization.jsonObject(with: encoder.encode(VenuePatch(ourNotes: .value("Ask about the rain plan.")))) as! [String: Any]
        #expect(set["our_notes"] as? String == "Ask about the rain plan.")

        let clear = try JSONSerialization.jsonObject(with: encoder.encode(VenuePatch(ourNotes: .null))) as! [String: Any]
        #expect(clear["our_notes"] is NSNull)

        let unchanged = try JSONSerialization.jsonObject(with: encoder.encode(VenuePatch(name: "Riverside Pavilion"))) as! [String: Any]
        #expect(unchanged["our_notes"] == nil)
    }

    @Test("venue writes use the canonical address fields") func venueAddressPatchEncoding() throws {
        let encoded = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(VenuePatch(address: .value("1 Apple Park Way"), city: .value("Cupertino")))
        ) as! [String: Any]
        #expect(encoded["address"] as? String == "1 Apple Park Way")
        #expect(encoded["city"] as? String == "Cupertino")
    }

    @Test("venue address updates replace coordinate pairs atomically and manual text clears them") func venueCoordinateInvalidation() throws {
        let encoder = JSONEncoder()
        let selected = try JSONSerialization.jsonObject(with: encoder.encode(VenuePatch(
            address: .value("1 Apple Park Way, Cupertino, CA 95014, United States"),
            city: .value("Cupertino"), state: .value("CA"), country: .value("United States"),
            latitude: .value(37.3349), longitude: .value(-122.0090)
        ))) as! [String: Any]
        #expect(selected["latitude"] as? Double == 37.3349)
        #expect(selected["longitude"] as? Double == -122.0090)

        let manual = try JSONSerialization.jsonObject(with: encoder.encode(VenuePatch(
            address: .value("Manually entered venue"), city: .null, state: .null, country: .null,
            latitude: .null, longitude: .null
        ))) as! [String: Any]
        #expect(manual["latitude"] is NSNull)
        #expect(manual["longitude"] is NSNull)
    }
}
