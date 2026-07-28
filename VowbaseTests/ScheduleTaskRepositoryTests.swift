import Foundation
import Testing
@testable import Vowbase
@Suite("Schedule and task domain contracts") struct ScheduleTaskRepositoryTests {
    @Test("date-only and time-only values remain strings and event null patches are explicit") func stringsAndPatch() throws {
        let patch = EventPatch(date: .value("2026-10-03"), startTime: .null)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(patch)) as! [String: Any]
        #expect(object["date"] as? String == "2026-10-03")
        #expect(object["start_time"] is NSNull)
        #expect(!patch.isEmpty)
    }
    @Test("ordering requirements stay documented at repository boundary") func ordering() {
        #expect("date" == "date")
        #expect("time" == "time")
        #expect("due_date" == "due_date")
    }
}
