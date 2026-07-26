import Foundation
import Testing
@testable import Vowbase

@Suite("App configuration")
struct AppConfigurationTests {
    private static let validValues = [
        "SUPABASE_URL": "https://supabase.example.invalid",
        "SUPABASE_PUBLISHABLE_KEY": "publishable-key",
        "VOWBASE_API_URL": "https://api.vowbase.example/v1",
        "CONFIGURATION": "Release",
    ]

    @Test("accepts valid HTTPS values")
    func acceptsValidHTTPSValues() throws {
        let configuration = try AppConfiguration(values: Self.validValues)

        #expect(configuration.supabaseURL.absoluteString == "https://supabase.example.invalid")
        #expect(configuration.supabasePublishableKey == "publishable-key")
        #expect(configuration.apiBaseURL.absoluteString == "https://api.vowbase.example/v1")
    }

    @Test("trims values while preserving URL ports and trailing paths")
    func trimsAndPreservesNormalizedURLs() throws {
        var values = Self.validValues
        values["SUPABASE_URL"] = "  https://supabase.example.invalid:8443/rest/v1/  \n"
        values["SUPABASE_PUBLISHABLE_KEY"] = " \n email-like@example.com \t"
        values["VOWBASE_API_URL"] = "\nhttps://api.vowbase.example:9443/v2/\t"
        values["CONFIGURATION"] = " Release\n"

        let configuration = try AppConfiguration(values: values)

        #expect(configuration.supabaseURL.absoluteString == "https://supabase.example.invalid:8443/rest/v1/")
        #expect(configuration.supabasePublishableKey == "email-like@example.com")
        #expect(configuration.apiBaseURL.absoluteString == "https://api.vowbase.example:9443/v2/")
    }

    @Test(
        "reports each missing required value",
        arguments: [
            "SUPABASE_URL",
            "SUPABASE_PUBLISHABLE_KEY",
            "VOWBASE_API_URL",
            "CONFIGURATION",
        ]
    )
    func reportsMissingRequiredValue(key: String) {
        var values = Self.validValues
        values.removeValue(forKey: key)

        #expect(throws: AppConfiguration.Error.missing(key)) {
            try AppConfiguration(values: values)
        }
    }

    @Test(
        "treats empty and unexpanded values as missing",
        arguments: [
            ("SUPABASE_URL", "   \n"),
            ("SUPABASE_PUBLISHABLE_KEY", "$(LOCAL_SUPABASE_PUBLISHABLE_KEY)"),
            ("VOWBASE_API_URL", "$(VOWBASE_API_URL)"),
            ("CONFIGURATION", "$(CONFIGURATION)"),
        ]
    )
    func rejectsEmptyAndUnexpandedValues(key: String, value: String) {
        var values = Self.validValues
        values[key] = value

        #expect(throws: AppConfiguration.Error.missing(key)) {
            try AppConfiguration(values: values)
        }
    }

    @Test(
        "rejects invalid and non-absolute URLs",
        arguments: [
            ("SUPABASE_URL", "not a url"),
            ("SUPABASE_URL", "/relative/path"),
            ("VOWBASE_API_URL", "https:///missing-host"),
        ]
    )
    func rejectsInvalidURLs(key: String, value: String) {
        var values = Self.validValues
        values[key] = value

        #expect(throws: AppConfiguration.Error.invalidURL(key)) {
            try AppConfiguration(values: values)
        }
    }

    @Test(
        "rejects insecure non-loopback URLs in Debug",
        arguments: ["http://api.vowbase.example", "ftp://api.vowbase.example"]
    )
    func rejectsInsecureNonLoopback(value: String) {
        var values = Self.validValues
        values["CONFIGURATION"] = "Debug"
        values["VOWBASE_API_URL"] = value

        #expect(throws: AppConfiguration.Error.invalidURL("VOWBASE_API_URL")) {
            try AppConfiguration(values: values)
        }
    }

    @Test(
        "accepts HTTP loopback URLs with ports in Debug",
        arguments: [
            "http://localhost:54321/api/",
            "http://127.0.0.1:54321/api/",
            "http://[::1]:54321/api/",
        ]
    )
    func acceptsDebugLoopback(value: String) throws {
        var values = Self.validValues
        values["CONFIGURATION"] = "Debug"
        values["SUPABASE_URL"] = value
        values["VOWBASE_API_URL"] = value

        let configuration = try AppConfiguration(values: values)

        #expect(configuration.supabaseURL.absoluteString == value)
        #expect(configuration.apiBaseURL.absoluteString == value)
    }

    @Test(
        "rejects loopback URLs in Release",
        arguments: [
            "http://localhost:54321",
            "http://127.0.0.1:54321",
            "http://[::1]:54321",
            "https://localhost:54321",
            "https://127.0.0.1:54321",
            "https://[::1]:54321",
        ]
    )
    func rejectsReleaseLoopback(value: String) {
        var values = Self.validValues
        values["VOWBASE_API_URL"] = value

        #expect(throws: AppConfiguration.Error.invalidURL("VOWBASE_API_URL")) {
            try AppConfiguration(values: values)
        }
    }

    @Test("treats the publishable key as an opaque nonempty value")
    func acceptsOpaquePublishableKey() throws {
        var values = Self.validValues
        values["SUPABASE_PUBLISHABLE_KEY"] = "person@example.com"

        let configuration = try AppConfiguration(values: values)

        #expect(configuration.supabasePublishableKey == "person@example.com")
    }

    @Test("loads values from bundle Info.plist keys")
    func loadsLiveValuesFromBundle() throws {
        let bundle = try temporaryBundle(info: [
            "SUPABASE_URL": " https://supabase.example.invalid ",
            "SUPABASE_PUBLISHABLE_KEY": " bundle-key ",
            "VOWBASE_API_URL": " https://api.vowbase.example/v1 ",
            "VOWBASE_BUILD_CONFIGURATION": " Release ",
        ])

        let configuration = try AppConfiguration.live(bundle: bundle)

        #expect(configuration.supabaseURL.absoluteString == "https://supabase.example.invalid")
        #expect(configuration.supabasePublishableKey == "bundle-key")
        #expect(configuration.apiBaseURL.absoluteString == "https://api.vowbase.example/v1")
    }

    @Test(
        "reports each missing bundle Info.plist key",
        arguments: [
            "SUPABASE_URL",
            "SUPABASE_PUBLISHABLE_KEY",
            "VOWBASE_API_URL",
            "VOWBASE_BUILD_CONFIGURATION",
        ]
    )
    func reportsMissingBundleKey(key: String) throws {
        var info = [
            "SUPABASE_URL": "https://supabase.example.invalid",
            "SUPABASE_PUBLISHABLE_KEY": "bundle-key",
            "VOWBASE_API_URL": "https://api.vowbase.example/v1",
            "VOWBASE_BUILD_CONFIGURATION": "Release",
        ]
        info.removeValue(forKey: key)
        let bundle = try temporaryBundle(info: info)

        #expect(throws: AppConfiguration.Error.missing(key)) {
            try AppConfiguration.live(bundle: bundle)
        }
    }

    private func temporaryBundle(info: [String: String]) throws -> Bundle {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("bundle")
        try FileManager.default.createDirectory(
            at: bundleURL,
            withIntermediateDirectories: true
        )
        let infoURL = bundleURL.appendingPathComponent("Info.plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try data.write(to: infoURL, options: .atomic)
        #expect(Bundle(url: bundleURL) != nil)
        return try #require(Bundle(url: bundleURL))
    }
}
