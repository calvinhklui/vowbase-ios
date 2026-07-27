import Foundation

struct Coordinate: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
}

struct GeocodeResult: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let displayName: String
    let city: String?
    let region: String?
    let country: String?
    let provider: String
    let providerResultId: String?
}

struct TravelDestination: Codable, Equatable, Sendable {
    let id: String
    let latitude: Double
    let longitude: Double
}

enum TravelTimeSource: String, Codable, Equatable, Sendable {
    case cache
    case googleRoutes = "google_routes"
    case estimate
}

enum TravelMode: String, Codable, Equatable, Sendable {
    case drive
    case flight
}

struct TravelTime: Codable, Equatable, Sendable {
    let id: String
    let latitude: Double
    let longitude: Double
    let durationSeconds: Int
    let distanceMeters: Int
    let source: TravelTimeSource
    let estimated: Bool
    let travelMode: TravelMode
}
