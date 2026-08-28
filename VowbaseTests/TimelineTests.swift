import Foundation
import Testing
@testable import Vowbase

@Suite("Timeline domain")
struct TimelineTests {
    private let weddingID = UUID(uuidString: "77B779C0-7E5B-4F9D-94F3-00C13DCEE5B4")!
    private let momentID = UUID(uuidString: "11B779C0-7E5B-4F9D-94F3-00C13DCEE5B4")!
    private let requirementID = UUID(uuidString: "22B779C0-7E5B-4F9D-94F3-00C13DCEE5B4")!
    private let creatorID = UUID(uuidString: "33B779C0-7E5B-4F9D-94F3-00C13DCEE5B4")!

    @Test("normalization is reverse chronological and excludes legacy done tasks without completion timestamps")
    func normalizesFeedWithoutFabricatingTaskHistory() {
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
            requirements: [requirement], venues: []
        )

        #expect(entries.map(\.title) == ["Book band", "Choose flowers", "Warm lighting"])
        #expect(!entries.contains { $0.title == "Old imported task" })
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
            tasks: [], requirements: [requirement], venues: [venue]
        ).first

        #expect(entry?.linkedVenueName == "Riverside Pavilion")
        #expect(entry?.requirementNames == ["Water view"])
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

    func createPlanningMomentRequirements(momentID _: UUID, requirementIDs _: [UUID]) async throws {
        requirementInsertAttempts += 1
        throw PartialSaveError.linkInsertFailed
    }
}

private enum PartialSaveError: Error {
    case linkInsertFailed
}

private enum MVPVenueFixture {
    static func make(name: String) -> MVPVenue {
        MVPVenue(
            id: UUID(), name: name, status: .toured, location: "Duluth", city: nil, state: nil,
            distanceMiles: nil, mapSearchQuery: "Duluth", fullAddress: nil, capacityMin: nil,
            capacityMax: nil, capacityTextOverride: nil, estimate: "", venueEstimateTextRaw: nil,
            travel: nil, allInEstimate: "", availableDates: "", summary: nil, website: nil,
            contactName: nil, contactEmail: nil, contactPhone: nil, latitude: nil, longitude: nil,
            coverPhotoURL: nil, coverPhotoCacheKey: "", photos: [], documents: [], ourNotes: nil
        )
    }
}
