import Foundation
protocol TaskRepository: Sendable { func tasks(weddingID: UUID) async throws -> [WeddingTask]; func createTask(_ draft: TaskDraft, weddingID: UUID) async throws -> WeddingTask; func updateTask(id: UUID, patch: TaskPatch) async throws -> WeddingTask; func deleteTask(id: UUID) async throws }
