import Foundation
import Observation
import Supabase
import SwiftUI

// MARK: - Domain

enum PlanningMomentType: String, Codable, CaseIterable, Equatable, Sendable, Identifiable {
    case venueTour = "venue_tour"
    case decision
    case meeting
    case payment
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .venueTour: "Venue tour"
        case .decision: "Decision"
        case .meeting: "Meeting"
        case .payment: "Payment"
        case .custom: "Custom moment"
        }
    }

    var systemImage: String {
        switch self {
        case .venueTour: "mappin.and.ellipse"
        case .decision: "checkmark.seal"
        case .meeting: "person.2"
        case .payment: "creditcard"
        case .custom: "sparkles"
        }
    }
}

struct PlanningMoment: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let weddingID: UUID
    let momentType: PlanningMomentType
    let title: String
    let notes: String?
    let occurredAt: Date
    let locationText: String?
    let createdBy: UUID
    let linkedVenueID: UUID?
    let followUpTaskID: UUID?
    let details: JSONValue
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID,
        weddingID: UUID,
        momentType: PlanningMomentType,
        title: String,
        notes: String?,
        occurredAt: Date,
        locationText: String?,
        createdBy: UUID,
        linkedVenueID: UUID?,
        followUpTaskID: UUID?,
        details: JSONValue,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.weddingID = weddingID
        self.momentType = momentType
        self.title = title
        self.notes = notes
        self.occurredAt = occurredAt
        self.locationText = locationText
        self.createdBy = createdBy
        self.linkedVenueID = linkedVenueID
        self.followUpTaskID = followUpTaskID
        self.details = details
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case weddingID = "wedding_id"
        case momentType = "moment_type"
        case title, notes
        case occurredAt = "occurred_at"
        case locationText = "location_text"
        case createdBy = "created_by"
        case linkedVenueID = "linked_venue_id"
        case followUpTaskID = "follow_up_task_id"
        case details
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Supabase decodes the table's snake-case column names directly, while
    /// `DatabaseDecoding` normalizes them before matching coding keys. Accept
    /// both forms so contract tests exercise the same model as the live path.
    private enum DecodingKeys: String, CodingKey {
        case id, title, notes, details
        case weddingIDSnake = "wedding_id"
        case weddingIDCamel = "weddingId"
        case momentTypeSnake = "moment_type"
        case momentTypeCamel = "momentType"
        case occurredAtSnake = "occurred_at"
        case occurredAtCamel = "occurredAt"
        case locationTextSnake = "location_text"
        case locationTextCamel = "locationText"
        case createdBySnake = "created_by"
        case createdByCamel = "createdBy"
        case linkedVenueIDSnake = "linked_venue_id"
        case linkedVenueIDCamel = "linkedVenueId"
        case followUpTaskIDSnake = "follow_up_task_id"
        case followUpTaskIDCamel = "followUpTaskId"
        case createdAtSnake = "created_at"
        case createdAtCamel = "createdAt"
        case updatedAtSnake = "updated_at"
        case updatedAtCamel = "updatedAt"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: DecodingKeys.self)
        func key(_ snakeCase: DecodingKeys, or camelCase: DecodingKeys) -> DecodingKeys {
            values.contains(snakeCase) ? snakeCase : camelCase
        }
        id = try values.decode(UUID.self, forKey: .id)
        weddingID = try values.decode(UUID.self, forKey: key(.weddingIDSnake, or: .weddingIDCamel))
        momentType = try values.decode(PlanningMomentType.self, forKey: key(.momentTypeSnake, or: .momentTypeCamel))
        title = try values.decode(String.self, forKey: .title)
        notes = try values.decodeIfPresent(String.self, forKey: .notes)
        occurredAt = try values.decode(Date.self, forKey: key(.occurredAtSnake, or: .occurredAtCamel))
        locationText = try values.decodeIfPresent(String.self, forKey: key(.locationTextSnake, or: .locationTextCamel))
        createdBy = try values.decode(UUID.self, forKey: key(.createdBySnake, or: .createdByCamel))
        linkedVenueID = try values.decodeIfPresent(UUID.self, forKey: key(.linkedVenueIDSnake, or: .linkedVenueIDCamel))
        followUpTaskID = try values.decodeIfPresent(UUID.self, forKey: key(.followUpTaskIDSnake, or: .followUpTaskIDCamel))
        details = try values.decode(JSONValue.self, forKey: .details)
        createdAt = try values.decode(Date.self, forKey: key(.createdAtSnake, or: .createdAtCamel))
        updatedAt = try values.decode(Date.self, forKey: key(.updatedAtSnake, or: .updatedAtCamel))
    }
}

struct PlanningMomentRequirement: Codable, Equatable, Sendable, Hashable, Identifiable {
    let momentID: UUID
    let requirementID: UUID
    let observation: String?
    let createdAt: Date

    var id: String { "\(momentID.uuidString)-\(requirementID.uuidString)" }

    enum CodingKeys: String, CodingKey {
        case momentID = "moment_id"
        case requirementID = "requirement_id"
        case observation
        case createdAt = "created_at"
    }
}

struct PlanningMomentDraft: Codable, Equatable, Sendable {
    let momentType: PlanningMomentType
    let title: String
    let notes: String?
    let occurredAt: Date
    let locationText: String?
    let linkedVenueID: UUID?
    let followUpTaskID: UUID?
    let details: JSONValue?

    init(
        momentType: PlanningMomentType,
        title: String,
        notes: String? = nil,
        occurredAt: Date,
        locationText: String? = nil,
        linkedVenueID: UUID? = nil,
        followUpTaskID: UUID? = nil,
        details: JSONValue? = nil
    ) {
        self.momentType = momentType
        self.title = title
        self.notes = notes
        self.occurredAt = occurredAt
        self.locationText = locationText
        self.linkedVenueID = linkedVenueID
        self.followUpTaskID = followUpTaskID
        self.details = details
    }

    var validationMessage: String? {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Give this moment a title." : nil
    }

    enum CodingKeys: String, CodingKey {
        case momentType = "moment_type"
        case title, notes
        case occurredAt = "occurred_at"
        case locationText = "location_text"
        case linkedVenueID = "linked_venue_id"
        case followUpTaskID = "follow_up_task_id"
        case details
    }
}

// MARK: - Repository

protocol TimelineRepository: Sendable {
    func planningMoments(weddingID: UUID) async throws -> [PlanningMoment]
    func planningMomentRequirements(weddingID: UUID) async throws -> [PlanningMomentRequirement]
    func createPlanningMoment(_ draft: PlanningMomentDraft, weddingID: UUID) async throws -> PlanningMoment
    func createPlanningMomentRequirements(momentID: UUID, requirementIDs: [UUID]) async throws
}

final class SupabaseTimelineRepository: TimelineRepository, @unchecked Sendable {
    private let provider: SupabaseProvider
    private let momentColumns = "id,wedding_id,moment_type,title,notes,occurred_at,location_text,created_by,linked_venue_id,follow_up_task_id,details,created_at,updated_at"

    init(provider: SupabaseProvider) {
        self.provider = provider
    }

    func planningMoments(weddingID: UUID) async throws -> [PlanningMoment] {
        try await run {
            try await self.provider.client
                .from("planning_moments")
                .select(self.momentColumns)
                .eq("wedding_id", value: DomainRepositorySupport.uuid(weddingID))
                .order("occurred_at", ascending: false)
                .execute()
                .value
        }
    }

    func planningMomentRequirements(weddingID: UUID) async throws -> [PlanningMomentRequirement] {
        try await run {
            try await self.provider.client
                .from("planning_moment_requirements")
                .select("moment_id,requirement_id,observation,created_at,planning_moments!inner(wedding_id)")
                .eq("planning_moments.wedding_id", value: DomainRepositorySupport.uuid(weddingID))
                .execute()
                .value
        }
    }

    func createPlanningMoment(_ draft: PlanningMomentDraft, weddingID: UUID) async throws -> PlanningMoment {
        try await run {
            try await self.provider.client
                .from("planning_moments")
                .insert(PlanningMomentCreate(weddingID: weddingID, draft: draft))
                .select(self.momentColumns)
                .single()
                .execute()
                .value
        }
    }

    func createPlanningMomentRequirements(momentID: UUID, requirementIDs: [UUID]) async throws {
        guard !requirementIDs.isEmpty else { return }
        let _: [PlanningMomentRequirement] = try await run {
            try await self.provider.client
                .from("planning_moment_requirements")
                .insert(requirementIDs.map { PlanningMomentRequirementCreate(momentID: momentID, requirementID: $0) })
                .select("moment_id,requirement_id,observation,created_at")
                .execute()
                .value
        }
    }

    private func run<T: Decodable & Sendable>(_ body: () async throws -> T) async throws -> T {
        do {
            try await DomainRepositorySupport.authenticated(provider)
            return try await body()
        } catch {
            throw DomainRepositorySupport.normalized(error, fallback: "Timeline request failed.")
        }
    }
}

private struct PlanningMomentCreate: Codable {
    let weddingID: UUID
    let momentType: PlanningMomentType
    let title: String
    let notes: String?
    let occurredAt: Date
    let locationText: String?
    let linkedVenueID: UUID?
    let followUpTaskID: UUID?
    let details: JSONValue?

    init(weddingID: UUID, draft: PlanningMomentDraft) {
        self.weddingID = weddingID
        momentType = draft.momentType
        title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        notes = draft.notes?.timelineNilIfBlank
        occurredAt = draft.occurredAt
        locationText = draft.locationText?.timelineNilIfBlank
        linkedVenueID = draft.linkedVenueID
        followUpTaskID = draft.followUpTaskID
        details = draft.details
    }

    enum CodingKeys: String, CodingKey {
        case weddingID = "wedding_id"
        case momentType = "moment_type"
        case title, notes
        case occurredAt = "occurred_at"
        case locationText = "location_text"
        case linkedVenueID = "linked_venue_id"
        case followUpTaskID = "follow_up_task_id"
        case details
    }
}

private struct PlanningMomentRequirementCreate: Codable {
    let momentID: UUID
    let requirementID: UUID

    enum CodingKeys: String, CodingKey {
        case momentID = "moment_id"
        case requirementID = "requirement_id"
    }
}

// MARK: - Feed normalization and status

enum TimelineEntryKind: Equatable, Sendable {
    case moment(PlanningMomentType)
    case completedTask
    case taskAdded
    case venueAdded
    case guestAdded
    case requirement

    var title: String {
        switch self {
        case let .moment(type): type.title
        case .completedTask: "Task completed"
        case .taskAdded: "Task added"
        case .venueAdded: "Venue added"
        case .guestAdded: "Guest added"
        case .requirement: "Requirement added"
        }
    }

    var systemImage: String {
        switch self {
        case let .moment(type): type.systemImage
        case .completedTask: "checkmark.circle.fill"
        case .taskAdded: "checklist"
        case .venueAdded: PlanLens.venues.systemImage
        case .guestAdded: PlanLens.guests.systemImage
        case .requirement: "list.bullet.clipboard"
        }
    }
}

enum TimelineEntryDestination: Equatable, Sendable {
    case venue(UUID)
    case guest(UUID)
}

struct TimelineEntry: Identifiable, Equatable, Sendable {
    let id: String
    let kind: TimelineEntryKind
    let title: String
    let occurredAt: Date
    let notes: String?
    let locationText: String?
    let linkedVenueName: String?
    let requirementNames: [String]
    /// Stable identity for timeline row types that support navigation.
    /// The view resolves the current value from its owning store before routing.
    let destination: TimelineEntryDestination?
}

enum TimelineFeed {
    static func normalized(
        moments: [PlanningMoment],
        momentRequirements: [PlanningMomentRequirement],
        tasks: [WeddingTask],
        requirements: [MoodboardRequirement],
        venues: [MVPVenue],
        guests: [MVPGuest]
    ) -> [TimelineEntry] {
        let requirementNames = Dictionary(uniqueKeysWithValues: requirements.map { ($0.id, $0.title) })
        let venueNames = Dictionary(uniqueKeysWithValues: venues.map { ($0.id, $0.name) })
        let requirementsByMoment = Dictionary(grouping: momentRequirements, by: \.momentID)

        var entries = moments.map { moment in
            TimelineEntry(
                id: "moment-\(moment.id.uuidString)",
                kind: .moment(moment.momentType),
                title: moment.title,
                occurredAt: moment.occurredAt,
                notes: moment.notes,
                locationText: moment.locationText,
                linkedVenueName: moment.linkedVenueID.flatMap { venueNames[$0] },
                requirementNames: (requirementsByMoment[moment.id] ?? []).compactMap { requirementNames[$0.requirementID] }.sorted(),
                destination: nil
            )
        }

        entries += tasks.map { task in
            return TimelineEntry(
                id: "task-\(task.id.uuidString)",
                kind: task.completedAt == nil ? .taskAdded : .completedTask,
                title: task.title,
                occurredAt: task.completedAt ?? task.createdAt,
                notes: nil,
                locationText: nil,
                linkedVenueName: nil,
                requirementNames: [],
                destination: nil
            )
        }

        entries += venues.map { venue in
            TimelineEntry(
                id: "venue-\(venue.id.uuidString)",
                kind: .venueAdded,
                title: venue.name,
                occurredAt: venue.createdAt,
                notes: nil,
                locationText: nil,
                linkedVenueName: nil,
                requirementNames: [],
                destination: .venue(venue.id)
            )
        }

        entries += guests.map { guest in
            TimelineEntry(
                id: "guest-\(guest.id.uuidString)",
                kind: .guestAdded,
                title: guest.name,
                occurredAt: guest.createdAt,
                notes: nil,
                locationText: nil,
                linkedVenueName: nil,
                requirementNames: [],
                destination: .guest(guest.id)
            )
        }

        entries += requirements.map { requirement in
            TimelineEntry(
                id: "requirement-\(requirement.id.uuidString)",
                kind: .requirement,
                title: requirement.title,
                occurredAt: requirement.createdAt,
                notes: requirement.description,
                locationText: nil,
                linkedVenueName: nil,
                requirementNames: [],
                destination: nil
            )
        }

        return entries.sorted {
            if $0.occurredAt != $1.occurredAt { return $0.occurredAt > $1.occurredAt }
            return $0.id < $1.id
        }
    }
}

enum TimelineOnTrackStatus: Equatable, Sendable {
    case insufficientInformation(reason: String)
    case needsAttention(reason: String)
    case onTrack(reason: String)

    static func evaluate(
        weddingDate: String?,
        requirementCount: Int,
        tasks: [WeddingTask],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Self {
        guard let weddingDate, let weddingDay = WeddingCountdownFormatter.date(from: weddingDate) else {
            return .insufficientInformation(reason: "Set the wedding date to assess due dates and planning risk.")
        }

        let today = calendar.startOfDay(for: now)
        let weddingStart = calendar.startOfDay(for: weddingDay)
        if weddingStart < today {
            return .needsAttention(reason: "The wedding date has passed, so the plan needs a fresh review.")
        }
        guard requirementCount > 0 else {
            return .insufficientInformation(reason: "Add at least one requirement before assessing the plan.")
        }

        let activeTasks = tasks.filter { $0.effectiveStatus != .done }
        guard !activeTasks.isEmpty else {
            return .insufficientInformation(reason: "Add an active task before assessing the plan.")
        }

        let overdueCount = activeTasks.filter { task in
            guard let dueDate = task.dueDate.flatMap(TaskDueDateFormatter.date(from:)) else { return false }
            return calendar.startOfDay(for: dueDate) < today
        }.count
        if overdueCount > 0 {
            let noun = overdueCount == 1 ? "task is" : "tasks are"
            return .needsAttention(reason: "\(overdueCount) \(noun) overdue. Clear those first, then reassess the plan.")
        }

        if activeTasks.contains(where: { task in
            guard let dueDate = task.dueDate else { return true }
            return TaskDueDateFormatter.date(from: dueDate) == nil
        }) {
            return .insufficientInformation(reason: "Give every active task a valid due date before assessing the plan.")
        }

        let days = calendar.dateComponents([.day], from: today, to: weddingStart).day ?? 0
        return .onTrack(reason: "No overdue tasks and \(days) days until the wedding.")
    }

    var title: String {
        switch self {
        case .insufficientInformation: "More information needed"
        case .needsAttention: "Needs attention"
        case .onTrack: "On track"
        }
    }

    var systemImage: String {
        switch self {
        case .insufficientInformation: "questionmark.circle.fill"
        case .needsAttention: "exclamationmark.circle.fill"
        case .onTrack: "checkmark.circle.fill"
        }
    }

    var reason: String {
        switch self {
        case let .insufficientInformation(reason), let .needsAttention(reason), let .onTrack(reason): reason
        }
    }
}

// MARK: - Feature state

@MainActor
@Observable
final class TimelineStore {
    private let repository: (any TimelineRepository)?
    private let inspirationRepository: (any InspirationRepository)?

    private(set) var moments = [PlanningMoment]()
    private(set) var momentRequirements = [PlanningMomentRequirement]()
    private(set) var requirements = [MoodboardRequirement]()
    var isLoading = false
    var isSaving = false
    var errorMessage: String?
    var saveErrorMessage: String?

    init(
        repository: (any TimelineRepository)? = nil,
        inspirationRepository: (any InspirationRepository)? = nil
    ) {
        self.repository = repository
        self.inspirationRepository = inspirationRepository
    }

    func load(weddingID: UUID) async {
        guard let repository, let inspirationRepository else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let loadedMoments = repository.planningMoments(weddingID: weddingID)
            async let loadedLinks = repository.planningMomentRequirements(weddingID: weddingID)
            async let loadedRequirements = inspirationRepository.moodboardRequirements(weddingID: weddingID)
            moments = try await loadedMoments
            momentRequirements = try await loadedLinks
            requirements = try await loadedRequirements
        } catch is CancellationError {
            return
        } catch {
            errorMessage = userFacingMessage(for: error, fallback: "We couldn't load the timeline. Refresh and try again.")
        }
    }

    @discardableResult
    func create(_ draft: PlanningMomentDraft, requirementIDs: Set<UUID>, weddingID: UUID) async -> Bool {
        guard let validationMessage = draft.validationMessage else {
            saveErrorMessage = nil
            errorMessage = nil
            isSaving = true
            defer { isSaving = false }

            do {
                let saved: PlanningMoment
                if let repository {
                    saved = try await repository.createPlanningMoment(draft, weddingID: weddingID)
                } else {
                    let now = Date()
                    saved = PlanningMoment(
                        id: UUID(), weddingID: weddingID, momentType: draft.momentType,
                        title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines), notes: draft.notes?.timelineNilIfBlank,
                        occurredAt: draft.occurredAt, locationText: draft.locationText?.timelineNilIfBlank,
                        createdBy: UUID(), linkedVenueID: draft.linkedVenueID, followUpTaskID: draft.followUpTaskID,
                        details: draft.details ?? .object([:]), createdAt: now, updatedAt: now
                    )
                }
                moments.append(saved)

                if let repository, !requirementIDs.isEmpty {
                    do {
                        try await repository.createPlanningMomentRequirements(momentID: saved.id, requirementIDs: Array(requirementIDs))
                    } catch {
                        errorMessage = "Your moment was saved, but its requirement links couldn’t be saved. Refresh the timeline before trying to add links again."
                        return true
                    }
                }
                let newLinks = requirementIDs.map {
                    PlanningMomentRequirement(momentID: saved.id, requirementID: $0, observation: nil, createdAt: saved.createdAt)
                }
                momentRequirements.append(contentsOf: newLinks)
                return true
            } catch {
                saveErrorMessage = userFacingMessage(for: error, fallback: "We couldn't save that moment. Try again.")
                return false
            }
        }
        saveErrorMessage = validationMessage
        return false
    }

    @discardableResult
    func createRequirement(_ draft: MoodboardRequirementDraft, weddingID: UUID) async -> Bool {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            saveErrorMessage = "Give this requirement a title."
            return false
        }

        saveErrorMessage = nil
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        do {
            let normalized = MoodboardRequirementDraft(
                importance: draft.importance,
                title: title,
                description: draft.description?.timelineNilIfBlank,
                position: draft.position
            )
            let saved: MoodboardRequirement
            if let inspirationRepository {
                saved = try await inspirationRepository.createMoodboardRequirement(normalized, weddingID: weddingID)
            } else {
                let now = Date()
                saved = MoodboardRequirement(
                    id: UUID(), weddingID: weddingID, importance: normalized.importance,
                    title: normalized.title, description: normalized.description,
                    position: normalized.position, createdAt: now, updatedAt: now
                )
            }
            requirements.append(saved)
            requirements.sort {
                $0.position == $1.position ? $0.createdAt < $1.createdAt : $0.position < $1.position
            }
            return true
        } catch {
            saveErrorMessage = userFacingMessage(for: error, fallback: "We couldn't save that requirement. Try again.")
            return false
        }
    }

    func feed(tasks: [WeddingTask], venues: [MVPVenue], guests: [MVPGuest]) -> [TimelineEntry] {
        TimelineFeed.normalized(
            moments: moments,
            momentRequirements: momentRequirements,
            tasks: tasks,
            requirements: requirements,
            venues: venues,
            guests: guests
        )
    }

    private func userFacingMessage(for error: Error, fallback: String) -> String {
        switch error as? BackendError {
        case .forbidden: "You don’t have permission to change the timeline."
        case .networkUnavailable: "Vowbase couldn’t reach the server. Check your connection and try again."
        case .authenticationRequired: "Your session has ended. Please sign in again."
        default: fallback
        }
    }
}

// MARK: - View

@MainActor
struct PlanningTimelineView: View {
    let store: VowbaseWorkspaceStore
    let taskStore: TaskStore
    let timelineStore: TimelineStore
    let onOpenVenue: (MVPVenue) -> Void
    let onOpenGuest: (MVPGuest) -> Void

    init(
        store: VowbaseWorkspaceStore,
        taskStore: TaskStore,
        timelineStore: TimelineStore,
        onOpenVenue: @escaping (MVPVenue) -> Void = { _ in },
        onOpenGuest: @escaping (MVPGuest) -> Void = { _ in }
    ) {
        self.store = store
        self.taskStore = taskStore
        self.timelineStore = timelineStore
        self.onOpenVenue = onOpenVenue
        self.onOpenGuest = onOpenGuest
    }

    private var weddingID: UUID? { store.wedding?.id }
    private var entries: [TimelineEntry] {
        timelineStore.feed(tasks: taskStore.tasks, venues: store.venues, guests: store.guests)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Timeline").displayTitle()
                Spacer()
            }
            .padding(.horizontal, VowbaseControlMetric.screenInset)
            .padding(.bottom, VowbaseSpace.small)

            Group {
                if timelineStore.isLoading && entries.isEmpty {
                    ProgressView("Loading timeline")
                        .tint(VowbaseTheme.rose)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if entries.isEmpty {
                    ScrollView {
                        VStack(spacing: VowbaseSpace.large) {
                            if let planningStatus {
                                TimelineStatusRow(status: planningStatus)
                            }
                            ContentUnavailableView {
                                Label("No timeline activity yet", systemImage: "clock.arrow.circlepath")
                            } description: {
                                Text("Add a task, guest, venue, requirement, or planning moment to start your timeline.")
                            }
                        }
                        .padding(VowbaseControlMetric.screenInset)
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                            if let planningStatus {
                                TimelineStatusRow(status: planningStatus)
                                    .padding(.bottom, VowbaseSpace.medium)
                            }

                            ForEach(Array(groupedEntries.enumerated()), id: \.offset) { _, group in
                                Text(TimelineDateFormatter.divider.string(from: group.date).uppercased())
                                    .font(VowbaseType.eyebrow)
                                    .foregroundStyle(VowbaseTheme.mutedInk)
                                    .padding(.top, VowbaseSpace.medium)
                                    .padding(.bottom, VowbaseSpace.small)
                                    .accessibilityAddTraits(.isHeader)

                                ForEach(group.entries) { entry in
                                    TimelineEntryRow(entry: entry, onOpen: openAction(for: entry))
                                    Divider()
                                }
                            }
                        }
                        .padding(.horizontal, VowbaseControlMetric.screenInset)
                        .padding(.bottom, VowbaseControlMetric.quickAddClearance + VowbaseSpace.medium)
                    }
                    .refreshable { await refresh() }
                }
            }
        }
        .overlay(alignment: .top) {
            if let errorMessage = timelineStore.errorMessage, !timelineStore.isSaving {
                TimelineErrorBanner(message: errorMessage) { Task { await refresh() } }
                    .padding(.horizontal, VowbaseControlMetric.screenInset)
            }
        }
        .task(id: weddingID) {
            guard let weddingID else { return }
            async let workspace: Bool = store.load(presentsFailure: false)
            async let tasks: Void = taskStore.load(weddingID: weddingID)
            async let timeline: Void = timelineStore.load(weddingID: weddingID)
            _ = await (workspace, tasks, timeline)
        }
    }

    private var planningStatus: TimelineOnTrackStatus? {
        guard let weddingDate = store.wedding?.weddingDate,
              WeddingCountdownFormatter.date(from: weddingDate) != nil else { return nil }
        return TimelineOnTrackStatus.evaluate(
            weddingDate: weddingDate,
            requirementCount: timelineStore.requirements.count,
            tasks: taskStore.tasks
        )
    }

    private var groupedEntries: [(date: Date, entries: [TimelineEntry])] {
        let calendar = Calendar.current
        return entries.reduce(into: [(date: Date, entries: [TimelineEntry])]()) { result, entry in
            if let index = result.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: entry.occurredAt) }) {
                result[index].entries.append(entry)
            } else {
                result.append((calendar.startOfDay(for: entry.occurredAt), [entry]))
            }
        }
    }

    private func refresh() async {
        guard let weddingID else { return }
        async let workspace: Bool = store.load(presentsFailure: false)
        async let tasks: Void = taskStore.load(weddingID: weddingID)
        async let timeline: Void = timelineStore.load(weddingID: weddingID)
        _ = await (workspace, tasks, timeline)
    }

    private func openAction(for entry: TimelineEntry) -> (() -> Void)? {
        switch entry.destination {
        case let .venue(id):
            guard let venue = store.venues.first(where: { $0.id == id }) else { return nil }
            return { onOpenVenue(venue) }
        case let .guest(id):
            guard let guest = store.guests.first(where: { $0.id == id }) else { return nil }
            return { onOpenGuest(guest) }
        case nil:
            return nil
        }
    }
}

private enum TimelineDateFormatter {
    static let divider: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let entry: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct TimelineStatusRow: View {
    let status: TimelineOnTrackStatus

    private var tint: Color {
        switch status {
        case .onTrack: VowbaseTheme.rose
        case .insufficientInformation, .needsAttention: .orange
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: VowbaseSpace.small) {
            Image(systemName: status.systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(status.title)
                    .font(VowbaseType.headline)
                    .foregroundStyle(VowbaseTheme.ink)
                Text(status.reason)
                    .font(VowbaseType.secondary)
                    .foregroundStyle(VowbaseTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(VowbaseSpace.medium)
        .background(VowbaseTheme.blush.opacity(0.7), in: RoundedRectangle(cornerRadius: VowbaseRadius.small, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Planning status: \(status.title). \(status.reason)")
    }
}

private struct TimelineEntryRow: View {
    let entry: TimelineEntry
    let onOpen: (() -> Void)?

    var body: some View {
        if let onOpen {
            Button(action: onOpen) {
                content
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Opens \(entry.title)")
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel)
        }
    }

    private var accessibilityLabel: String {
        "\(entry.kind.title): \(entry.title), \(TimelineDateFormatter.divider.string(from: entry.occurredAt))"
    }

    private var content: some View {
        HStack(alignment: .top, spacing: VowbaseSpace.medium) {
            Image(systemName: entry.kind.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(VowbaseTheme.rose)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: VowbaseSpace.small) {
                    Text(entry.title)
                        .font(VowbaseType.headline)
                        .foregroundStyle(VowbaseTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: VowbaseSpace.small)
                    Text(TimelineDateFormatter.entry.string(from: entry.occurredAt))
                        .font(VowbaseType.caption)
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }
                Text(entry.kind.title)
                    .font(VowbaseType.caption)
                    .foregroundStyle(VowbaseTheme.mutedInk)
                if let notes = entry.notes {
                    Text(notes)
                        .font(VowbaseType.secondary)
                        .foregroundStyle(VowbaseTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let locationText = entry.locationText {
                    Label(locationText, systemImage: "mappin")
                        .font(VowbaseType.caption)
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }
                if let venue = entry.linkedVenueName {
                    Label(venue, systemImage: "building.2")
                        .font(VowbaseType.caption)
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }
                if !entry.requirementNames.isEmpty {
                    Label(entry.requirementNames.joined(separator: ", "), systemImage: "list.bullet")
                        .font(VowbaseType.caption)
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }
            }
        }
        .padding(.vertical, VowbaseSpace.medium)
    }
}

private struct TimelineErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: VowbaseSpace.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(VowbaseType.caption)
                .foregroundStyle(VowbaseTheme.ink)
            Spacer(minLength: 0)
            Button("Refresh", action: retry)
                .font(VowbaseType.caption.weight(.semibold))
        }
        .padding(VowbaseSpace.small)
        .background(VowbaseDesign.surface, in: RoundedRectangle(cornerRadius: VowbaseRadius.small, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct TimelineComposer: View {
    @Environment(\.dismiss) private var dismiss
    let timelineStore: TimelineStore
    let weddingID: UUID
    let venues: [MVPVenue]

    @State private var momentType: PlanningMomentType = .venueTour
    @State private var title = ""
    @State private var occurredAt = Date()
    @State private var notes = ""
    @State private var locationText = ""
    @State private var linkedVenueID: UUID?
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Moment") {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.sentences)
                        .focused($isTitleFocused)
                    Picker("Type", selection: $momentType) {
                        ForEach(PlanningMomentType.allCases) { type in
                            Label(type.title, systemImage: type.systemImage).tag(type)
                        }
                    }
                    DatePicker("When", selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Details") {
                    Picker("Linked Venue", selection: $linkedVenueID) {
                        Text("None").tag(UUID?.none)
                        ForEach(venues) { venue in
                            Text(venue.name).tag(Optional(venue.id))
                        }
                    }
                    TextField("Location (optional)", text: $locationText)
                        .textInputAutocapitalization(.words)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...7)
                }
            }
            .navigationTitle("Add Moment")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { isTitleFocused = true }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(timelineStore.isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .overlay {
                if timelineStore.isSaving {
                    ProgressView("Saving moment")
                        .padding(VowbaseSpace.large)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: VowbaseRadius.standard, style: .continuous))
                }
            }
            .alert("We couldn’t save that moment", isPresented: saveErrorBinding) {
                Button("OK", role: .cancel) { timelineStore.saveErrorMessage = nil }
            } message: {
                Text(timelineStore.saveErrorMessage ?? "Please try again.")
            }
        }
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(
            get: { timelineStore.saveErrorMessage != nil && !timelineStore.isSaving },
            set: { if !$0 { timelineStore.saveErrorMessage = nil } }
        )
    }

    private func save() async {
        let saved = await timelineStore.create(
            PlanningMomentDraft(
                momentType: momentType,
                title: title,
                notes: notes.timelineNilIfBlank,
                occurredAt: occurredAt,
                locationText: locationText.timelineNilIfBlank,
                linkedVenueID: linkedVenueID
            ),
            requirementIDs: [],
            weddingID: weddingID
        )
        if saved { dismiss() }
    }
}

struct RequirementComposer: View {
    @Environment(\.dismiss) private var dismiss
    let timelineStore: TimelineStore
    let weddingID: UUID

    @State private var title = ""
    @State private var importance = "core"
    @State private var notes = ""
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Requirement") {
                    TextField("Outdoor ceremony space", text: $title)
                        .textInputAutocapitalization(.sentences)
                        .focused($isTitleFocused)
                    Picker("Importance", selection: $importance) {
                        Text("Must Have").tag("core")
                        Text("Nice to Have").tag("preference")
                    }
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...7)
                }
            }
            .navigationTitle("Add Requirement")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { isTitleFocused = true }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await save() } }
                        .disabled(timelineStore.isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .overlay {
                if timelineStore.isSaving {
                    ProgressView("Saving requirement")
                        .padding(VowbaseSpace.large)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: VowbaseRadius.standard, style: .continuous))
                }
            }
            .alert("We couldn’t save that requirement", isPresented: saveErrorBinding) {
                Button("OK", role: .cancel) { timelineStore.saveErrorMessage = nil }
            } message: {
                Text(timelineStore.saveErrorMessage ?? "Please try again.")
            }
        }
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(
            get: { timelineStore.saveErrorMessage != nil && !timelineStore.isSaving },
            set: { if !$0 { timelineStore.saveErrorMessage = nil } }
        )
    }

    private func save() async {
        let nextPosition = (timelineStore.requirements.map(\.position).max() ?? -1) + 1
        let saved = await timelineStore.createRequirement(
            MoodboardRequirementDraft(
                importance: importance,
                title: title,
                description: notes.timelineNilIfBlank,
                position: nextPosition
            ),
            weddingID: weddingID
        )
        if saved { dismiss() }
    }
}

private extension String {
    var timelineNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
