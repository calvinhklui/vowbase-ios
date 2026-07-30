import Foundation
import Testing
@testable import Vowbase

@Suite("Guest inline editing: patches, custom fields, and display resolution")
struct GuestFieldEditingTests {
    private let weddingID = UUID(uuidString: "79B779C0-7E5B-4F9D-94F3-00C13DCEE5B4")!
    private let guestID = UUID(uuidString: "AE67A07D-D565-4A7D-A960-4B6A186C4D6D")!

    private func column(
        _ key: String,
        label: String,
        kind: GuestCustomColumnKind,
        options: [String] = [],
        position: Int = 0,
        hidden: Bool = false
    ) -> GuestCustomColumn {
        GuestCustomColumn(
            id: UUID(),
            weddingID: weddingID,
            key: key,
            label: label,
            kind: kind,
            options: .array(options.map(JSONValue.string)),
            position: position,
            hidden: hidden,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
    }

    private func guest(customFields: JSONValue = .object([:])) -> Guest {
        Guest(
            id: guestID,
            weddingID: weddingID,
            firstName: "Avery",
            lastName: "Rowan",
            email: nil,
            phone: nil,
            address: nil,
            customFields: customFields,
            rsvpStatus: .pending,
            rsvpDate: nil,
            originLabel: nil,
            originLatitude: nil,
            originLongitude: nil,
            originPrecision: nil,
            geocodeStatus: nil,
            createdAt: .distantPast
        )
    }

    private func encodedPatch(_ patch: GuestPatch) throws -> [String: Any] {
        let data = try JSONEncoder().encode(patch)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Single-field patches

    @Test("A patch carries only the field being edited")
    func patchCarriesOneField() throws {
        let body = try encodedPatch(#require(GuestEditableField.email.patch(newValue: "a@example.com")))
        #expect(body.keys.sorted() == ["email"])
        #expect(body["email"] as? String == "a@example.com")
    }

    @Test("Clearing an optional field sends null, not an empty string")
    func clearingSendsNull() throws {
        let body = try encodedPatch(#require(GuestEditableField.phone.patch(newValue: "   ")))
        #expect(body.keys.sorted() == ["phone"])
        #expect(body["phone"] is NSNull)
    }

    @Test("Values are trimmed before they are sent")
    func valuesAreTrimmed() throws {
        let body = try encodedPatch(#require(GuestEditableField.lastName.patch(newValue: "  Rowan  ")))
        #expect(body["last_name"] as? String == "Rowan")
    }

    @Test("An empty required field produces no patch at all")
    func emptyRequiredFieldIsRejected() {
        #expect(GuestEditableField.firstName.patch(newValue: "") == nil)
        #expect(GuestEditableField.firstName.patch(newValue: "   ") == nil)
        #expect(GuestEditableField.firstName.patch(newValue: "Avery") != nil)
    }

    // MARK: - Custom field merging

    @Test("Merging preserves the keys it is not editing")
    func mergingPreservesSiblings() {
        let existing = JSONValue.object([
            "group": .string("Cedar Circle"),
            "table": .number(4)
        ])
        let merged = GuestCustomFields.merging(existing, key: "meal_choice", value: .string("Vegan"))

        #expect(GuestCustomFields.value(in: merged, for: "group") == .string("Cedar Circle"))
        #expect(GuestCustomFields.value(in: merged, for: "table") == .number(4))
        #expect(GuestCustomFields.value(in: merged, for: "meal_choice") == .string("Vegan"))
    }

    /// The lost-update case the whole write queue exists to prevent: two edits
    /// to different keys must both survive when each merges against the result
    /// of the one before it.
    @Test("Sequential merges against the latest object keep both edits")
    func sequentialMergesKeepBothEdits() {
        let base = JSONValue.object(["group": .string("Cedar Circle")])
        let first = GuestCustomFields.merging(base, key: "meal_choice", value: .string("Vegan"))
        let second = GuestCustomFields.merging(first, key: "table", value: .number(6))

        #expect(GuestCustomFields.value(in: second, for: "meal_choice") == .string("Vegan"))
        #expect(GuestCustomFields.value(in: second, for: "table") == .number(6))
        #expect(GuestCustomFields.value(in: second, for: "group") == .string("Cedar Circle"))
    }

    /// Merging against a stale base is exactly what the queue must avoid, and
    /// this pins the failure mode so a regression is legible.
    @Test("Merging against a stale base drops the concurrent edit")
    func staleBaseDropsConcurrentEdit() {
        let base = JSONValue.object(["group": .string("Cedar Circle")])
        let withMeal = GuestCustomFields.merging(base, key: "meal_choice", value: .string("Vegan"))
        let fromStaleBase = GuestCustomFields.merging(base, key: "table", value: .number(6))

        #expect(GuestCustomFields.value(in: withMeal, for: "meal_choice") == .string("Vegan"))
        #expect(GuestCustomFields.value(in: fromStaleBase, for: "meal_choice") == nil)
    }

    @Test("Clearing removes the key rather than storing null")
    func clearingRemovesKey() {
        let existing = JSONValue.object(["meal_choice": .string("Vegan"), "group": .string("Cedar Circle")])
        let merged = GuestCustomFields.merging(existing, key: "meal_choice", value: nil)

        #expect(GuestCustomFields.object(in: merged).keys.sorted() == ["group"])
    }

    @Test("A stored null reads as no value")
    func storedNullReadsAsAbsent() {
        let container = JSONValue.object(["group": .null])
        #expect(GuestCustomFields.value(in: container, for: "group") == nil)
    }

    // MARK: - Encoding and display

    @Test("Numbers round-trip without a trailing decimal")
    func numberDisplayIsClean() {
        #expect(GuestCustomFields.displayText(.number(4), kind: .number) == "4")
        #expect(GuestCustomFields.displayText(.number(4.5), kind: .number) == "4.5")
    }

    @Test("Non-numeric text does not encode into a number column")
    func nonNumericTextIsRejected() {
        #expect(GuestCustomFields.encode("twelve", kind: .number) == nil)
        #expect(GuestCustomFields.encode("12", kind: .number) == .number(12))
    }

    @Test("Blank input clears any column kind")
    func blankInputClears() {
        for kind in [GuestCustomColumnKind.text, .number, .select] {
            #expect(GuestCustomFields.encode("   ", kind: kind) == nil)
        }
    }

    @Test("A value whose type contradicts its column is flagged, not coerced")
    func mismatchedValueIsFlagged() {
        #expect(GuestCustomFields.isUnsupported(.array([.string("a")]), kind: .text))
        #expect(GuestCustomFields.isUnsupported(.bool(true), kind: .select))
        #expect(!GuestCustomFields.isUnsupported(.string("Vegan"), kind: .select))
        #expect(!GuestCustomFields.isUnsupported(nil, kind: .text))
    }

    @Test("Select options tolerate a malformed definition")
    func optionsTolerateBadData() {
        let good = column("meal", label: "Meal", kind: .select, options: ["Fish", "Vegan"])
        #expect(GuestCustomFields.options(in: good) == ["Fish", "Vegan"])

        let malformed = GuestCustomColumn(
            id: UUID(), weddingID: weddingID, key: "meal", label: "Meal", kind: .select,
            options: .object(["nope": .string("x")]), position: 0, hidden: false,
            createdAt: .distantPast, updatedAt: .distantPast
        )
        #expect(GuestCustomFields.options(in: malformed).isEmpty)
    }

    // MARK: - Display resolution

    @Test("Columns order by position, and hidden ones are excluded")
    func orderingAndVisibility() {
        let columns = [
            column("c", label: "C", kind: .text, position: 2),
            column("a", label: "A", kind: .text, position: 0),
            column("b", label: "B", kind: .text, position: 1, hidden: true)
        ]
        #expect(GuestDisplayResolver.orderedColumns(columns).map(\.key) == ["a", "b", "c"])
        #expect(GuestDisplayResolver.visibleColumns(columns).map(\.key) == ["a", "c"])
    }

    @Test("The subtitle column prefers the first select, then the first text")
    func subtitleColumnPreference() {
        let withSelect = [
            column("note", label: "Note", kind: .text, position: 0),
            column("side", label: "Side", kind: .select, options: ["Bride"], position: 1)
        ]
        #expect(GuestDisplayResolver.subtitleColumn(in: withSelect)?.key == "side")

        let textOnly = [column("note", label: "Note", kind: .text, position: 0)]
        #expect(GuestDisplayResolver.subtitleColumn(in: textOnly)?.key == "note")

        #expect(GuestDisplayResolver.subtitleColumn(in: []) == nil)
    }

    /// The resolver must not key off a literal column name — a wedding that
    /// calls its grouping column `side` has to work with no code change.
    @Test("The subtitle resolves from definitions, not a hard-coded key")
    func subtitleIgnoresLiteralKeyNames() {
        let columns = [column("side", label: "Side", kind: .select, options: ["Bride", "Groom"])]
        let record = guest(customFields: .object(["side": .string("Bride")]))
        #expect(GuestDisplayResolver.subtitle(for: record, columns: columns) == "Bride")
    }

    @Test("A guest with no value for the subtitle column shows nothing")
    func absentSubtitleIsNil() {
        let columns = [column("side", label: "Side", kind: .select, options: ["Bride"])]
        #expect(GuestDisplayResolver.subtitle(for: guest(), columns: columns) == nil)
        #expect(GuestDisplayResolver.subtitle(for: guest(), columns: []) == nil)
    }

    @Test("A hidden column never becomes the subtitle")
    func hiddenColumnIsNotSubtitle() {
        let columns = [column("side", label: "Side", kind: .select, options: ["Bride"], hidden: true)]
        let record = guest(customFields: .object(["side": .string("Bride")]))
        #expect(GuestDisplayResolver.subtitle(for: record, columns: columns) == nil)
    }

    // MARK: - Save state

    @Test("A failed save carries the value the user typed")
    func failedStateKeepsTypedValue() {
        let state = GuestFieldSaveState.failed(pendingValue: "typed@example.com")
        #expect(state != .saved)
        guard case let .failed(pending) = state else {
            Issue.record("expected a failed state")
            return
        }
        #expect(pending == "typed@example.com")
    }

    @Test("Field keys namespace custom fields away from built-ins")
    func fieldKeysAreDistinct() {
        let builtIn = GuestFieldKey(guestID: guestID, field: .email)
        let custom = GuestFieldKey.customField(guestID: guestID, key: "email")
        #expect(builtIn != custom)

        let otherGuest = GuestFieldKey(guestID: UUID(), field: .email)
        #expect(builtIn != otherGuest)
    }
}
