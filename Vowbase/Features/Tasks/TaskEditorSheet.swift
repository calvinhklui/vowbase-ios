import SwiftUI

@MainActor
struct TaskEditorSheet: View {
    let destination: TaskEditorDestination
    let taskStore: TaskStore
    let weddingID: UUID?
    let canManageTasks: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var status: WeddingTaskStatus = .todo
    @State private var priority: WeddingTaskPriority = .medium
    @State private var ownerLabel = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var isSaving = false
    @State private var showsDeleteConfirmation = false

    private var task: WeddingTask? {
        guard case .edit(let id) = destination else { return nil }
        return taskStore.tasks.first(where: { $0.id == id })
    }

    private var isNew: Bool {
        if case .add = destination { return true }
        return false
    }

    private var showsUnavailableTask: Bool {
        !isNew && task == nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if showsUnavailableTask {
                    TaskUnavailableView()
                } else {
                    TaskEditorFields(title: $title, notes: $notes, status: $status, priority: $priority, ownerLabel: $ownerLabel, hasDueDate: $hasDueDate, dueDate: $dueDate, showsDeleteConfirmation: $showsDeleteConfirmation, showsDelete: !isNew && canManageTasks)
                }
            }
            .scrollContentBackground(.hidden)
            .background(VowbaseTheme.background)
            .navigationTitle(isNew ? "Add Task" : "Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    VowbaseConfirmationToolbarButton(
                        isNew ? "Add Task" : "Save Task",
                        isDisabled: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving || !canManageTasks,
                        action: save
                    )
                }
            }
            .disabled(!canManageTasks || isSaving)
            .overlay {
                if isSaving {
                    ProgressView()
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .alert("Couldn’t Save Task", isPresented: Binding(
                get: { taskStore.errorMessage != nil },
                set: { if !$0 { taskStore.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { taskStore.errorMessage = nil }
            } message: {
                Text(taskStore.errorMessage ?? "Please try again.")
            }
            .confirmationDialog("Delete this task?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Task", role: .destructive) { deleteTask() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can’t be undone.")
            }
            .onAppear(perform: configure)
        }
    }

    private func configure() {
        guard let task else {
            if case let .add(prefillTitle) = destination, let prefillTitle {
                title = prefillTitle
            }
            return
        }
        title = task.title
        notes = task.description ?? ""
        status = task.effectiveStatus
        priority = task.priority ?? .medium
        ownerLabel = task.ownerLabel ?? ""
        if let rawDueDate = task.dueDate, let parsed = TaskDueDateFormatter.date(from: rawDueDate) {
            hasDueDate = true
            dueDate = parsed
        }
    }

    private func save() {
        guard canManageTasks else { return }
        isSaving = true
        Task {
            let success: Bool
            if let task {
                success = await taskStore.update(
                    task: task,
                    title: title,
                    description: notes,
                    status: status,
                    priority: priority,
                    ownerLabel: ownerLabel,
                    dueDate: hasDueDate ? TaskDueDateFormatter.string(from: dueDate) : nil
                )
            } else if let weddingID {
                success = await taskStore.create(
                    TaskDraft(
                        title: title,
                        description: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
                        status: status,
                        priority: priority,
                        ownerLabel: ownerLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : ownerLabel,
                        dueDate: hasDueDate ? TaskDueDateFormatter.string(from: dueDate) : nil
                    ),
                    weddingID: weddingID
                )
            } else {
                success = false
            }
            isSaving = false
            if success { dismiss() }
        }
    }

    private func deleteTask() {
        guard let task else { return }
        isSaving = true
        Task {
            let success = await taskStore.delete(task)
            isSaving = false
            if success { dismiss() }
        }
    }
}

private struct TaskAssigneeFooter: View {
    var body: some View {
        Text("Add the person who owns the next step. Assignees can be refined to workspace members as that directory becomes available.")
    }
}

private struct TaskEditorFields: View {
    @Binding var title: String
    @Binding var notes: String
    @Binding var status: WeddingTaskStatus
    @Binding var priority: WeddingTaskPriority
    @Binding var ownerLabel: String
    @Binding var hasDueDate: Bool
    @Binding var dueDate: Date
    @Binding var showsDeleteConfirmation: Bool
    let showsDelete: Bool

    var body: some View {
        Form {
            TaskTextFields(title: $title, notes: $notes)
            TaskPlanFields(status: $status, priority: $priority)
            TaskTimingFields(hasDueDate: $hasDueDate, dueDate: $dueDate)
            TaskAssigneeFields(ownerLabel: $ownerLabel)
            if showsDelete {
                Section { Button("Delete Task", role: .destructive) { showsDeleteConfirmation = true } }
            }
        }
        .contentMargins(.horizontal, VowbaseControlMetric.screenInset, for: .scrollContent)
    }
}

private struct TaskTextFields: View {
    @Binding var title: String
    @Binding var notes: String

    var body: some View {
        Section {
            TextField("Task title", text: $title, axis: .vertical)
                .font(.system(size: 18, weight: .semibold))
                .lineLimit(1...3)
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(3...8)
        }
    }
}

private struct TaskPlanFields: View {
    @Binding var status: WeddingTaskStatus
    @Binding var priority: WeddingTaskPriority

    var body: some View {
        Section("Plan") {
            Picker("Status", selection: $status) {
                Text("Backlog").tag(WeddingTaskStatus.backlog)
                Text("To Do").tag(WeddingTaskStatus.todo)
                Text("In Progress").tag(WeddingTaskStatus.inProgress)
                Text("Blocked").tag(WeddingTaskStatus.blocked)
                Text("Done").tag(WeddingTaskStatus.done)
            }
            Picker("Priority", selection: $priority) {
                Text("Low").tag(WeddingTaskPriority.low)
                Text("Medium").tag(WeddingTaskPriority.medium)
                Text("High").tag(WeddingTaskPriority.high)
                Text("Urgent").tag(WeddingTaskPriority.urgent)
            }
        }
    }
}

private struct TaskTimingFields: View {
    @Binding var hasDueDate: Bool
    @Binding var dueDate: Date

    var body: some View {
        Section("Timing") {
            Toggle("Due date", isOn: $hasDueDate.animation())
            if hasDueDate { DatePicker("Due", selection: $dueDate, displayedComponents: .date) }
        }
    }
}

private struct TaskAssigneeFields: View {
    @Binding var ownerLabel: String

    var body: some View {
        Section {
            TextField("Name", text: $ownerLabel)
                .textContentType(.name)
        } header: {
            Text("Assigned to")
        } footer: {
            TaskAssigneeFooter()
        }
    }
}

private struct TaskUnavailableView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
            Text("Task unavailable")
                .font(.headline)
            Text("It may have been deleted in another session.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
