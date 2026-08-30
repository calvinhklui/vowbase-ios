import Foundation
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

@Test("record deep links parse only canonical Vowbase detail URLs")
func recordDeepLinkParsing() {
    let weddingID = UUID(uuidString: "79B779C0-7E5B-4F9D-94F3-00C13DCEE5B4")!
    let recordID = UUID(uuidString: "3BF32EC1-63B3-40F8-A112-1E054FC34E83")!

    #expect(VowbaseDeepLink.parse(URL(string: "https://vowbase.app/app/w/\(weddingID)/venues/\(recordID)")!) == .venue(weddingID: weddingID, venueID: recordID))
    #expect(VowbaseDeepLink.parse(URL(string: "https://vowbase.app/app/w/\(weddingID)/guests/\(recordID)")!) == .guest(weddingID: weddingID, guestID: recordID))
    #expect(VowbaseDeepLink.parse(URL(string: "https://example.com/app/w/\(weddingID)/venues/\(recordID)")!) == nil)
    #expect(VowbaseDeepLink.parse(URL(string: "vowbase://app/w/\(weddingID)/venues/\(recordID)")!) == nil)
}

@Test("record deep links build canonical lowercase URLs")
func recordDeepLinkURLs() {
    let weddingID = UUID(uuidString: "79B779C0-7E5B-4F9D-94F3-00C13DCEE5B4")!
    let recordID = UUID(uuidString: "3BF32EC1-63B3-40F8-A112-1E054FC34E83")!

    #expect(VowbaseDeepLink.guest(weddingID: weddingID, guestID: recordID).url.absoluteString == "https://vowbase.app/app/w/79b779c0-7e5b-4f9d-94f3-00c13dcee5b4/guests/3bf32ec1-63b3-40f8-a112-1e054fc34e83")
}
