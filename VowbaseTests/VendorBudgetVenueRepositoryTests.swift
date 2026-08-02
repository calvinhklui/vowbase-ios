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
}
