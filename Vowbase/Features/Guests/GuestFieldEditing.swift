import Foundation

/// Identifies one editable row so its save state is tracked independently.
///
/// Inline editing commits a single field at a time, and a failure on one row
/// must never imply anything about its neighbours.
struct GuestFieldKey: Hashable, Sendable {
    let guestID: UUID
    let field: String

    init(guestID: UUID, field: String) {
        self.guestID = guestID
        self.field = field
    }

    init(guestID: UUID, field: GuestEditableField) {
        self.init(guestID: guestID, field: field.rawValue)
    }

    /// Custom fields share the guest's `custom_fields` column but still save
    /// and fail per row, so they need their own namespaced keys.
    static func customField(guestID: UUID, key: String) -> GuestFieldKey {
        GuestFieldKey(guestID: guestID, field: "custom:\(key)")
    }
}

enum GuestFieldSaveState: Equatable, Sendable {
    case saving
    case saved
    /// Carries the value the user typed. A failed write keeps their input on
    /// screen rather than reverting to the stored value.
    case failed(pendingValue: String?)
}

/// The guest fields that edit as plain text and patch one at a time.
///
/// `address` is deliberately absent: it commits in two stages because saving it
/// also re-derives the map origin, so the store owns that flow.
enum GuestEditableField: String, CaseIterable, Sendable {
    case firstName
    case lastName
    case email
    case phone

    var label: String {
        switch self {
        case .firstName: "First name"
        case .lastName: "Last name"
        case .email: "Email"
        case .phone: "Phone"
        }
    }

    /// Only the first name is required; everything else can be cleared to null.
    var isRequired: Bool { self == .firstName }

    func currentValue(in guest: Guest) -> String? {
        switch self {
        case .firstName: guest.firstName
        case .lastName: guest.lastName
        case .email: guest.email
        case .phone: guest.phone
        }
    }

    /// Builds a patch carrying exactly this field.
    ///
    /// Returns `nil` when the input is not committable, which today means an
    /// empty required field. Clearing an optional field sends an explicit null
    /// rather than an empty string.
    func patch(newValue: String) -> GuestPatch? {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String? = trimmed.isEmpty ? nil : trimmed

        switch self {
        case .firstName:
            guard let value else { return nil }
            return GuestPatch(firstName: value)
        case .lastName:
            return GuestPatch(lastName: value.map(NullablePatch.value) ?? .null)
        case .email:
            return GuestPatch(email: value.map(NullablePatch.value) ?? .null)
        case .phone:
            return GuestPatch(phone: value.map(NullablePatch.value) ?? .null)
        }
    }
}

/// Reading and writing values inside the guest's `custom_fields` JSON object.
///
/// `GuestPatch.customFields` replaces the whole object, so every write is a
/// merge against a base rather than a targeted update.
enum GuestCustomFields {
    static func object(in value: JSONValue) -> [String: JSONValue] {
        guard case let .object(fields) = value else { return [:] }
        return fields
    }

    static func value(in container: JSONValue, for key: String) -> JSONValue? {
        guard let stored = object(in: container)[key], stored != .null else { return nil }
        return stored
    }

    /// Returns `container` with `key` set to `newValue`, or removed when nil.
    ///
    /// The caller must pass the most recently server-confirmed container so
    /// concurrent edits to different keys do not erase one another.
    static func merging(_ container: JSONValue, key: String, value newValue: JSONValue?) -> JSONValue {
        var fields = object(in: container)
        if let newValue {
            fields[key] = newValue
        } else {
            fields.removeValue(forKey: key)
        }
        return .object(fields)
    }

    /// Text shown in a read-state row, or nil when there is nothing stored.
    static func displayText(_ value: JSONValue?, kind: GuestCustomColumnKind) -> String? {
        guard let value else { return nil }
        switch value {
        case let .string(text):
            return text.isEmpty ? nil : text
        case let .number(number):
            return numberText(number)
        case let .bool(flag):
            return flag ? "Yes" : "No"
        case .array, .object, .null:
            // Written by the web app or an import in a shape this row can't edit.
            return nil
        }
    }

    /// True when a stored value exists but does not match its column's kind.
    ///
    /// Those rows render read-only rather than crashing or silently coercing.
    static func isUnsupported(_ value: JSONValue?, kind: GuestCustomColumnKind) -> Bool {
        guard let value else { return false }
        switch (value, kind) {
        case (.string, .text), (.string, .select), (.number, .number), (.bool, .checkbox):
            return false
        // A number stored against a text column still reads fine.
        case (.number, .text), (.string, .number):
            return false
        default:
            return true
        }
    }

    /// Converts typed text into the JSON value for a column, or nil to clear it.
    static func encode(_ text: String, kind: GuestCustomColumnKind) -> JSONValue? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch kind {
        case .text, .select:
            return .string(trimmed)
        case .number:
            guard let number = Double(trimmed) else { return nil }
            return .number(number)
        case .checkbox:
            return .bool(true)
        }
    }

    /// The options a select column offers, tolerating a malformed definition.
    static func options(in column: GuestCustomColumn) -> [String] {
        guard case let .array(values) = column.options else { return [] }
        return values.compactMap { value in
            guard case let .string(text) = value else { return nil }
            return text
        }
    }

    private static func numberText(_ value: Double) -> String {
        value.rounded() == value && value.magnitude < 1e15
            ? String(Int(value))
            : String(value)
    }
}

/// Turns column definitions into stable row metadata.
///
/// The view must never key off a literal column name: a wedding whose grouping
/// column is called `side` or `table` has to work without a code change.
enum GuestDisplayResolver {
    static func orderedColumns(_ columns: [GuestCustomColumn]) -> [GuestCustomColumn] {
        columns.sorted { left, right in
            left.position == right.position
                ? left.label.localizedCaseInsensitiveCompare(right.label) == .orderedAscending
                : left.position < right.position
        }
    }

    static func visibleColumns(_ columns: [GuestCustomColumn]) -> [GuestCustomColumn] {
        orderedColumns(columns).filter { !$0.hidden }
    }

    /// The column whose value appears beneath the guest's name in the list.
    ///
    /// Prefers the first select column, then the first text column. Weddings
    /// with neither simply show no subtitle.
    static func subtitleColumn(in columns: [GuestCustomColumn]) -> GuestCustomColumn? {
        let visible = visibleColumns(columns)
        return visible.first { $0.kind == .select } ?? visible.first { $0.kind == .text }
    }

    /// The row subtitle for a guest, or nil when the wedding defines no
    /// suitable column or this guest has no value for it.
    ///
    /// Returning nil rather than a placeholder matters: a literal "No group" on
    /// every row of a wedding that never defined groups is noise, not data.
    static func subtitle(for guest: Guest, columns: [GuestCustomColumn]) -> String? {
        guard let column = subtitleColumn(in: columns) else { return nil }
        let stored = GuestCustomFields.value(in: guest.customFields, for: column.key)
        return GuestCustomFields.displayText(stored, kind: column.kind)
    }
}
