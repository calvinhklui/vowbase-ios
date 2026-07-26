import Foundation

struct AppConfiguration: Sendable {
    enum Error: Swift.Error, Equatable, Sendable {
        case missing(String)
        case invalidURL(String)
    }

    let supabaseURL: URL
    let supabasePublishableKey: String
    let apiBaseURL: URL

    init(values: [String: String]) throws {
        let configuration = try Self.requiredValue(for: "CONFIGURATION", in: values)
        let allowsInsecureLoopback = configuration.caseInsensitiveCompare("Debug") == .orderedSame

        let supabaseURLValue = try Self.requiredValue(for: "SUPABASE_URL", in: values)
        supabaseURL = try Self.validatedURL(
            supabaseURLValue,
            key: "SUPABASE_URL",
            allowsInsecureLoopback: allowsInsecureLoopback
        )

        supabasePublishableKey = try Self.requiredValue(
            for: "SUPABASE_PUBLISHABLE_KEY",
            in: values
        )

        let apiBaseURLValue = try Self.requiredValue(for: "VOWBASE_API_URL", in: values)
        apiBaseURL = try Self.validatedURL(
            apiBaseURLValue,
            key: "VOWBASE_API_URL",
            allowsInsecureLoopback: allowsInsecureLoopback
        )
    }

    static func live(bundle: Bundle = .main) throws -> AppConfiguration {
        var values = [String: String]()
        for key in ["SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "VOWBASE_API_URL"] {
            values[key] = try bundleValue(for: key, in: bundle)
        }
        values["CONFIGURATION"] = try bundleValue(
            for: "VOWBASE_BUILD_CONFIGURATION",
            in: bundle
        )
        return try AppConfiguration(values: values)
    }

    private static func bundleValue(for key: String, in bundle: Bundle) throws -> String {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else {
            throw Error.missing(key)
        }
        return try requiredValue(for: key, in: [key: value])
    }

    private static func requiredValue(
        for key: String,
        in values: [String: String]
    ) throws -> String {
        guard let rawValue = values[key] else {
            throw Error.missing(key)
        }

        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("$(") else {
            throw Error.missing(key)
        }
        return value
    }

    private static func validatedURL(
        _ value: String,
        key: String,
        allowsInsecureLoopback: Bool
    ) throws -> URL {
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty,
              let url = components.url else {
            throw Error.invalidURL(key)
        }

        let normalizedHost = host
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()
        let isLoopback = normalizedHost == "localhost"
            || normalizedHost == "127.0.0.1"
            || normalizedHost == "::1"

        guard allowsInsecureLoopback || !isLoopback else {
            throw Error.invalidURL(key)
        }
        if scheme == "https" {
            return url
        }

        guard scheme == "http", allowsInsecureLoopback, isLoopback else {
            throw Error.invalidURL(key)
        }
        return url
    }
}
