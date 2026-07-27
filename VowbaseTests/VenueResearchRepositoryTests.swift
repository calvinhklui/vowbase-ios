import Foundation
import Testing
@testable import Vowbase

@Suite("Venue research repository")
struct VenueResearchRepositoryTests {
    @Test("start sends the exact website payload and a unique idempotency header")
    func startsWebsiteResearch() async throws {
        let api = VenueResearchAPIStub(responses: [
            Data("{\"runId\":\"10000000-0000-4000-8000-000000000001\",\"alreadyActive\":false}".utf8),
        ])
        let repository = APIVenueResearchRepository(api: api, makeIdempotencyKey: { "key-123" })
        let venueID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!

        let start = try await repository.start(
            .website(URL(string: "https://venue.example/research")!),
            venueID: venueID
        )

        #expect(start.alreadyActive == false)
        let request = try #require((await api.requests).first)
        #expect(request.path == "v1/venue-research/start")
        #expect(request.method == "POST")
        #expect(request.headers == ["Idempotency-Key": "key-123"])
        let payload = try #require(try requestJSON(request.body) as? [String: Any])
        #expect(payload["venueId"] as? String == venueID.uuidString.uppercased())
        #expect(payload["source"] as? String == "website")
        #expect(payload["url"] as? String == "https://venue.example/research")
        #expect(payload["filePath"] == nil)
        #expect(payload["pastedText"] == nil)
    }

    @Test("text research and polling use the versioned server contracts")
    func startsTextAndPollsRun() async throws {
        let api = VenueResearchAPIStub(responses: [
            Data("{\"runId\":\"10000000-0000-4000-8000-000000000001\",\"alreadyActive\":true}".utf8),
            try fixture("venue-research-run"),
        ])
        let repository = APIVenueResearchRepository(api: api, makeIdempotencyKey: { "key-text" })
        let venueID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
        let runID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!

        let started = try await repository.start(
            .text("This venue has an indoor rain plan."),
            venueID: venueID
        )
        let run = try await repository.run(id: runID)

        #expect(started.alreadyActive)
        #expect(run.id == runID)
        #expect(run.sourceURL?.host == "venue.example")
        #expect(run.suggestions.first?.fieldKey == "capacity_max")
        #expect(run.suggestions.first?.suggestedValue == .number(175))
        #expect(run.facts.first?.topic == "Rain plan")
        let requests = await api.requests
        let textPayload = try #require(try requestJSON(requests[0].body) as? [String: Any])
        #expect(textPayload["source"] as? String == "text")
        #expect(textPayload["pastedText"] as? String == "This venue has an indoor rain plan.")
        #expect(textPayload["url"] == nil)
        #expect(requests[1].path == "v1/venue-research/10000000-0000-4000-8000-000000000001")
        #expect(requests[1].method == "GET")
    }

    @Test("apply and cancel use their exact mutation routes")
    func appliesAndCancels() async throws {
        let api = VenueResearchAPIStub(responses: [
            Data("{\"applied\":1,\"conflicts\":2}".utf8),
            Data("{\"ok\":true}".utf8),
        ])
        let repository = APIVenueResearchRepository(api: api)
        let runID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        let suggestionID = UUID(uuidString: "40000000-0000-4000-8000-000000000001")!
        let factID = UUID(uuidString: "50000000-0000-4000-8000-000000000001")!

        let result = try await repository.apply(
            runID: runID,
            suggestionIDs: [suggestionID],
            factIDs: [factID]
        )
        try await repository.cancel(runID: runID)

        #expect(result == ApplyResearchResult(applied: 1, conflicts: 2))
        let requests = await api.requests
        #expect(requests.map(\.path) == [
            "v1/venue-research/10000000-0000-4000-8000-000000000001/apply",
            "v1/venue-research/10000000-0000-4000-8000-000000000001/cancel",
        ])
        let payload = try #require(try requestJSON(requests[0].body) as? [String: Any])
        #expect(payload["suggestionIds"] as? [String] == [suggestionID.uuidString.uppercased()])
        #expect(payload["factIds"] as? [String] == [factID.uuidString.uppercased()])
        #expect(requests.allSatisfy { $0.method == "POST" })
    }

    @Test("conflict responses propagate without mutation retries")
    func preservesConflict() async throws {
        let expected = BackendError.conflict(message: "Research is not ready.", requestID: "request-1")
        let api = VenueResearchAPIStub(responses: [], error: expected)

        await #expect(throws: expected) {
            _ = try await APIVenueResearchRepository(api: api).apply(
                runID: UUID(),
                suggestionIDs: [],
                factIDs: []
            )
        }
        #expect((await api.requests).count == 1)
    }
}

private actor VenueResearchAPIStub: VowbaseAPIClientProtocol {
    private var responses: [Data]
    private let error: BackendError?
    private(set) var requests = [CapturedVenueResearchRequest]()

    init(responses: [Data], error: BackendError? = nil) {
        self.responses = responses
        self.error = error
    }

    func send<Response: Decodable & Sendable>(_ request: APIRequest<Response>) async throws -> Response {
        requests.append(.init(method: request.method, path: request.path, body: request.body, headers: request.headers))
        if let error { throw error }
        guard !responses.isEmpty else { throw BackendError.invalidResponse }
        return try JSONDecoder().decode(Response.self, from: responses.removeFirst())
    }
}

private struct CapturedVenueResearchRequest: Sendable {
    let method: String
    let path: String
    let body: Data?
    let headers: [String: String]

    init<Response>(method: APIRequest<Response>.Method, path: String, body: Data?, headers: [String: String]) {
        self.method = method.rawValue
        self.path = path
        self.body = body
        self.headers = headers
    }
}

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle(for: VenueResearchFixtureBundle.self).url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
}

private final class VenueResearchFixtureBundle {}

private func requestJSON(_ body: Data?) throws -> Any {
    try JSONSerialization.jsonObject(with: try #require(body))
}
