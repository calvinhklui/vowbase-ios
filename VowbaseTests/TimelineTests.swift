import Foundation
import Testing
@testable import Vowbase

@Suite("Timeline domain")
struct TimelineTests {
    private let weddingID = UUID(uuidString: "77B779C0-7E5B-4F9D-94F3-00C13DCEE5B4")!
    private let momentID = UUID(uuidString: "11B779C0-7E5B-4F9D-94F3-00C13DCEE5B4")!
    private let requirementID = UUID(uuidString: "22B779C0-7E5B-4F9D-94F3-00C13DCEE5B4")!
    private let creatorID = UUID(uuidString: "33B779C0-7E5B-4F9D-94F3-00C13DCEE5B4")!

    @Test("normalization is reverse chronological and gives each task one lifecycle entry")
    func normalizesFeedWithTaskCompletionPrecedence() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let moment = PlanningMoment(
            id: momentID, weddingID: weddingID, momentType: .decision, title: "Choose flowers",
            notes: nil, occurredAt: now.addingTimeInterval(-60), locationText: nil,
            createdBy: creatorID, linkedVenueID: nil, followUpTaskID: nil, details: .object([:]),
            createdAt: now, updatedAt: now
        )
        let completed = task(title: "Book band", status: .done, completedAt: now.addingTimeInterval(60), createdAt: now)
        let legacyDone = task(title: "Old imported task", status: .done, completedAt: nil, createdAt: now)
        let requirement = MoodboardRequirement(
            id: requirementID, weddingID: weddingID, importance: "must_have", title: "Warm lighting",
            description: nil, position: 0, createdAt: now.addingTimeInterval(-120), updatedAt: now
        )

        let entries = TimelineFeed.normalized(
            moments: [moment], momentRequirements: [], tasks: [legacyDone, completed],
            requirements: [requirement], venues: [], guests: []
        )

        #expect(entries.map(\.title) == ["Book band", "Old imported task", "Choose flowers", "Warm lighting"])
        #expect(entries.first?.kind == .completedTask)
        #expect(entries.first?.occurredAt == completed.completedAt)
        #expect(entries[1].kind == .taskAdded)
        #expect(entries[1].occurredAt == legacyDone.createdAt)
        #expect(entries[2].destination == .moment(moment.id))
        #expect(entries[3].destination == .requirement(requirement.id))
        #expect(entries.filter { $0.id == "task-\(completed.id.uuidString)" }.count == 1)
    }

    @Test("moment links resolve requirements and venue names")
    func resolvesManualMomentLinks() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let venue = MVPVenueFixture.make(name: "Riverside Pavilion")
        let moment = PlanningMoment(
            id: momentID, weddingID: weddingID, momentType: .venueTour, title: "Tour Riverside",
            notes: nil, occurredAt: now, locationText: "Duluth", createdBy: creatorID,
            linkedVenueID: venue.id, followUpTaskID: nil, details: .object([:]), createdAt: now, updatedAt: now
        )
        let requirement = MoodboardRequirement(
            id: requirementID, weddingID: weddingID, importance: "must_have", title: "Water view",
            description: nil, position: 0, createdAt: now, updatedAt: now
        )

        let entry = TimelineFeed.normalized(
            moments: [moment],
            momentRequirements: [.init(momentID: momentID, requirementID: requirementID, observation: nil, createdAt: now)],
            tasks: [], requirements: [requirement], venues: [venue], guests: []
        ).first

        #expect(entry?.linkedVenueName == "Riverside Pavilion")
        #expect(entry?.requirementNames == ["Water view"])
    }

    @Test("venue and guest additions use creation dates and preserve mixed-source ordering")
    func normalizesVenueAndGuestAdditions() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let venue = MVPVenueFixture.make(name: "Riverside Pavilion", createdAt: now.addingTimeInterval(-60))
        let guest = MVPGuestFixture.make(firstName: "Avery", lastName: "Ng", createdAt: now)
        let addedTask = task(title: "Draft seating plan", status: .todo, completedAt: nil, createdAt: now.addingTimeInterval(-120))

        let entries = TimelineFeed.normalized(
            moments: [],
            momentRequirements: [],
            tasks: [addedTask],
            requirements: [],
            venues: [venue],
            guests: [guest]
        )

        #expect(entries.map(\.title) == ["Avery Ng", "Riverside Pavilion", "Draft seating plan"])
        #expect(entries.map(\.kind) == [.guestAdded, .venueAdded, .taskAdded])
        #expect(entries.allSatisfy { $0.notes == nil && $0.locationText == nil })
        #expect(entries[0].destination == .guest(guest.id))
        #expect(entries[0].kind.systemImage == PlanLens.guests.systemImage)
        #expect(entries[1].destination == .venue(venue.id))
        #expect(entries[1].kind.systemImage == PlanLens.venues.systemImage)
        #expect(entries[2].destination == nil)
    }

    @Test("on-track state follows conservative information and overdue boundaries")
    func evaluatesPlanningStatusBoundaries() {
        let calendar = Calendar.current
        let now = Date()
        let today = WeddingCountdownFormatter.string(from: now)
        let futureWedding = WeddingCountdownFormatter.string(from: calendar.date(byAdding: .day, value: 10, to: now)!)
        let passedWedding = WeddingCountdownFormatter.string(from: calendar.date(byAdding: .day, value: -2, to: now)!)
        let futureDue = TaskDueDateFormatter.string(from: calendar.date(byAdding: .day, value: 2, to: now)!)
        let overdueDue = TaskDueDateFormatter.string(from: calendar.date(byAdding: .day, value: -2, to: now)!)
        let activeTask = task(title: "Confirm florist", status: .todo, dueDate: futureDue, completedAt: nil, createdAt: now)

        #expect(isInsufficient(TimelineOnTrackStatus.evaluate(weddingDate: nil, requirementCount: 1, tasks: [activeTask], now: now, calendar: calendar)))
        #expect(isInsufficient(TimelineOnTrackStatus.evaluate(weddingDate: futureWedding, requirementCount: 0, tasks: [activeTask], now: now, calendar: calendar)))
        #expect(isInsufficient(TimelineOnTrackStatus.evaluate(weddingDate: futureWedding, requirementCount: 1, tasks: [], now: now, calendar: calendar)))
        let noTaskStatus = TimelineOnTrackStatus.evaluate(weddingDate: futureWedding, requirementCount: 1, tasks: [activeTask], now: now, calendar: calendar)
        #expect(isOnTrack(noTaskStatus))
        #expect(isOnTrack(TimelineOnTrackStatus.evaluate(weddingDate: today, requirementCount: 1, tasks: [activeTask], now: now, calendar: calendar)))
        #expect(isNeedsAttention(TimelineOnTrackStatus.evaluate(weddingDate: passedWedding, requirementCount: 1, tasks: [activeTask], now: now, calendar: calendar)))
        #expect(TimelineOnTrackStatus.evaluate(
            weddingDate: futureWedding,
            requirementCount: 1,
            tasks: [task(title: "Late", status: .todo, dueDate: overdueDue, completedAt: nil, createdAt: now)],
            now: now,
            calendar: calendar
        ) == .needsAttention(reason: "1 task is overdue. Clear those first, then reassess the plan."))
        let legacyDoneStatus = TimelineOnTrackStatus.evaluate(
            weddingDate: futureWedding,
            requirementCount: 1,
            tasks: [
                activeTask,
                task(title: "Legacy done", status: .done, dueDate: overdueDue, completedAt: nil, createdAt: now),
            ],
            now: now,
            calendar: calendar
        )
        #expect(isOnTrack(legacyDoneStatus))
        #expect(isInsufficient(TimelineOnTrackStatus.evaluate(
            weddingDate: futureWedding,
            requirementCount: 1,
            tasks: [task(title: "No due date", status: .todo, dueDate: nil, completedAt: nil, createdAt: now)],
            now: now,
            calendar: calendar
        )))
        #expect(isInsufficient(TimelineOnTrackStatus.evaluate(
            weddingDate: futureWedding,
            requirementCount: 1,
            tasks: [task(title: "Invalid due date", status: .todo, dueDate: "not-a-date", completedAt: nil, createdAt: now)],
            now: now,
            calendar: calendar
        )))
    }

    @Test("planning moment models decode database keys and drafts encode contract keys")
    func decodesAndEncodesPlanningMoments() throws {
        let decoded = try DatabaseDecoding.decoder.decode(
            PlanningMoment.self,
            from: Data("""
            {
              "id":"11B779C0-7E5B-4F9D-94F3-00C13DCEE5B4",
              "wedding_id":"77B779C0-7E5B-4F9D-94F3-00C13DCEE5B4",
              "moment_type":"meeting",
              "title":"Meet the florist",
              "notes":null,
              "occurred_at":"2027-01-02T12:30:00Z",
              "location_text":"Studio",
              "created_by":"33B779C0-7E5B-4F9D-94F3-00C13DCEE5B4",
              "linked_venue_id":null,
              "follow_up_task_id":null,
              "details":{},
              "created_at":"2027-01-02T12:30:00Z",
              "updated_at":"2027-01-02T12:30:00Z"
            }
            """.utf8)
        )
        let draft = PlanningMomentDraft(momentType: .payment, title: "Pay deposit", occurredAt: decoded.occurredAt, locationText: "Online")
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])

        #expect(decoded.momentType == .meeting)
        #expect(decoded.locationText == "Studio")
        #expect(decoded.createdBy == creatorID)
        #expect(decoded.details == .object([:]))
        #expect(object["moment_type"] as? String == "payment")
        #expect(object["location_text"] as? String == "Online")
        #expect(object["occurred_at"] != nil)
        #expect(object["details"] == nil)
    }

    @Test("moodboard requirements decode Supabase and normalized database keys")
    func decodesMoodboardRequirementsFromSupabaseContract() throws {
        let data = Data("""
        {
          "id":"22B779C0-7E5B-4F9D-94F3-00C13DCEE5B4",
          "wedding_id":"77B779C0-7E5B-4F9D-94F3-00C13DCEE5B4",
          "importance":"must_have",
          "title":"Water view",
          "description":null,
          "position":0,
          "created_at":"2027-01-02T12:30:00Z",
          "updated_at":"2027-01-02T12:30:00Z"
        }
        """.utf8)
        let supabaseStyleDecoder = JSONDecoder()
        supabaseStyleDecoder.dateDecodingStrategy = .custom(ISO8601DateDecoding.decode)

        let direct = try supabaseStyleDecoder.decode(MoodboardRequirement.self, from: data)
        let normalized = try DatabaseDecoding.decoder.decode(MoodboardRequirement.self, from: data)

        #expect(direct.id == requirementID)
        #expect(direct.weddingID == weddingID)
        #expect(direct.title == "Water view")
        #expect(direct.importance == "must_have")
        #expect(direct.position == 0)
        #expect(direct == normalized)
    }

    @Test("composer validation rejects a blank title")
    func validatesDraft() {
        #expect(PlanningMomentDraft(momentType: .custom, title: " \n", occurredAt: Date()).validationMessage == "Give this moment a title.")
    }

    @Test("timeline is the first visible lens")
    func timelineIsFirstVisibleLens() {
        #expect(PlanLens.visibleRailCases == [.timeline, .venues, .guests, .tasks])
    }

    @Test("requirement creation trims fields and appends to the timeline")
    @MainActor
    func createsRequirement() async {
        let store = TimelineStore()

        let saved = await store.createRequirement(
            MoodboardRequirementDraft(
                importance: "core",
                title: "  Outdoor ceremony space  ",
                description: "  ",
                position: 0
            ),
            weddingID: weddingID
        )

        #expect(saved)
        #expect(store.requirements.count == 1)
        #expect(store.requirements.first?.title == "Outdoor ceremony space")
        #expect(store.requirements.first?.description == nil)
    }

    @Test("moments can be updated and deleted through the editor store path")
    @MainActor
    func updatesAndDeletesMoment() async throws {
        let store = TimelineStore()
        let created = await store.create(
            PlanningMomentDraft(momentType: .meeting, title: "Meet florist", occurredAt: Date()),
            requirementIDs: [],
            weddingID: weddingID
        )
        #expect(created)
        let moment = try #require(store.moments.first)

        let updated = await store.update(
            moment,
            draft: PlanningMomentDraft(
                momentType: .decision,
                title: "Choose florist",
                notes: "Shortlist reviewed",
                occurredAt: moment.occurredAt,
                locationText: "Studio"
            )
        )
        #expect(updated)
        #expect(store.moments.first?.title == "Choose florist")
        #expect(store.moments.first?.momentType == .decision)
        #expect(store.moments.first?.locationText == "Studio")

        let savedMoment = try #require(store.moments.first)
        let deleted = await store.delete(savedMoment)
        #expect(deleted)
        #expect(store.moments.isEmpty)
    }

    @Test("requirements can be updated and deleted through the editor store path")
    @MainActor
    func updatesAndDeletesRequirement() async throws {
        let store = TimelineStore()
        let created = await store.createRequirement(
            MoodboardRequirementDraft(
                importance: "core",
                title: "Outdoor ceremony",
                description: nil,
                position: 0
            ),
            weddingID: weddingID
        )
        #expect(created)
        let requirement = try #require(store.requirements.first)

        let updated = await store.updateRequirement(
            requirement,
            draft: MoodboardRequirementDraft(
                importance: "preference",
                title: "Covered outdoor ceremony",
                description: "Rain-ready",
                position: requirement.position
            )
        )
        #expect(updated)
        #expect(store.requirements.first?.title == "Covered outdoor ceremony")
        #expect(store.requirements.first?.importance == "preference")
        #expect(store.requirements.first?.description == "Rain-ready")

        let savedRequirement = try #require(store.requirements.first)
        let deleted = await store.deleteRequirement(savedRequirement)
        #expect(deleted)
        #expect(store.requirements.isEmpty)
    }

    @Test("a requirement-link failure keeps the persisted moment and avoids resubmission")
    @MainActor
    func retainsPersistedMomentAfterRequirementLinkFailure() async {
        let repository = PartiallyFailingTimelineRepository(weddingID: weddingID, creatorID: creatorID)
        let store = TimelineStore(repository: repository)

        let saved = await store.create(
            PlanningMomentDraft(momentType: .decision, title: "Choose a caterer", occurredAt: Date()),
            requirementIDs: [requirementID],
            weddingID: weddingID
        )

        #expect(saved)
        #expect(store.moments == [repository.persistedMoment])
        #expect(store.momentRequirements.isEmpty)
        #expect(store.errorMessage?.contains("moment was saved") == true)
        #expect(repository.requirementInsertAttempts == 1)
    }

    private func task(
        title: String,
        status: WeddingTaskStatus,
        dueDate: String? = nil,
        completedAt: Date?,
        createdAt: Date
    ) -> WeddingTask {
        WeddingTask(
            id: UUID(), weddingID: weddingID, title: title, description: nil, status: status,
            priority: .medium, ownerUserID: nil, ownerLabel: nil, dueDate: dueDate,
            completedAt: completedAt, createdAt: createdAt
        )
    }

    private func isOnTrack(_ status: TimelineOnTrackStatus) -> Bool {
        if case .onTrack = status { return true }
        return false
    }

    private func isNeedsAttention(_ status: TimelineOnTrackStatus) -> Bool {
        if case .needsAttention = status { return true }
        return false
    }

    private func isInsufficient(_ status: TimelineOnTrackStatus) -> Bool {
        if case .insufficientInformation = status { return true }
        return false
    }
}

private final class PartiallyFailingTimelineRepository: TimelineRepository, @unchecked Sendable {
    let persistedMoment: PlanningMoment
    private(set) var requirementInsertAttempts = 0

    init(weddingID: UUID, creatorID: UUID) {
        let now = Date()
        persistedMoment = PlanningMoment(
            id: UUID(), weddingID: weddingID, momentType: .decision, title: "Choose a caterer",
            notes: nil, occurredAt: now, locationText: nil, createdBy: creatorID,
            linkedVenueID: nil, followUpTaskID: nil, details: .object([:]), createdAt: now, updatedAt: now
        )
    }

    func planningMoments(weddingID _: UUID) async throws -> [PlanningMoment] { [] }
    func planningMomentRequirements(weddingID _: UUID) async throws -> [PlanningMomentRequirement] { [] }
    func createPlanningMoment(_: PlanningMomentDraft, weddingID _: UUID) async throws -> PlanningMoment { persistedMoment }
    func updatePlanningMoment(id _: UUID, draft _: PlanningMomentDraft) async throws -> PlanningMoment { persistedMoment }
    func deletePlanningMoment(id _: UUID) async throws {}

    func createPlanningMomentRequirements(momentID _: UUID, requirementIDs _: [UUID]) async throws {
        requirementInsertAttempts += 1
        throw PartialSaveError.linkInsertFailed
    }
}

private enum PartialSaveError: Error {
    case linkInsertFailed
}

private enum MVPVenueFixture {
    static func make(name: String, createdAt: Date = Date()) -> MVPVenue {
        MVPVenue(
            id: UUID(), name: name, createdAt: createdAt, status: .toured, location: "Duluth", city: nil, state: nil,
            distanceMiles: nil, mapSearchQuery: "Duluth", fullAddress: nil, capacityMin: nil,
            capacityMax: nil, capacityTextOverride: nil, estimate: "", venueEstimateTextRaw: nil,
            travel: nil, allInEstimate: "", availableDates: "", summary: nil, website: nil,
            contactName: nil, contactEmail: nil, contactPhone: nil, latitude: nil, longitude: nil,
            coverPhotoURL: nil, coverPhotoCacheKey: "", photos: [], documents: [], ourNotes: nil
        )
    }
}

private enum MVPGuestFixture {
    static func make(firstName: String, lastName: String, createdAt: Date) -> MVPGuest {
        MVPGuest(
            id: UUID(), firstName: firstName, lastName: lastName, createdAt: createdAt,
            subtitle: nil, location: nil, email: nil, phone: nil, rsvp: .notInvited,
            isMappable: false, customSearchText: ""
        )
    }
}
