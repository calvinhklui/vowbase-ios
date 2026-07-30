import Foundation
import Testing
@testable import Vowbase

struct TaskModelsTests {
    @Test func patchEncodesOnlyChangedFieldsAndExplicitNulls() throws {
        let patch = TaskPatch(
            title: "Confirm florist",
            description: .null,
            status: .value(.inProgress)
        )

        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(patch)) as? [String: Any]

        #expect(object?["title"] as? String == "Confirm florist")
        #expect(object?["description"] is NSNull)
        #expect(object?["status"] as? String == "in_progress")
        #expect(object?["priority"] == nil)
        #expect(object?["owner_label"] == nil)
    }

    @Test func defaultsKeepNewTasksActionable() {
        let draft = TaskDraft(title: "Send rehearsal invite")

        #expect(draft.status == .todo)
        #expect(draft.priority == .medium)
    }
}
