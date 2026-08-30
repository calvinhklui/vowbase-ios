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
