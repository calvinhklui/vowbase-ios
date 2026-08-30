import Testing
@testable import Vowbase

@Test func testHarnessRuns() {
    #expect(true)
}

@Test("Navigation opens on Timeline by default")
@MainActor
func navigationDefaultsToTimeline() {
    #expect(AppNavigationModel().selectedLens == .timeline)
}

@Test("workspace title derives a possessive wedding title from couple names")
func workspaceTitleDerivation() {
    #expect(WeddingTitleFormatter.string(coupleNames: "Andey & Calvin", weddingName: "Ignored Wedding") == "Andey & Calvin’s Wedding")
    #expect(WeddingTitleFormatter.string(coupleNames: "Andey & Calvin’s Wedding", weddingName: "Ignored Wedding") == "Andey & Calvin’s Wedding")
    #expect(WeddingTitleFormatter.string(coupleNames: "Andey & Calvin Wedding", weddingName: "Ignored Wedding") == "Andey & Calvin Wedding")
    #expect(WeddingTitleFormatter.string(coupleNames: "Andey & Calvin’s", weddingName: "Ignored Wedding") == "Andey & Calvin’s Wedding")
}

@Test("workspace title falls back when couple names are blank")
func workspaceTitleFallbacks() {
    #expect(WeddingTitleFormatter.string(coupleNames: " \n", weddingName: "Calvin Wedding") == "Calvin Wedding")
    #expect(WeddingTitleFormatter.string(coupleNames: nil, weddingName: "  ") == "Your wedding")
}
