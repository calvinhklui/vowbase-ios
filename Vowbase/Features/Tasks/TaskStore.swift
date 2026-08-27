import Foundation
import Observation

@MainActor
@Observable
final class TaskStore {
    private let repository: (any TaskRepository)?
    private let usesFixtures: Bool

    var tasks: [WeddingTask]
    var isLoading = false
    var errorMessage: String?
    var mutatingTaskIDs = Set<UUID>()

    init(repository: (any TaskRepository)? = nil, fixtures: [WeddingTask] = []) {
        self.repository = repository
        self.usesFixtures = repository == nil && !fixtures.isEmpty
        self.tasks = fixtures
    }

    func load(weddingID: UUID) async {
        guard let repository else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            tasks = try await repository.tasks(weddingID: weddingID)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = userFacingMessage(for: error, fallback: "We couldn't load tasks. Refresh and try again.")
        }
    }

    @discardableResult
    func create(_ draft: TaskDraft, weddingID: UUID) async -> Bool {
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "A task needs a title."
            return false
        }

        errorMessage = nil
        do {
            let created: WeddingTask
            if let repository {
                created = try await repository.createTask(
                    TaskDraft(
                        title: trimmedTitle,
                        description: draft.description?.nilIfBlank,
                        status: draft.status,
                        priority: draft.priority,
                        ownerUserID: draft.ownerUserID,
                        ownerLabel: draft.ownerLabel?.nilIfBlank,
                        dueDate: draft.dueDate
                    ),
                    weddingID: weddingID
                )
            } else {
                created = WeddingTask(
                    id: UUID(),
                    weddingID: weddingID,
                    title: trimmedTitle,
                    description: draft.description?.nilIfBlank,
                    status: draft.status,
                    priority: draft.priority,
                    ownerUserID: draft.ownerUserID,
                    ownerLabel: draft.ownerLabel?.nilIfBlank,
                    dueDate: draft.dueDate,
                    completedAt: nil,
                    createdAt: Date()
                )
            }
            tasks.append(created)
            sortTasks()
            return true
        } catch {
            errorMessage = userFacingMessage(for: error, fallback: "We couldn't create that task. Try again.")
            return false
        }
    }

    @discardableResult
    func update(
        task: WeddingTask,
        title: String,
        description: String,
        status: WeddingTaskStatus,
        priority: WeddingTaskPriority,
        ownerLabel: String,
        dueDate: String?
    ) async -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "A task needs a title."
            return false
        }

        mutatingTaskIDs.insert(task.id)
        errorMessage = nil
        defer { mutatingTaskIDs.remove(task.id) }

        let patch = TaskPatch(
            title: trimmedTitle == task.title ? nil : trimmedTitle,
            description: patchValue(description, current: task.description),
            status: status == task.effectiveStatus ? .unchanged : .value(status),
            priority: priority == (task.priority ?? .medium) ? .unchanged : .value(priority),
            ownerLabel: patchValue(ownerLabel, current: task.ownerLabel),
            dueDate: dueDate == task.dueDate ? .unchanged : (dueDate.map(NullablePatch.value) ?? .null)
        )

        guard !patch.isEmpty else { return true }

        do {
            let updated: WeddingTask
            if let repository {
                updated = try await repository.updateTask(id: task.id, patch: patch)
            } else {
                updated = WeddingTask(
                    id: task.id,
                    weddingID: task.weddingID,
                    title: trimmedTitle,
                    description: description.nilIfBlank,
                    status: status,
                    priority: priority,
                    ownerUserID: task.ownerUserID,
                    ownerLabel: ownerLabel.nilIfBlank,
                    dueDate: dueDate,
                    completedAt: task.completedAt,
                    createdAt: task.createdAt
                )
            }
            replace(updated)
            return true
        } catch {
            errorMessage = userFacingMessage(for: error, fallback: "We couldn't save that task. Try again.")
            return false
        }
    }

    @discardableResult
    func setStatus(_ status: WeddingTaskStatus, for task: WeddingTask) async -> Bool {
        guard task.effectiveStatus != status else { return true }

        mutatingTaskIDs.insert(task.id)
        errorMessage = nil
        defer { mutatingTaskIDs.remove(task.id) }

        do {
            let updated: WeddingTask
            if let repository {
                updated = try await repository.updateTask(id: task.id, patch: TaskPatch(status: .value(status)))
            } else {
                updated = WeddingTask(
                    id: task.id,
                    weddingID: task.weddingID,
                    title: task.title,
                    description: task.description,
                    status: status,
                    priority: task.priority,
                    ownerUserID: task.ownerUserID,
                    ownerLabel: task.ownerLabel,
                    dueDate: task.dueDate,
                    completedAt: task.completedAt,
                    createdAt: task.createdAt
                )
            }
            replace(updated)
            return true
        } catch {
            errorMessage = userFacingMessage(for: error, fallback: "We couldn't update that task. Try again.")
            return false
        }
    }

    @discardableResult
    func delete(_ task: WeddingTask) async -> Bool {
        mutatingTaskIDs.insert(task.id)
        errorMessage = nil
        defer { mutatingTaskIDs.remove(task.id) }

        do {
            if let repository {
                try await repository.deleteTask(id: task.id)
            } else if !usesFixtures {
                return false
            }
            tasks.removeAll { $0.id == task.id }
            return true
        } catch {
            errorMessage = userFacingMessage(for: error, fallback: "We couldn't delete that task. Try again.")
            return false
        }
    }

    private func patchValue(_ proposed: String, current: String?) -> NullablePatch<String> {
        let normalized = proposed.nilIfBlank
        guard normalized != current else { return .unchanged }
        return normalized.map(NullablePatch.value) ?? .null
    }

    private func replace(_ task: WeddingTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
        sortTasks()
    }

    private func sortTasks() {
        tasks.sort {
            switch ($0.dueDate, $1.dueDate) {
            case let (left?, right?): return left < right
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return $0.createdAt < $1.createdAt
            }
        }
    }

    private func userFacingMessage(for error: Error, fallback: String) -> String {
        switch error as? BackendError {
        case .forbidden:
            "You don’t have permission to make that change."
        case .networkUnavailable:
            "Vowbase couldn’t reach the server. Check your connection and try again."
        case .authenticationRequired:
            "Your session has ended. Please sign in again."
        default:
            fallback
        }
    }
}

extension TaskStore {
    static func testingWorkspace(weddingID: UUID) -> TaskStore {
        let calendar = Calendar.current
        let now = Date()
        func date(_ days: Int) -> String {
            TaskDueDateFormatter.string(from: calendar.date(byAdding: .day, value: days, to: now) ?? now)
        }

        return TaskStore(fixtures: [
            WeddingTask(id: UUID(), weddingID: weddingID, title: "Confirm ceremony readings", description: "Share the final order with the officiant.", status: .todo, priority: .high, ownerUserID: nil, ownerLabel: "Calvin", dueDate: date(0), createdAt: now),
            WeddingTask(id: UUID(), weddingID: weddingID, title: "Review florist proposal", description: nil, status: .inProgress, priority: .medium, ownerUserID: nil, ownerLabel: "Avery", dueDate: date(3), createdAt: now),
            WeddingTask(id: UUID(), weddingID: weddingID, title: "Choose welcome-bag treats", description: nil, status: .backlog, priority: .low, ownerUserID: nil, ownerLabel: nil, dueDate: nil, createdAt: now),
            WeddingTask(id: UUID(), weddingID: weddingID, title: "Send catering headcount", description: nil, status: .blocked, priority: .urgent, ownerUserID: nil, ownerLabel: "Avery", dueDate: date(-1), createdAt: now),
            WeddingTask(id: UUID(), weddingID: weddingID, title: "Book rehearsal dinner", description: nil, status: .done, priority: .medium, ownerUserID: nil, ownerLabel: nil, dueDate: date(-4), createdAt: now)
        ])
    }
}

enum TaskDueDateFormatter {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func date(from value: String) -> Date? { formatter.date(from: value) }
    static func string(from date: Date) -> String { formatter.string(from: date) }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
