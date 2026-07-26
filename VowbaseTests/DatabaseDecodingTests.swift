import Foundation
import Testing
@testable import Vowbase

@Suite("Database decoding")
struct DatabaseDecodingTests {
    @Test("decodes the workspace membership fixture exactly")
    func decodesWorkspaceMembershipFixtureExactly() throws {
        let bundle = Bundle(for: DatabaseDecodingTestsBundleToken.self)
        let fixtureURL = try #require(
            bundle.url(
                forResource: "workspace-membership",
                withExtension: "json",
                subdirectory: "Fixtures"
            ) ?? bundle.url(
                forResource: "workspace-membership",
                withExtension: "json"
            )
        )

        let membership = try DatabaseDecoding.decoder.decode(
            FixtureMembership.self,
            from: Data(contentsOf: fixtureURL)
        )

        requireSendable(membership)
        #expect(membership.id == UUID(uuidString: "01908f9d-2265-789a-bcde-f0123456789a"))
        #expect(membership.weddingId == UUID(uuidString: "01908f9d-2265-789a-bcde-f0123456789b"))
        #expect(membership.userId == UUID(uuidString: "01908f9d-2265-789a-bcde-f0123456789c"))
        #expect(membership.role == .partner)
        #expect(membership.status == "active")
        #expect(membership.createdAt.timeIntervalSince1970 == 1_784_989_425.678)
        #expect(
            membership.wedding == FixtureWedding(
                id: UUID(uuidString: "01908f9d-2265-789a-bcde-f0123456789b")!,
                name: "Alex & Calvin",
                coupleNames: "Alex and Calvin",
                weddingDate: "2027-06-12",
                location: "Brooklyn, NY"
            )
        )
    }

    @Test("decodes timestamps with and without fractional seconds")
    func decodesFractionalAndNonfractionalTimestamps() throws {
        struct Timestamp: Decodable {
            let createdAt: Date
        }

        let fractional = try DatabaseDecoding.decoder.decode(
            Timestamp.self,
            from: Data(#"{"created_at":"2026-07-25T14:23:45.678Z"}"#.utf8)
        )
        let nonfractional = try DatabaseDecoding.decoder.decode(
            Timestamp.self,
            from: Data(#"{"created_at":"2026-07-25T14:23:45Z"}"#.utf8)
        )

        #expect(fractional.createdAt.timeIntervalSince1970 == 1_784_989_425.678)
        #expect(nonfractional.createdAt.timeIntervalSince1970 == 1_784_989_425)
    }

    @Test("provides an independently configured decoder on every access")
    func providesIndependentDecoderInstances() {
        let first = DatabaseDecoding.decoder
        let second = DatabaseDecoding.decoder

        #expect(first !== second)
    }

    @Test("round-trips JSON objects and arrays without confusing booleans and numbers")
    func roundTripsJSONObjectsAndArrays() throws {
        let value: JSONValue = .object([
            "name": .string("Vowbase"),
            "enabled": .bool(true),
            "count": .number(1),
            "items": .array([
                .bool(false),
                .number(0),
                .number(1.5),
                .null,
                .object(["nested": .string("value")]),
            ]),
        ])

        requireSendable(value)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)

        #expect(decoded == value)
        #expect(
            try JSONDecoder().decode(
                JSONValue.self,
                from: Data("[true,1,false,0,1.5,null]".utf8)
            ) == .array([
                .bool(true),
                .number(1),
                .bool(false),
                .number(0),
                .number(1.5),
                .null,
            ])
        )
    }

    private func requireSendable<T: Sendable>(_: T) {}
}

private enum FixtureWeddingRole: String, Codable, Sendable {
    case owner
    case partner
    case planner
    case parent
    case viewer
}

private struct FixtureWedding: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let coupleNames: String?
    let weddingDate: String?
    let location: String?
}

private struct FixtureMembership: Codable, Equatable, Sendable {
    let id: UUID
    let weddingId: UUID
    let userId: UUID
    let role: FixtureWeddingRole
    let status: String
    let createdAt: Date
    let wedding: FixtureWedding
}

private final class DatabaseDecodingTestsBundleToken {}
