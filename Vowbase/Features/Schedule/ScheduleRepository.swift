import Foundation
protocol ScheduleRepository: Sendable {
    func events(weddingID: UUID) async throws -> [WeddingEvent]
    func createEvent(_ draft: EventDraft, weddingID: UUID) async throws -> WeddingEvent
    func updateEvent(id: UUID, patch: EventPatch) async throws -> WeddingEvent
    func deleteEvent(id: UUID) async throws
    func dayOfItems(weddingID: UUID) async throws -> [DayOfItem]
    func createDayOfItem(_ draft: DayOfItemDraft, weddingID: UUID) async throws -> DayOfItem
    func updateDayOfItem(id: UUID, patch: DayOfItemPatch) async throws -> DayOfItem
    func deleteDayOfItem(id: UUID) async throws
}
