import Foundation

final class APIVenueResearchRepository: VenueResearchRepository, @unchecked Sendable {
    private let api: any VowbaseAPIClientProtocol
    private let makeIdempotencyKey: @Sendable () -> String

    init(
        api: any VowbaseAPIClientProtocol,
        makeIdempotencyKey: @escaping @Sendable () -> String = {
            UUID().uuidString.lowercased()
        }
    ) {
        self.api = api
        self.makeIdempotencyKey = makeIdempotencyKey
    }

    func start(
        _ source: VenueResearchSource,
        venueID: UUID
    ) async throws -> VenueResearchStartResult {
        let body = try encode(StartResearchRequest(venueID: venueID, source: source))
        return try await api.send(
            APIRequest(
                method: .post,
                path: "v1/venue-research/start",
                body: body,
                headers: ["Idempotency-Key": makeIdempotencyKey()]
            )
        )
    }

    func run(id: UUID) async throws -> VenueResearchRun {
        let response: VenueResearchResponse = try await api.send(
            APIRequest(method: .get, path: "v1/venue-research/\(id.uuidString.lowercased())")
        )
        return VenueResearchRun(
            id: response.run.id,
            venueID: response.run.venueID,
            weddingID: response.run.weddingID,
            sourceType: response.run.sourceType,
            sourceURL: response.run.sourceURL,
            status: response.run.status,
            errorCode: response.run.errorCode,
            ocrUsed: response.run.ocrUsed,
            createdAt: response.run.createdAt,
            updatedAt: response.run.updatedAt,
            completedAt: response.run.completedAt,
            suggestions: response.suggestions,
            facts: response.facts
        )
    }

    func apply(
        runID: UUID,
        suggestionIDs: [UUID],
        factIDs: [UUID]
    ) async throws -> ApplyResearchResult {
        let body = try encode(
            ApplyResearchRequest(suggestionIDs: suggestionIDs, factIDs: factIDs)
        )
        return try await api.send(
            APIRequest(
                method: .post,
                path: "v1/venue-research/\(runID.uuidString.lowercased())/apply",
                body: body
            )
        )
    }

    func cancel(runID: UUID) async throws {
        let _: CancelResearchResponse = try await api.send(
            APIRequest(
                method: .post,
                path: "v1/venue-research/\(runID.uuidString.lowercased())/cancel"
            )
        )
    }

    private func encode<Body: Encodable>(_ body: Body) throws -> Data {
        do {
            return try JSONEncoder().encode(body)
        } catch {
            throw BackendError.invalidResponse
        }
    }
}

private struct StartResearchRequest: Encodable {
    let venueID: UUID
    let source: String
    let url: String?
    let filePath: String?
    let pastedText: String?

    init(venueID: UUID, source: VenueResearchSource) {
        self.venueID = venueID
        switch source {
        case let .website(url):
            self.source = "website"
            self.url = url.absoluteString
            self.filePath = nil
            self.pastedText = nil
        case let .file(path):
            self.source = "file"
            self.url = nil
            self.filePath = path
            self.pastedText = nil
        case let .text(value):
            self.source = "text"
            self.url = nil
            self.filePath = nil
            self.pastedText = value
        }
    }

    private enum CodingKeys: String, CodingKey {
        case venueID = "venueId"
        case source
        case url
        case filePath
        case pastedText
    }
}

private struct VenueResearchResponse: Decodable, Sendable {
    let run: VenueResearchRun
    let suggestions: [VenueResearchSuggestion]
    let facts: [VenueResearchFact]
}

private struct ApplyResearchRequest: Encodable {
    let suggestionIDs: [UUID]
    let factIDs: [UUID]

    private enum CodingKeys: String, CodingKey {
        case suggestionIDs = "suggestionIds"
        case factIDs = "factIds"
    }
}

private struct CancelResearchResponse: Decodable, Sendable {
    let ok: Bool
}
