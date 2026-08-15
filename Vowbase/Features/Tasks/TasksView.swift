import SwiftUI

enum TaskEditorDestination: Identifiable {
    /// `prefillTitle` is how the Overview lens's "Needs you" module promotes
    /// a nudge into a real task (spec §11.3) — the editor opens already
    /// titled, ready for a due date and owner.
    case add(prefillTitle: String? = nil)
    case edit(UUID)

    var id: String {
        switch self {
        case .add(let prefillTitle): "add-\(prefillTitle ?? "blank")"
        case .edit(let id): "edit-\(id.uuidString)"
        }
    }
}

private enum TasksPresentation: String, CaseIterable, Identifiable {
    case list
    case board

    var id: String { rawValue }
    var title: String { self == .list ? "List" : "Board" }
    var systemImage: String { self == .list ? "list.bullet" : "rectangle.split.3x1" }
}

/// The Tasks lens's console content. Canvas-optional (spec §2.1): the
/// console opens at `.full` rather than `.peek` since there's no map
/// selection for a peek rail to caption, and its own header is gone — the
/// shared, selection-aware `ConsoleHeader` covers it now.
@MainActor
struct TasksView: View {
    let store: VowbaseWorkspaceStore
    let taskStore: TaskStore
    @Binding var editor: TaskEditorDestination?

    @State private var presentation: TasksPresentation = .list
    @State private var query = ""
    @State private var showsCompleted = false
    @State private var boardColumnID: String? = WeddingTaskStatus.backlog.rawValue

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    TaskSearchField(query: $query)

                    TaskViewControls(presentation: $presentation, showsCompleted: $showsCompleted)

                if taskStore.isLoading && taskStore.tasks.isEmpty {
                    ProgressView("Loading tasks")
                        .padding(.vertical, 56)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredTasks.isEmpty {
                    ContentUnavailableView {
                        Label(emptyTitle, systemImage: "checklist")
                    } description: {
                        Text(emptyMessage)
                    } actions: {
                        if store.canManageTasks {
                            Button("Add Task") { editor = .add() }
                                .buttonStyle(.borderedProminent)
                                .tint(VowbaseTheme.rose)
                        }
                    }
                    .padding(.vertical, 36)
                    .frame(maxWidth: .infinity)
                } else {
                    taskContent
                }
            }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            .vowbaseScrollClearance()
            .navigationBarHidden(true)
            .refreshable {
                if let weddingID = store.wedding?.id { await taskStore.load(weddingID: weddingID) }
            }
        }
        .task(id: store.wedding?.id) {
            if let weddingID = store.wedding?.id { await taskStore.load(weddingID: weddingID) }
        }
    }

    @ViewBuilder
    private var taskContent: some View {
        switch presentation {
        case .list:
            ForEach(TaskDateBucket.orderedBuckets(for: filteredTasks)) { bucket in
                let tasks = tasks(in: bucket)
                if !tasks.isEmpty {
                    TaskSection(bucket: bucket, tasks: tasks, taskStore: taskStore, canManageTasks: store.canManageTasks) {
                        editor = .edit($0.id)
                        }
                    }
                }
        case .board:
            TaskBoard(tasks: filteredTasks, taskStore: taskStore, canManageTasks: store.canManageTasks, selectedColumnID: $boardColumnID) {
                editor = .edit($0.id)
            }
        }
    }

    private var filteredTasks: [WeddingTask] {
        taskStore.tasks.filter { task in
            let matchesCompletion = showsCompleted || task.effectiveStatus != .done
            guard matchesCompletion else { return false }
            guard !query.isEmpty else { return true }
            return [task.title, task.description, task.ownerLabel]
                .compactMap { $0 }
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(query)
        }
    }

    private func tasks(in bucket: TaskDateBucket) -> [WeddingTask] {
        filteredTasks.filter { bucket.contains($0) }
    }

    private var emptyTitle: String { query.isEmpty ? "No tasks yet" : "No matching tasks" }
    private var emptyMessage: String {
        query.isEmpty ? "Keep the next good decision within reach. Add a task to get started." : "Try a different word or clear your search."
    }
}

private struct TaskSearchField: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(VowbaseTheme.mutedInk)
            TextField("Search tasks", text: $query)
                .textInputAutocapitalization(.sentences)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VowbaseTheme.border, lineWidth: 1))
    }
}

private struct TaskViewControls: View {
    @Binding var presentation: TasksPresentation
    @Binding var showsCompleted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Picker("Task view", selection: $presentation) {
                ForEach(TasksPresentation.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Button {
                showsCompleted.toggle()
            } label: {
                Image(systemName: showsCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(showsCompleted ? .white : VowbaseTheme.ink)
                    .frame(width: 52, height: 38)
                    .background(showsCompleted ? VowbaseTheme.rose : VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(VowbaseTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showsCompleted ? "Hide completed tasks" : "Show completed tasks")
        }
    }
}

private struct TaskSection: View {
    let bucket: TaskDateBucket
    let tasks: [WeddingTask]
    let taskStore: TaskStore
    let canManageTasks: Bool
    let onEdit: (WeddingTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(bucket.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(bucket == .overdue ? .red : VowbaseTheme.mutedInk)

            VStack(spacing: 1) {
                ForEach(tasks) { task in
                    TaskRow(task: task, taskStore: taskStore, canManageTasks: canManageTasks, onEdit: { onEdit(task) })
                    if task.id != tasks.last?.id { Divider().padding(.leading, 66) }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VowbaseTheme.border.opacity(0.72), lineWidth: 1) }
        }
    }
}

private struct TaskRow: View {
    let task: WeddingTask
    let taskStore: TaskStore
    let canManageTasks: Bool
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Button {
                guard canManageTasks else { return }
                Task { await taskStore.setStatus(task.effectiveStatus == .done ? .todo : .done, for: task) }
            } label: {
                Image(systemName: task.effectiveStatus == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(task.effectiveStatus == .done ? VowbaseTheme.rose : VowbaseTheme.mutedInk.opacity(0.7))
                    .frame(width: 27, height: 27)
            }
            .buttonStyle(.plain)
            .disabled(!canManageTasks || taskStore.mutatingTaskIDs.contains(task.id))
            .accessibilityLabel(task.effectiveStatus == .done ? "Mark \(task.title) incomplete" : "Mark \(task.title) complete")

            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(VowbaseTheme.ink)
                        .strikethrough(task.effectiveStatus == .done, color: VowbaseTheme.mutedInk)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 7) {
                        if let due = TaskDateBucket.displayDate(for: task) {
                            Label(due, systemImage: "calendar")
                        }
                        if let owner = task.ownerLabel, !owner.isEmpty {
                            Label(owner, systemImage: "person")
                        }
                        if task.priority == .urgent || task.priority == .high {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(task.priority == .urgent ? .red : .orange)
                                .accessibilityLabel(task.priority?.title ?? "High priority")
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VowbaseTheme.mutedInk)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(VowbaseTheme.mutedInk.opacity(0.6))
                    .padding(.top, 5)
            }
            .buttonStyle(.plain)
            .disabled(!canManageTasks)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .contextMenu {
            if canManageTasks {
                Button(task.effectiveStatus == .done ? "Mark Incomplete" : "Mark Complete", systemImage: task.effectiveStatus == .done ? "arrow.uturn.backward" : "checkmark") {
                    Task { await taskStore.setStatus(task.effectiveStatus == .done ? .todo : .done, for: task) }
                }
                Button("Edit Task", systemImage: "pencil", action: onEdit)
            }
        }
    }
}

private struct TaskBoard: View {
    let tasks: [WeddingTask]
    let taskStore: TaskStore
    let canManageTasks: Bool
    @Binding var selectedColumnID: String?
    let onEdit: (WeddingTask) -> Void

    private let columns: [WeddingTaskStatus] = [.backlog, .todo, .inProgress, .blocked, .done]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(columns, id: \.self) { status in
                    VStack(alignment: .leading, spacing: 11) {
                        HStack {
                            Label(status.title, systemImage: status.systemImage)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(VowbaseTheme.ink)
                            Spacer()
                            Text("\(tasks.filter { $0.effectiveStatus == status }.count)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(VowbaseTheme.mutedInk)
                        }
                        LazyVStack(spacing: 9) {
                            ForEach(tasks.filter { $0.effectiveStatus == status }) { task in
                                TaskBoardCard(task: task, taskStore: taskStore, canManageTasks: canManageTasks) { onEdit(task) }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(width: 274, alignment: .topLeading)
                    .frame(minHeight: 500, alignment: .top)
                    .background(VowbaseTheme.blush.opacity(0.45), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .id(status.rawValue)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 20)
            .padding(.bottom, 100)
        }
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollPosition(id: $selectedColumnID)
        .accessibilityLabel("Task board columns")
    }
}

private struct TaskBoardCard: View {
    let task: WeddingTask
    let taskStore: TaskStore
    let canManageTasks: Bool
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 9) {
                Text(task.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(VowbaseTheme.ink)
                    .multilineTextAlignment(.leading)
                if let due = TaskDateBucket.displayDate(for: task) {
                    Label(due, systemImage: "calendar")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(TaskDateBucket.isOverdue(task) ? .red : VowbaseTheme.mutedInk)
                }
                if let owner = task.ownerLabel, !owner.isEmpty {
                    Label(owner, systemImage: "person.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canManageTasks)
        .contextMenu {
            if canManageTasks {
                Menu("Move to", systemImage: "arrow.right.circle") {
                    ForEach(WeddingTaskStatus.allCases, id: \.self) { status in
                        Button(status.title) { Task { await taskStore.setStatus(status, for: task) } }
                    }
                }
                Button("Edit Task", systemImage: "pencil", action: onEdit)
            }
        }
    }
}

private enum TaskDateBucket: String, Identifiable {
    case overdue, today, nextSevenDays, later, noDate, completed
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overdue: "Overdue"
        case .today: "Today"
        case .nextSevenDays: "Next 7 Days"
        case .later: "Later"
        case .noDate: "No Due Date"
        case .completed: "Completed"
        }
    }

    static func orderedBuckets(for tasks: [WeddingTask]) -> [TaskDateBucket] {
        let hasCompleted = tasks.contains { $0.effectiveStatus == .done }
        return [.overdue, .today, .nextSevenDays, .later, .noDate] + (hasCompleted ? [.completed] : [])
    }

    func contains(_ task: WeddingTask) -> Bool {
        if task.effectiveStatus == .done { return self == .completed }
        guard let due = TaskDueDateFormatter.date(from: task.dueDate ?? "") else { return self == .noDate }
        let calendar = Calendar.current
        if calendar.isDateInToday(due) { return self == .today }
        if due < calendar.startOfDay(for: Date()) { return self == .overdue }
        if let boundary = calendar.date(byAdding: .day, value: 7, to: Date()), due <= boundary { return self == .nextSevenDays }
        return self == .later
    }

    static func displayDate(for task: WeddingTask) -> String? {
        guard let value = task.dueDate, let date = TaskDueDateFormatter.date(from: value) else { return nil }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func isOverdue(_ task: WeddingTask) -> Bool {
        guard let date = TaskDueDateFormatter.date(from: task.dueDate ?? "") else { return false }
        return date < Calendar.current.startOfDay(for: Date()) && task.effectiveStatus != .done
    }
}
