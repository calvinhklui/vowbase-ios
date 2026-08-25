import Testing
@testable import Vowbase

@Suite("Console detents")
struct ConsoleDetentTests {
    @Test("Focused-lens default resolves to sixty percent of the screen")
    func focusedLensDefaultHeight() {
        #expect(ConsoleDetent.half.pointHeight(in: 1_000) == 600)
    }
}
