import Foundation

enum WeddingTaskStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case backlog
    case todo
    case inProgress = "in_progress"
    case blocked
    case done

    var title: String {
        switch self {
        case .backlog: "Backlog"
        case .todo: "To Do"
        case .inProgress: "In Progress"
        case .blocked: "Blocked"
        case .done: "Done"
        }
    }

    var systemImage: String {
        switch self {
        case .backlog: "tray"
        case .todo: "circle"
        case .inProgress: "arrow.triangle.2.circlepath"
        case .blocked: "exclamationmark.octagon"
        case .done: "checkmark.circle.fill"
        }
    }
}

enum WeddingTaskPriority: String, Codable, CaseIterable, Equatable, Sendable {
    case low, medium, high, urgent

    var title: String { rawValue.capitalized }
}

struct WeddingTask: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let weddingID: UUID
    let title: String
    let description: String?
    let status: WeddingTaskStatus?
    let priority: WeddingTaskPriority?
    let ownerUserID: UUID?
    let ownerLabel: String?
    let dueDate: String?
    let relatedVendorID: UUID?
    let relatedEventID: UUID?
    let createdAt: Date

    var effectiveStatus: WeddingTaskStatus { status ?? .todo }

    enum CodingKeys: String, CodingKey {
        case id
        case weddingID = "wedding_id"
        case title, description, status, priority
        case ownerUserID = "owner_user_id"
        case ownerLabel = "owner_label"
        case dueDate = "due_date"
        case relatedVendorID = "related_vendor_id"
        case relatedEventID = "related_event_id"
        case createdAt = "created_at"
    }
}

struct TaskDraft: Codable, Equatable, Sendable {
    let title: String
    let description: String?
    let status: WeddingTaskStatus?
    let priority: WeddingTaskPriority?
    let ownerUserID: UUID?
    let ownerLabel: String?
    let dueDate: String?
    let relatedVendorID: UUID?
    let relatedEventID: UUID?

    init(
        title: String,
        description: String? = nil,
        status: WeddingTaskStatus? = .todo,
        priority: WeddingTaskPriority? = .medium,
        ownerUserID: UUID? = nil,
        ownerLabel: String? = nil,
        dueDate: String? = nil,
        relatedVendorID: UUID? = nil,
        relatedEventID: UUID? = nil
    ) {
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.ownerUserID = ownerUserID
        self.ownerLabel = ownerLabel
        self.dueDate = dueDate
        self.relatedVendorID = relatedVendorID
        self.relatedEventID = relatedEventID
    }

    enum CodingKeys: String, CodingKey {
        case title, description, status, priority
        case ownerUserID = "owner_user_id"
        case ownerLabel = "owner_label"
        case dueDate = "due_date"
        case relatedVendorID = "related_vendor_id"
        case relatedEventID = "related_event_id"
    }
}

struct TaskPatch: Encodable, Equatable, Sendable {
    let title: String?
    let description: NullablePatch<String>
    let status: NullablePatch<WeddingTaskStatus>
    let priority: NullablePatch<WeddingTaskPriority>
    let ownerUserID: NullablePatch<UUID>
    let ownerLabel: NullablePatch<String>
    let dueDate: NullablePatch<String>
    let relatedVendorID: NullablePatch<UUID>
    let relatedEventID: NullablePatch<UUID>

    init(
        title: String? = nil,
        description: NullablePatch<String> = .unchanged,
        status: NullablePatch<WeddingTaskStatus> = .unchanged,
        priority: NullablePatch<WeddingTaskPriority> = .unchanged,
        ownerUserID: NullablePatch<UUID> = .unchanged,
        ownerLabel: NullablePatch<String> = .unchanged,
        dueDate: NullablePatch<String> = .unchanged,
        relatedVendorID: NullablePatch<UUID> = .unchanged,
        relatedEventID: NullablePatch<UUID> = .unchanged
    ) {
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.ownerUserID = ownerUserID
        self.ownerLabel = ownerLabel
        self.dueDate = dueDate
        self.relatedVendorID = relatedVendorID
        self.relatedEventID = relatedEventID
    }

    var isEmpty: Bool {
        title == nil && description == .unchanged && status == .unchanged &&
        priority == .unchanged && ownerUserID == .unchanged && ownerLabel == .unchanged &&
        dueDate == .unchanged && relatedVendorID == .unchanged && relatedEventID == .unchanged
    }

    enum CodingKeys: String, CodingKey {
        case title, description, status, priority
        case ownerUserID = "owner_user_id"
        case ownerLabel = "owner_label"
        case dueDate = "due_date"
        case relatedVendorID = "related_vendor_id"
        case relatedEventID = "related_event_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(status, forKey: .status)
        try container.encode(priority, forKey: .priority)
        try container.encode(ownerUserID, forKey: .ownerUserID)
        try container.encode(ownerLabel, forKey: .ownerLabel)
        try container.encode(dueDate, forKey: .dueDate)
        try container.encode(relatedVendorID, forKey: .relatedVendorID)
        try container.encode(relatedEventID, forKey: .relatedEventID)
    }
}

private extension KeyedEncodingContainer where Key == TaskPatch.CodingKeys {
    mutating func encode<Value: Encodable & Equatable & Sendable>(
        _ patch: NullablePatch<Value>,
        forKey key: Key
    ) throws {
        switch patch {
        case .unchanged:
            break
        case .value(let value):
            try encode(value, forKey: key)
        case .null:
            try encodeNil(forKey: key)
        }
    }
}
