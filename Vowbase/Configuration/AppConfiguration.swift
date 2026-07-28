import Foundation
import Darwin

struct AppConfiguration: Sendable {
    enum Error: Swift.Error, Equatable, Sendable {
        case missing(String)
        case invalidURL(String)
    }

    #if DEBUG
    enum TransportPolicy: Equatable, Sendable {
        case debug
        case release
    }
    #endif

    let supabaseURL: URL
    let supabasePublishableKey: String
    let apiBaseURL: URL

    init(values: [String: String]) throws {
        try self.init(
            values: values,
            allowsInsecureLoopback: Self.compiledAllowsInsecureLoopback
        )
    }

    #if DEBUG
    init(values: [String: String], transportPolicy: TransportPolicy) throws {
        try self.init(
            values: values,
            allowsInsecureLoopback: transportPolicy == .debug
        )
    }
    #endif

    private init(
        values: [String: String],
        allowsInsecureLoopback: Bool
    ) throws {
        _ = try Self.requiredValue(for: "CONFIGURATION", in: values)

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
        try load(
            bundle: bundle,
            allowsInsecureLoopback: Self.compiledAllowsInsecureLoopback
        )
    }

    #if DEBUG
    static func live(
        bundle: Bundle,
        transportPolicy: TransportPolicy
    ) throws -> AppConfiguration {
        try load(
            bundle: bundle,
            allowsInsecureLoopback: transportPolicy == .debug
        )
    }
    #endif

    private static func load(
        bundle: Bundle,
        allowsInsecureLoopback: Bool
    ) throws -> AppConfiguration {
        let info = bundle.infoDictionary ?? [:]
        var values = [String: String]()
        for key in ["SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "VOWBASE_API_URL"] {
            values[key] = try infoValue(for: key, in: info)
        }
        values["CONFIGURATION"] = try infoValue(
            for: "VOWBASE_BUILD_CONFIGURATION",
            in: info
        )
        return try AppConfiguration(
            values: values,
            allowsInsecureLoopback: allowsInsecureLoopback
        )
    }

    private static var compiledAllowsInsecureLoopback: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private static func infoValue(for key: String, in info: [String: Any]) throws -> String {
        guard let value = info[key] as? String else {
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

        guard let isLoopback = LoopbackHostClassifier.isLoopback(host) else {
            throw Error.invalidURL(key)
        }

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

private enum LoopbackHostClassifier {
    static func isLoopback(_ rawHost: String) -> Bool? {
        var host = rawHost.lowercased()
        while host.hasSuffix(".") {
            host.removeLast()
        }

        let hasOpeningBracket = host.hasPrefix("[")
        let hasClosingBracket = host.hasSuffix("]")
        guard hasOpeningBracket == hasClosingBracket else {
            return nil
        }
        if hasOpeningBracket {
            host.removeFirst()
            host.removeLast()
        }

        let zoneDelimiters = host.indices.filter { host[$0] == "%" }
        if !zoneDelimiters.isEmpty {
            guard zoneDelimiters.count == 1,
                  host.contains(":"),
                  let delimiter = zoneDelimiters.first else {
                return nil
            }
            let zoneStart = host.index(after: delimiter)
            let address = host[..<delimiter]
            let zone = host[zoneStart...]
            guard !address.isEmpty,
                  !zone.isEmpty,
                  zone.utf8.allSatisfy(isValidZoneCharacter) else {
                return nil
            }
            host = String(address)
        }

        if host == "localhost" || host.hasSuffix(".localhost") {
            return true
        }
        if let isLoopback = ipv4LoopbackStatus(host) {
            return isLoopback
        }
        if host.contains(":") {
            if let isLoopback = ipv6LoopbackStatus(host) {
                return isLoopback
            }
            if let isLoopback = legacyMappedIPv4LoopbackStatus(host) {
                return isLoopback
            }
            return nil
        }
        return false
    }

    private static func isValidZoneCharacter(_ byte: UInt8) -> Bool {
        (byte >= 48 && byte <= 57)
            || (byte >= 65 && byte <= 90)
            || (byte >= 97 && byte <= 122)
            || byte == 46
            || byte == 95
            || byte == 45
    }

    private static func ipv4LoopbackStatus(_ host: String) -> Bool? {
        var address = in_addr()
        let parsed = host.withCString { inet_aton($0, &address) }
        guard parsed == 1 else {
            return nil
        }
        return withUnsafeBytes(of: &address) { bytes in
            bytes.first == 127
        }
    }

    private static func ipv6LoopbackStatus(_ host: String) -> Bool? {
        var address = in6_addr()
        let parsed = host.withCString { inet_pton(AF_INET6, $0, &address) }
        guard parsed == 1 else {
            return nil
        }

        return withUnsafeBytes(of: &address) { rawBytes in
            let bytes = Array(rawBytes)
            let isIPv6Loopback = bytes.dropLast().allSatisfy { $0 == 0 }
                && bytes.last == 1
            let isIPv4MappedLoopback = bytes.prefix(10).allSatisfy { $0 == 0 }
                && bytes[10] == 0xff
                && bytes[11] == 0xff
                && bytes[12] == 127
            return isIPv6Loopback || isIPv4MappedLoopback
        }
    }

    private static func legacyMappedIPv4LoopbackStatus(_ host: String) -> Bool? {
        for mappedPrefix in ["::ffff:", "0:0:0:0:0:ffff:"]
        where host.hasPrefix(mappedPrefix) {
            let ipv4 = String(host.dropFirst(mappedPrefix.count))
            return ipv4LoopbackStatus(ipv4)
        }
        return nil
    }
}
