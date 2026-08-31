import SwiftUI

private extension GuestCustomColumnKind {
    var title: String {
        switch self {
        case .text: "Text"
        case .number: "Number"
        case .select: "Select"
        case .checkbox: "Checkbox"
        }
    }

    var symbol: String {
        switch self {
        case .text: "textformat"
        case .number: "number"
        case .select: "list.bullet"
        case .checkbox: "checkmark.square"
        }
    }

    /// What happens to values already stored when a column changes to this kind.
    var coercionWarning: String {
        switch self {
        case .number: "Values that aren’t numbers will be cleared."
        case .text: "Values are preserved as text."
        case .select: "Existing distinct values become the starting option list."
        case .checkbox: "Any non-empty value becomes checked."
        }
    }
}

/// The wedding's own field schema.
///
/// Order set here drives guest detail, Add guest, and the filter sheet, so this
/// is the one place ordering is decided.
@MainActor
struct GuestFieldListView: View {
    let store: VowbaseWorkspaceStore
    let allowsVerticalScrolling: Bool
    let onRequestExpansion: () -> Void
    let onRequestCollapse: () -> Void
    @State private var editingColumn: GuestCustomColumn?
    @State private var isCreating = false
    @State private var pendingDeletion: GuestCustomColumn?

    private var columns: [GuestCustomColumn] { store.allCustomColumns }

    init(
        store: VowbaseWorkspaceStore,
        allowsVerticalScrolling: Bool = true,
        onRequestExpansion: @escaping () -> Void = {},
        onRequestCollapse: @escaping () -> Void = {}
    ) {
        self.store = store
        self.allowsVerticalScrolling = allowsVerticalScrolling
        self.onRequestExpansion = onRequestExpansion
        self.onRequestCollapse = onRequestCollapse
    }

    var body: some View {
        List {
            if columns.isEmpty {
                emptyState
            } else {
                Section {
                    ForEach(columns) { column in
                        Button {
                            editingColumn = column
                        } label: {
                            row(column)
                        }
                        .swipeActions(edge: .leading) {
                            Button(column.hidden ? "Show" : "Hide") {
                                Task { await store.updateCustomColumn(column, hidden: !column.hidden) }
                            }
                            .tint(VowbaseTheme.mutedInk)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) { pendingDeletion = column }
                        }
                    }
                    .onMove { source, destination in
                        Task { await store.reorderCustomColumns(from: source, to: destination) }
                    }
                    .onDelete { offsets in
                        // Edit mode replaces swipe actions with its own delete
                        // control, so this is the only path to Delete once
                        // reordering is active. Route it through the same
                        // confirmation rather than deleting immediately.
                        if let index = offsets.first {
                            pendingDeletion = columns[index]
                        }
                    }
                } header: {
                    Text("\(columns.count) field\(columns.count == 1 ? "" : "s")")
                } footer: {
                    Text("Drag to reorder. This order controls guest detail, Add guest, and the filter sheet. The number is how many guests hold a value.")
                }
            }

            Section {
                Button {
                    isCreating = true
                } label: {
                    Label("Add a field", systemImage: "plus")
                }
                .tint(VowbaseTheme.rose)
            }

            if columns.filter { !$0.hidden }.count > 12 {
                Section {
                    Text("Long field lists make guest rows harder to scan. Consider hiding seasonal fields instead of deleting them.")
                        .font(.footnote)
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }
            }
        }
        .consoleVerticalScrollHandoff(
            allowsVerticalScrolling: allowsVerticalScrolling,
            onExpand: onRequestExpansion,
            onCollapse: onRequestCollapse
        )
        .scrollContentBackground(.hidden)
        .background(VowbaseTheme.groupedBackground)
        .tint(VowbaseTheme.rose)
        .navigationTitle("Manage Fields")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton().tint(VowbaseTheme.rose) }
        }
        .sheet(item: $editingColumn) { column in
            GuestFieldEditorView(store: store, column: column)
        }
        .sheet(isPresented: $isCreating) {
            GuestFieldEditorView(store: store, column: nil)
        }
        .alert(
            "Delete “\(pendingDeletion?.label ?? "")”?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { column in
            Button("Delete field", role: .destructive) {
                Task { await store.deleteCustomColumn(column) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { column in
            let used = store.usageCount(for: column)
            Text(
                used == 0
                    ? "No guests hold a value for this field."
                    : "This permanently removes the value stored for \(used) guest\(used == 1 ? "" : "s"). It can’t be undone."
            )
        }
    }

    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("No custom fields yet.")
                    .font(.headline)
                Text("Add fields for the things you track per guest — Group, Meal choice, Plus one, Table.")
                    .font(.subheadline)
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
            .padding(.vertical, 8)
        }
    }

    private func row(_ column: GuestCustomColumn) -> some View {
        HStack(spacing: 12) {
            Image(systemName: column.kind.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(VowbaseTheme.rose)
                .frame(width: 30, height: 30)
                .background(VowbaseTheme.blush, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(column.label)
                    .foregroundStyle(VowbaseTheme.ink)
                Text(column.key)
                    .font(.caption.monospaced())
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
            Spacer(minLength: 8)
            if column.hidden {
                Text("Hidden")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(VowbaseTheme.border.opacity(0.5), in: Capsule())
                    .foregroundStyle(VowbaseTheme.mutedInk)
            } else {
                Text("\(store.usageCount(for: column))")
                    .monospacedDigit()
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
        }
        .opacity(column.hidden ? 0.55 : 1)
    }
}

/// Creates or edits one column. Both flows share this form because the only
/// real difference is whether the key is still up for grabs.
@MainActor
private struct GuestFieldEditorView: View {
    let store: VowbaseWorkspaceStore
    /// Nil when creating.
    let column: GuestCustomColumn?

    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var kind: GuestCustomColumnKind
    @State private var options: [String]
    @State private var hidden: Bool
    @State private var newOption = ""
    @State private var pendingKind: GuestCustomColumnKind?
    @State private var renameTarget: String?
    @State private var renameText = ""
    @State private var isSaving = false

    init(store: VowbaseWorkspaceStore, column: GuestCustomColumn?) {
        self.store = store
        self.column = column
        _label = State(initialValue: column?.label ?? "")
        _kind = State(initialValue: column?.kind ?? .text)
        _options = State(initialValue: column.map(GuestCustomFields.options(in:)) ?? [])
        _hidden = State(initialValue: column?.hidden ?? false)
    }

    private var isCreating: Bool { column == nil }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                kindSection
                if kind == .select {
                    optionsSection
                }
                visibilitySection
            }
            .scrollContentBackground(.hidden)
            .background(VowbaseTheme.groupedBackground)
            .tint(VowbaseTheme.rose)
            .navigationTitle(isCreating ? "Add field" : "Edit field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "Add" : "Save") { save() }
                        .disabled(label.trimmed.isEmpty || isSaving)
                }
            }
            .alert(
                "Change “\(label)” to \(pendingKind?.title.lowercased() ?? "")?",
                isPresented: Binding(
                    get: { pendingKind != nil },
                    set: { if !$0 { pendingKind = nil } }
                ),
                presenting: pendingKind
            ) { target in
                Button("Change kind") { apply(kind: target) }
                Button("Cancel", role: .cancel) {}
            } message: { target in
                let affected = column.map(store.usageCount(for:)) ?? 0
                Text("\(target.coercionWarning) \(affected) guest\(affected == 1 ? "" : "s") hold a value for this field.")
            }
            .alert(
                "Rename “\(renameTarget ?? "")”",
                isPresented: Binding(
                    get: { renameTarget != nil },
                    set: { if !$0 { renameTarget = nil } }
                )
            ) {
                TextField("Option name", text: $renameText)
                Button("Rename and rewrite") { commitRename(rewriting: true) }
                Button("Rename only") { commitRename(rewriting: false) }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let target = renameTarget, let column {
                    let used = store.usageCount(for: column, option: target)
                    Text("\(used) guest\(used == 1 ? "" : "s") use this option. Rewriting updates them; renaming only leaves them on the old label.")
                }
            }
        }
    }

    // MARK: Sections

    private var identitySection: some View {
        Section {
            TextField("Label", text: $label)
                .textInputAutocapitalization(.words)
            LabeledContent("Key") {
                Text(column?.key ?? store.proposedKey(for: label))
                    .font(.callout.monospaced())
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
        } footer: {
            Text(isCreating
                 ? "The key is generated from the label and shared with the web workspace. It can’t change later."
                 : "The key is shared with the web workspace and can’t change after the field is created. Renaming the label is safe and updates every screen.")
        }
    }

    private var kindSection: some View {
        Section {
            ForEach([GuestCustomColumnKind.text, .number, .select, .checkbox], id: \.self) { option in
                Button {
                    select(kind: option)
                } label: {
                    HStack {
                        Image(systemName: option.symbol)
                            .foregroundStyle(VowbaseTheme.rose)
                            .frame(width: 24)
                        Text(option.title).foregroundStyle(VowbaseTheme.ink)
                        Spacer()
                        if option == kind {
                            Image(systemName: "checkmark").foregroundStyle(VowbaseTheme.rose)
                        }
                    }
                }
            }
        } header: {
            Text("Kind")
        } footer: {
            if !isCreating {
                Text("Changing the kind converts stored values. You’ll see how many guests are affected first.")
            }
        }
    }

    private var optionsSection: some View {
        Section {
            ForEach(options, id: \.self) { option in
                HStack {
                    Text(option)
                    Spacer()
                    if let column {
                        Text("\(store.usageCount(for: column, option: option))")
                            .monospacedDigit()
                            .foregroundStyle(VowbaseTheme.mutedInk)
                        Button {
                            renameTarget = option
                            renameText = option
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .tint(VowbaseTheme.rose)
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        options.removeAll { $0 == option }
                    }
                }
            }
            .onMove { source, destination in
                options.move(fromOffsets: source, toOffset: destination)
            }
            HStack {
                TextField("Add an option", text: $newOption)
                Button("Add") {
                    let trimmed = newOption.trimmed
                    guard !trimmed.isEmpty, !options.contains(trimmed) else { return }
                    options.append(trimmed)
                    newOption = ""
                }
                .disabled(newOption.trimmed.isEmpty)
            }
        } header: {
            Text("Options")
        } footer: {
            Text(isCreating
                 ? "Add the choices this field offers."
                 : "Renaming asks whether to rewrite the guests using an option. Removing one leaves their value in place, shown as no longer an option.")
        }
    }

    private var visibilitySection: some View {
        Section {
            Toggle("Hidden", isOn: $hidden)
                .tint(VowbaseTheme.rose)
        } footer: {
            Text("Hidden fields keep their data and stay visible in the web workspace. Use this for seasonal fields instead of deleting them.")
        }
    }

    // MARK: Actions

    private func select(kind target: GuestCustomColumnKind) {
        guard target != kind else { return }
        // Creating a field has no stored values to convert, so no warning.
        guard !isCreating, let column, store.usageCount(for: column) > 0 else {
            apply(kind: target)
            return
        }
        pendingKind = target
    }

    private func apply(kind target: GuestCustomColumnKind) {
        if target == .select, options.isEmpty, let column {
            // Seed the option list from what guests already hold.
            let existing = store.allGuestRecords.compactMap { guest -> String? in
                let stored = GuestCustomFields.value(in: guest.customFields, for: column.key)
                return GuestCustomFields.displayText(stored, kind: column.kind)
            }
            options = Set(existing).sorted()
        }
        kind = target
        pendingKind = nil
    }

    private func commitRename(rewriting: Bool) {
        guard let column, let original = renameTarget else { return }
        let replacement = renameText.trimmed
        renameTarget = nil
        guard !replacement.isEmpty, replacement != original else { return }
        Task {
            await store.renameOption(
                column,
                from: original,
                to: replacement,
                rewritingGuests: rewriting
            )
            let refreshed = store.allCustomColumns.first { $0.id == column.id } ?? column
            options = GuestCustomFields.options(in: refreshed)
        }
    }

    private func save() {
        isSaving = true
        Task {
            let didSave: Bool
            if let column {
                didSave = await store.updateCustomColumn(
                    column,
                    label: label,
                    kind: kind,
                    options: kind == .select ? options : [],
                    hidden: hidden
                )
            } else {
                didSave = await store.createCustomColumn(
                    label: label,
                    kind: kind,
                    options: kind == .select ? options : []
                )
            }
            isSaving = false
            if didSave { dismiss() }
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfBlank: String? { trimmed.isEmpty ? nil : trimmed }
}

#if DEBUG
#Preview("Manage fields") {
    NavigationStack {
        GuestFieldListView(store: VowbaseWorkspaceStore(testingWorkspace: true))
    }
}
#endif
