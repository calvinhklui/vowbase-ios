import Foundation

protocol MapWorkflowRepository: Sendable {
    func geocode(query: String) async throws -> [GeocodeResult]
    func reverseGeocode(latitude: Double, longitude: Double) async throws -> [GeocodeResult]
    func travelTimes(
        weddingID: UUID,
        origin: Coordinate,
        destinations: [TravelDestination]
    ) async throws -> [TravelTime]
}
