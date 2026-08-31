import SwiftUI

extension VenueCustomColumnKind {
    var title: String {
        switch self {
        case .text: "Text"
        case .number: "Number"
        case .select: "Select"
        case .checkbox: "Checkbox"
        case .rank: "Rank (1–5)"
        }
    }

    var symbol: String {
        switch self {
        case .text: "textformat"
        case .number: "number"
        case .select: "list.bullet"
        case .checkbox: "checkmark.square"
        case .rank: "5.circle"
        }
    }
}

@MainActor
struct VenueFieldListView: View {
    let store: VowbaseWorkspaceStore
    let allowsVerticalScrolling: Bool
    let onRequestExpansion: () -> Void
    let onRequestCollapse: () -> Void

    @State private var presentedEditor: VenueFieldEditorDestination?
    @State private var pendingDeletion: VenueCustomColumn?

    private var columns: [VenueCustomColumn] { store.allVenueCustomColumns }

    var body: some View {
        List {
            if columns.isEmpty {
                emptyState
            } else {
                Section {
                    ForEach(columns) { column in
                        Button {
                            presentedEditor = .edit(column)
                        } label: {
                            row(column)
                        }
                        .swipeActions(edge: .leading) {
                            Button(column.hidden ? "Show" : "Hide") {
                                Task { await store.updateVenueCustomColumn(column, hidden: !column.hidden) }
                            }
                            .tint(VowbaseTheme.mutedInk)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) { pendingDeletion = column }
                        }
                    }
                    .onMove { source, destination in
                        Task { await store.reorderVenueCustomColumns(from: source, to: destination) }
                    }
                    .onDelete { offsets in
                        if let index = offsets.first {
                            pendingDeletion = columns[index]
                        }
                    }
                } header: {
                    Text("\(columns.count) field\(columns.count == 1 ? "" : "s")")
                } footer: {
                    Text("Drag to reorder. This order controls venue detail and Add venue. The number is how many venues hold a value.")
                }
            }

            Section {
                Button {
                    presentedEditor = .create
                } label: {
                    Label("Add a field", systemImage: "plus")
                }
                .tint(VowbaseTheme.rose)
            }

            if columns.filter({ !$0.hidden }).count > 12 {
                Section {
                    Text("Long field lists make venue details harder to scan. Consider hiding seasonal fields instead of deleting them.")
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
        .sheet(item: $presentedEditor) { destination in
            switch destination {
            case .create:
                VenueFieldEditorView(store: store, column: nil)
            case let .edit(column):
                VenueFieldEditorView(store: store, column: column)
            }
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
                Task { await store.deleteVenueCustomColumn(column) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { column in
            let used = store.venueUsageCount(for: column)
            Text(
                used == 0
                    ? "No venues hold a value for this field."
                    : "This permanently removes the value stored for \(used) venue\(used == 1 ? "" : "s"). It can’t be undone."
            )
        }
    }

    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("No custom fields yet.")
                    .font(.headline)
                Text("Add fields for the things you compare per venue — Reception, Catering, Parking, Accessibility.")
                    .font(.subheadline)
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
            .padding(.vertical, 8)
        }
    }

    private func row(_ column: VenueCustomColumn) -> some View {
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
                Text("\(store.venueUsageCount(for: column))")
                    .monospacedDigit()
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
        }
        .opacity(column.hidden ? 0.55 : 1)
    }
}

private enum VenueFieldEditorDestination: Identifiable {
    case create
    case edit(VenueCustomColumn)

    var id: String {
        switch self {
        case .create: "create"
        case let .edit(column): "edit-\(column.id.uuidString)"
        }
    }
}

@MainActor
private struct VenueFieldEditorView: View {
    let store: VowbaseWorkspaceStore
    let column: VenueCustomColumn?

    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var kind: VenueCustomColumnKind
    @State private var options: [String]
    @State private var hidden: Bool
    @State private var newOption = ""
    @State private var renameTarget: String?
    @State private var renameText = ""
    @State private var isSaving = false

    init(store: VowbaseWorkspaceStore, column: VenueCustomColumn?) {
        self.store = store
        self.column = column
        _label = State(initialValue: column?.label ?? "")
        _kind = State(initialValue: column?.kind ?? .text)
        _options = State(initialValue: column.map(VenueCustomFields.options(in:)) ?? [])
        _hidden = State(initialValue: column?.hidden ?? false)
    }

    private var isCreating: Bool { column == nil }
    private var usageCount: Int { column.map(store.venueUsageCount(for:)) ?? 0 }

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
                    let used = store.venueUsageCount(for: column, option: target)
                    Text("\(used) venue\(used == 1 ? "" : "s") use this option. Rewriting updates them; renaming only leaves them on the old label.")
                }
            }
        }
    }

    private var identitySection: some View {
        Section {
            TextField("Label", text: $label)
                .textInputAutocapitalization(.words)
            LabeledContent("Key") {
                Text(column?.key ?? store.proposedVenueCustomKey(for: label))
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
            ForEach(VenueCustomColumnKind.allCases, id: \.self) { option in
                Button {
                    guard isCreating || option == kind || usageCount == 0 else { return }
                    kind = option
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
                .disabled(!isCreating && option != kind && usageCount > 0)
            }
        } header: {
            Text("Kind")
        } footer: {
            if !isCreating {
                Text(usageCount > 0
                     ? "Kind can’t change once a venue holds a value."
                     : "A field’s kind can change until a venue holds a value.")
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
                        Text("\(store.venueUsageCount(for: column, option: option))")
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
                 : "Renaming asks whether to rewrite the venues using an option. Removing one leaves their value in place, shown as no longer an option.")
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

    private func commitRename(rewriting: Bool) {
        guard let column, let original = renameTarget else { return }
        let replacement = renameText.trimmed
        renameTarget = nil
        guard !replacement.isEmpty, replacement != original else { return }
        Task {
            await store.renameVenueOption(
                column,
                from: original,
                to: replacement,
                rewritingVenues: rewriting
            )
            let refreshed = store.allVenueCustomColumns.first { $0.id == column.id } ?? column
            options = VenueCustomFields.options(in: refreshed)
        }
    }

    private func save() {
        isSaving = true
        Task {
            let didSave: Bool
            if let column {
                didSave = await store.updateVenueCustomColumn(
                    column,
                    label: label,
                    kind: kind,
                    options: kind == .select ? options : [],
                    hidden: hidden
                )
            } else {
                didSave = await store.createVenueCustomColumn(
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
}

#if DEBUG
#Preview("Manage venue fields") {
    NavigationStack {
        VenueFieldListView(
            store: VowbaseWorkspaceStore(testingWorkspace: true),
            allowsVerticalScrolling: true,
            onRequestExpansion: {},
            onRequestCollapse: {}
        )
    }
}
#endif
