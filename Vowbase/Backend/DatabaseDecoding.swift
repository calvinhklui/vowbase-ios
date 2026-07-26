import Foundation

enum DatabaseDecoding {
    static var decoder: JSONDecoder {
        makeDecoder()
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom(ISO8601DateDecoding.decode)
        return decoder
    }
}

enum ISO8601DateDecoding {
    static func decode(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        if let date = formatter(includingFractionalSeconds: true).date(from: value)
            ?? formatter(includingFractionalSeconds: false).date(from: value) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected an ISO-8601 timestamp."
        )
    }

    private static func formatter(includingFractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = includingFractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }
}
