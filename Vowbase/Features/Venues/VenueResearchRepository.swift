import Foundation

protocol VenueResearchRepository: Sendable {
    func start(_ source: VenueResearchSource, venueID: UUID) async throws -> VenueResearchStartResult
    func run(id: UUID) async throws -> VenueResearchRun
    func apply(
        runID: UUID,
        suggestionIDs: [UUID],
        factIDs: [UUID]
    ) async throws -> ApplyResearchResult
    func cancel(runID: UUID) async throws
}
