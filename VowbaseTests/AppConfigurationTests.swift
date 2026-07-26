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
            try AppConfiguration(values: values, transportPolicy: .debug)
        }
    }

    @Test(
        "accepts canonical and legacy HTTP loopback URLs in Debug policy",
        arguments: [
            "http://localhost:54321/api/",
            "http://LOCALHOST.:54321/api/",
            "http://service.localhost:54321/api/",
            "http://service.LOCALHOST.:54321/api/",
            "http://127.0.0.1:54321/api/",
            "http://127.42.5.9:54321/api/",
            "http://127.255.255.255.:54321/api/",
            "http://127.1:54321/api/",
            "http://2130706433:54321/api/",
            "http://0177.0.0.1:54321/api/",
            "http://0x7f000001:54321/api/",
            "http://0x7f.1:54321/api/",
            "http://[::1]:54321/api/",
            "http://[0:0:0:0:0:0:0:1]:54321/api/",
            "http://[::ffff:127.0.0.1]:54321/api/",
            "http://[::ffff:127.42.5.9]:54321/api/",
            "http://[::ffff:127.1]:54321/api/",
            "http://[::ffff:2130706433]:54321/api/",
            "http://[::ffff:0x7f000001]:54321/api/",
        ]
    )
    func acceptsDebugLoopback(value: String) throws {
        var values = Self.validValues
        values["CONFIGURATION"] = "Release"
        values["SUPABASE_URL"] = value
        values["VOWBASE_API_URL"] = value

        let configuration = try AppConfiguration(values: values, transportPolicy: .debug)

        #expect(configuration.supabaseURL.absoluteString == value)
        #expect(configuration.apiBaseURL.absoluteString == value)
    }

    @Test(
        "rejects canonical and legacy loopback URLs in Release policy",
        arguments: [
            "localhost",
            "LOCALHOST.",
            "service.localhost",
            "service.LOCALHOST.",
            "127.0.0.1",
            "127.255.255.255",
            "127.42.5.9.",
            "127.1",
            "2130706433",
            "0177.0.0.1",
            "0x7f000001",
            "0x7f.1",
            "[::1]",
            "[0:0:0:0:0:0:0:1]",
            "[::ffff:127.0.0.1]",
            "[::ffff:127.42.5.9]",
            "[::ffff:127.1]",
            "[::ffff:2130706433]",
            "[::ffff:0x7f000001]",
        ]
    )
    func rejectsReleaseLoopback(host: String) {
        var values = Self.validValues
        values["CONFIGURATION"] = "Debug"

        for scheme in ["http", "https"] {
            values["VOWBASE_API_URL"] = "\(scheme)://\(host):54321/api"
            #expect(throws: AppConfiguration.Error.invalidURL("VOWBASE_API_URL")) {
                try AppConfiguration(values: values, transportPolicy: .release)
            }
        }
    }

    @Test(
        "accepts non-loopback HTTPS hosts in Release policy",
        arguments: [
            "https://localhost.example:443",
            "https://notlocalhost:443",
            "https://128.0.0.1:443",
            "https://[::ffff:128.0.0.1]:443",
        ]
    )
    func acceptsNonLoopbackHTTPS(value: String) throws {
        var values = Self.validValues
        values["VOWBASE_API_URL"] = value

        let configuration = try AppConfiguration(values: values, transportPolicy: .release)

        #expect(configuration.apiBaseURL.absoluteString == value)
    }

    @Test("a Debug marker cannot weaken Release transport policy")
    func debugMarkerCannotWeakenReleasePolicy() {
        var values = Self.validValues
        values["CONFIGURATION"] = "Debug"
        values["VOWBASE_API_URL"] = "http://127.1:8080"

        #expect(throws: AppConfiguration.Error.invalidURL("VOWBASE_API_URL")) {
            try AppConfiguration(values: values, transportPolicy: .release)
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

    @Test("live parsing cannot be weakened by a Debug plist marker")
    func liveDebugMarkerCannotWeakenReleasePolicy() throws {
        let bundle = try temporaryBundle(info: [
            "SUPABASE_URL": "https://supabase.example.invalid",
            "SUPABASE_PUBLISHABLE_KEY": "bundle-key",
            "VOWBASE_API_URL": "http://127.1:8080",
            "VOWBASE_BUILD_CONFIGURATION": "Debug",
        ])

        #expect(throws: AppConfiguration.Error.invalidURL("VOWBASE_API_URL")) {
            try AppConfiguration.live(bundle: bundle, transportPolicy: .release)
        }
    }

    @Test("live parsing ignores localized InfoPlist.strings overrides")
    func liveUsesRawInfoDictionary() throws {
        let bundle = try temporaryBundle(
            info: [
                "SUPABASE_URL": "https://supabase.example.invalid",
                "SUPABASE_PUBLISHABLE_KEY": "raw-bundle-key",
                "VOWBASE_API_URL": "https://api.vowbase.example/v1",
                "VOWBASE_BUILD_CONFIGURATION": "Release",
            ],
            localizedOverrides: [
                "SUPABASE_URL": "https://localized.example.invalid",
                "SUPABASE_PUBLISHABLE_KEY": "localized-key",
                "VOWBASE_API_URL": "https://localized-api.example.invalid",
                "VOWBASE_BUILD_CONFIGURATION": "Debug",
            ]
        )

        #expect(bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String == "https://localized.example.invalid")
        #expect(bundle.infoDictionary?["SUPABASE_URL"] as? String == "https://supabase.example.invalid")

        let configuration = try AppConfiguration.live(bundle: bundle, transportPolicy: .release)

        #expect(configuration.supabaseURL.absoluteString == "https://supabase.example.invalid")
        #expect(configuration.supabasePublishableKey == "raw-bundle-key")
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
        var info: [String: Any] = [
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

    private func temporaryBundle(
        info: [String: Any],
        localizedOverrides: [String: String] = [:]
    ) throws -> Bundle {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("bundle")
        try FileManager.default.createDirectory(
            at: bundleURL,
            withIntermediateDirectories: true
        )
        var bundleInfo = info
        bundleInfo["CFBundleDevelopmentRegion"] = "en"
        bundleInfo["CFBundleIdentifier"] = "com.vowbase.configuration-tests.\(UUID().uuidString)"
        bundleInfo["CFBundleLocalizations"] = ["en"]
        let infoURL = bundleURL.appendingPathComponent("Info.plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: bundleInfo,
            format: .xml,
            options: 0
        )
        try data.write(to: infoURL, options: .atomic)

        if !localizedOverrides.isEmpty {
            let localizationURL = bundleURL.appendingPathComponent("en.lproj")
            try FileManager.default.createDirectory(
                at: localizationURL,
                withIntermediateDirectories: true
            )
            let localizedData = try PropertyListSerialization.data(
                fromPropertyList: localizedOverrides,
                format: .binary,
                options: 0
            )
            try localizedData.write(
                to: localizationURL.appendingPathComponent("InfoPlist.strings"),
                options: .atomic
            )
        }

        #expect(Bundle(url: bundleURL) != nil)
        return try #require(Bundle(url: bundleURL))
    }
}
