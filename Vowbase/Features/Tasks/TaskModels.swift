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
    /// Server-authored completion timestamp. A done status alone is not
    /// enough to create a historical Timeline entry, because older records
    /// may not have a reliable completion date.
    let completedAt: Date?
    let createdAt: Date

    var effectiveStatus: WeddingTaskStatus { status ?? .todo }

    init(
        id: UUID,
        weddingID: UUID,
        title: String,
        description: String?,
        status: WeddingTaskStatus?,
        priority: WeddingTaskPriority?,
        ownerUserID: UUID?,
        ownerLabel: String?,
        dueDate: String?,
        completedAt: Date? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.weddingID = weddingID
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.ownerUserID = ownerUserID
        self.ownerLabel = ownerLabel
        self.dueDate = dueDate
        self.completedAt = completedAt
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case weddingID = "wedding_id"
        case title, description, status, priority
        case ownerUserID = "owner_user_id"
        case ownerLabel = "owner_label"
        case dueDate = "due_date"
        case completedAt = "completed_at"
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

    init(
        title: String,
        description: String? = nil,
        status: WeddingTaskStatus? = .todo,
        priority: WeddingTaskPriority? = .medium,
        ownerUserID: UUID? = nil,
        ownerLabel: String? = nil,
        dueDate: String? = nil
    ) {
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.ownerUserID = ownerUserID
        self.ownerLabel = ownerLabel
        self.dueDate = dueDate
    }

    enum CodingKeys: String, CodingKey {
        case title, description, status, priority
        case ownerUserID = "owner_user_id"
        case ownerLabel = "owner_label"
        case dueDate = "due_date"
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

    init(
        title: String? = nil,
        description: NullablePatch<String> = .unchanged,
        status: NullablePatch<WeddingTaskStatus> = .unchanged,
        priority: NullablePatch<WeddingTaskPriority> = .unchanged,
        ownerUserID: NullablePatch<UUID> = .unchanged,
        ownerLabel: NullablePatch<String> = .unchanged,
        dueDate: NullablePatch<String> = .unchanged
    ) {
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.ownerUserID = ownerUserID
        self.ownerLabel = ownerLabel
        self.dueDate = dueDate
    }

    var isEmpty: Bool {
        title == nil && description == .unchanged && status == .unchanged &&
        priority == .unchanged && ownerUserID == .unchanged && ownerLabel == .unchanged &&
        dueDate == .unchanged
    }

    enum CodingKeys: String, CodingKey {
        case title, description, status, priority
        case ownerUserID = "owner_user_id"
        case ownerLabel = "owner_label"
        case dueDate = "due_date"
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
