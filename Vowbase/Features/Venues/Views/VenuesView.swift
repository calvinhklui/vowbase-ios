import SwiftUI

// MARK: - Venues

/// The Venues lens content stays mounted as the console moves through its
/// detents. Its own header is gone; the console's shared, selection-aware
/// header (`ConsoleHeader`) covers it instead.
@MainActor
struct VenuesView: View {
    let store: VowbaseWorkspaceStore
    let onAddVenue: () -> Void
    let onReturnToMap: () -> Void
    /// Routes a list selection through the shell so the persistent map and
    /// console navigation update in one transaction.
    let onSelectVenue: (MVPVenue) -> Void
    let onViewOnMap: (MVPVenue) -> Void
    let allowsVerticalScrolling: Bool
    let onRequestExpansion: () -> Void
    let onRequestCollapse: () -> Void
    @Binding var isNoteEditing: Bool
    /// Owned by `WeddingAppShell`, not this view — the shell needs to know
    /// when this stack has drilled past its root so it can hide the
    /// console's own header and grabber for the pushed detail screen.
    @Binding var path: NavigationPath
    @State private var selectedStatus: VenueStatus?
    @State private var query = ""
    @State private var sort: VenueSortOrder = .lastUpdated

    private var visibleVenues: [MVPVenue] {
        store.filteredVenues(searchText: query, status: selectedStatus, sort: sort)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ConsoleHeader(venues: store.venues)
                        .padding(.bottom, VowbaseSpace.small)

                    if !store.venues.isEmpty {
                        VenueMetricPills(venues: store.venues, selectedStatus: $selectedStatus)
                    }

                    toolRow
                        .padding(.top, 10)

                    Group {
                        if store.venues.isEmpty {
                            VenuesEmptyState(onAddVenue: onAddVenue, onReturnToMap: onReturnToMap)
                        } else if visibleVenues.isEmpty {
                            noResults
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(visibleVenues.enumerated()), id: \.element.id) { index, venue in
                                    Button {
                                        onSelectVenue(venue)
                                    } label: {
                                        CompactVenueRow(venue: venue)
                                    }
                                    .buttonStyle(.plain)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    if index < visibleVenues.count - 1 {
                                        Divider()
                                            .padding(.leading, 86)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 18)
                }
                .padding(.horizontal, 16)
            }
            .consoleVerticalScrollHandoff(
                allowsVerticalScrolling: allowsVerticalScrolling,
                onExpand: onRequestExpansion,
                onCollapse: onRequestCollapse
            )
            .scrollDismissesKeyboard(.immediately)
            .vowbaseScrollClearance()
            .navigationBarHidden(true)
            .navigationDestination(for: MVPVenue.self) { venue in
                VenueDetailView(
                    venue: venue,
                    store: store,
                    isNoteEditing: $isNoteEditing,
                    onViewOnMap: { onViewOnMap(venue) },
                    allowsVerticalScrolling: allowsVerticalScrolling,
                    onRequestExpansion: onRequestExpansion,
                    onRequestCollapse: onRequestCollapse
                )
            }
            .navigationDestination(for: VenuesRoute.self) { route in
                switch route {
                case .customFields:
                    VenueFieldListView(
                        store: store,
                        allowsVerticalScrolling: allowsVerticalScrolling,
                        onRequestExpansion: onRequestExpansion,
                        onRequestCollapse: onRequestCollapse
                    )
                }
            }
        }
    }

    // MARK: Controls

    private var toolRow: some View {
        HStack(spacing: 4) {
            CompactConsoleSearchField(placeholder: "Search venues", text: $query)

            Menu {
                Picker("Filter by status", selection: $selectedStatus) {
                    Text("All statuses").tag(VenueStatus?.none)
                    ForEach(VenueStatus.compactLifecycleOrder, id: \.self) { status in
                        Text(status.title).tag(Optional(status))
                    }
                }
            } label: {
                CompactConsoleCircleControl(
                    systemImage: "line.3.horizontal.decrease",
                    isActive: selectedStatus != nil
                )
            }
            .accessibilityLabel(selectedStatus.map { "Filter, \($0.title)" } ?? "Filter")

            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(VenueSortOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
            } label: {
                CompactConsoleCircleControl(systemImage: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort")

            NavigationLink(value: VenuesRoute.customFields) {
                CompactConsoleCircleControl(systemImage: "slider.horizontal.3")
            }
            .accessibilityLabel("Manage venue fields")
        }
    }

    private var noResults: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                selectedStatus == nil ? "No venues match \u{201c}\(query)\u{201d}" : "No venues match these filters",
                systemImage: selectedStatus == nil ? "magnifyingglass" : "line.3.horizontal.decrease.circle",
                description: Text(noResultsDescription)
            )
            Button("Clear filters") {
                query = ""
                selectedStatus = nil
            }
            .font(.system(size: 16, weight: .semibold))
            .tint(VowbaseTheme.rose)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private var noResultsDescription: String {
        if selectedStatus != nil {
            return "Try a different lifecycle status or search."
        }
        return "Search covers venue names, status, locations, and contact details."
    }
}

enum VenuesRoute: Hashable {
    case customFields
}

private extension VenueStatus {
    static let compactLifecycleOrder: [VenueStatus] = [
        .considering, .contacted, .toured,
        .shortlisted, .negotiating, .booked, .passed
    ]
}

private struct VenueMetricPills: View {
    let venues: [MVPVenue]
    @Binding var selectedStatus: VenueStatus?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(VenueStatus.compactLifecycleOrder, id: \.self) { status in
                    let isSelected = selectedStatus == status
                    let count = venues.count(where: { $0.status == status })

                    Button {
                        selectedStatus = isSelected ? nil : status
                    } label: {
                        CompactMetricFilterPill(
                            count: count,
                            title: status.title,
                            isSelected: isSelected
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(status.title), \(count) venue\(count == 1 ? "" : "s")")
                    .accessibilityHint(isSelected ? "Double tap to show all venues" : "Double tap to filter the venue list")
                }
            }
        }
        .scrollDisabled(false)
        .contentMargins(.horizontal, 1, for: .scrollContent)
        .animation(.easeInOut(duration: 0.18), value: selectedStatus)
    }
}

private struct CompactVenueRow: View {
    let venue: MVPVenue

    var body: some View {
        HStack(spacing: 12) {
            VowbaseVenueImage(url: venue.photoURL, cacheKey: venue.coverPhotoCacheKey)
                .frame(width: 72, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(venue.name)
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(VowbaseTheme.ink)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    CompactVenueStatus(status: venue.status)
                    Text(venue.rowSecondaryText)
                        .font(.system(size: 13))
                        .foregroundStyle(VowbaseTheme.mutedInk)
                        .lineLimit(1)
                }

                HStack(spacing: 12) {
                    Label(venue.capacity, systemImage: "person.2")
                    Label(venue.estimate, systemImage: "dollarsign.circle")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(VowbaseTheme.mutedInk)
                .lineLimit(1)
            }

            Spacer(minLength: 6)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VowbaseTheme.mutedInk)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct CompactVenueStatus: View {
    let status: VenueStatus

    var body: some View {
        Text(status.title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(status.badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.badgeColor.opacity(0.16), in: Capsule())
    }
}

private struct VenuesEmptyState: View {
    let onAddVenue: () -> Void
    let onReturnToMap: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 34))
                .foregroundStyle(VowbaseTheme.rose)
                .padding(22)
                .background(VowbaseTheme.blush, in: Circle())

            VStack(spacing: 8) {
                Text("Start your venue shortlist.")
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(VowbaseTheme.ink)
                    .multilineTextAlignment(.center)
                Text("Add a name, location, capacity, price, and your impressions after each visit — everything you need to build a shortlist and choose the right place.")
                    .font(.system(size: 15))
                    .foregroundStyle(VowbaseTheme.mutedInk)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Button("Add venue", action: onAddVenue)
                    .buttonStyle(VowbasePrimaryButtonStyle())
                Button("Return to Map", action: onReturnToMap)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(VowbaseTheme.rose)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 44)
        .frame(maxWidth: .infinity)
    }
}

@MainActor
struct VenueFieldListView: View {
    let store: VowbaseWorkspaceStore
    let allowsVerticalScrolling: Bool
    let onRequestExpansion: () -> Void
    let onRequestCollapse: () -> Void
    @State private var editor: VenueCustomColumn?
    @State private var isCreating = false
    @State private var pendingDeletion: VenueCustomColumn?

    private var columns: [VenueCustomColumn] { store.allVenueCustomColumns }

    var body: some View {
        List {
            Section {
                if columns.isEmpty {
                    Text("No custom fields yet. Track independent venue details like Reception, Catering, or Parking.")
                        .foregroundStyle(VowbaseTheme.mutedInk)
                } else {
                    ForEach(columns) { column in
                        Button { editor = column } label: {
                            HStack {
                                Image(systemName: column.kind.symbol).frame(width: 28)
                                    .foregroundStyle(VowbaseTheme.rose)
                                VStack(alignment: .leading) {
                                    Text(column.label).foregroundStyle(VowbaseTheme.ink)
                                    Text(column.key).font(.caption.monospaced()).foregroundStyle(VowbaseTheme.mutedInk)
                                }
                                Spacer()
                                Text("\(store.venueUsageCount(for: column))").monospacedDigit().foregroundStyle(VowbaseTheme.mutedInk)
                                if column.hidden { Image(systemName: "eye.slash").foregroundStyle(VowbaseTheme.mutedInk) }
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button(column.hidden ? "Show" : "Hide") { Task { await store.updateVenueCustomColumn(column, hidden: !column.hidden) } }
                                .tint(VowbaseTheme.mutedInk)
                        }
                        .swipeActions { Button("Delete", role: .destructive) { pendingDeletion = column } }
                    }
                    .onMove { source, destination in Task { await store.reorderVenueCustomColumns(from: source, to: destination) } }
                }
            } header: { Text("\(columns.count) field\(columns.count == 1 ? "" : "s")") } footer: {
                Text("Drag to reorder. Hidden fields keep their values. A rank is a separate 1–5 score, not the venue shortlist order.")
            }
            Section { Button { isCreating = true } label: { Label("Add a field", systemImage: "plus") }.tint(VowbaseTheme.rose) }
        }
        .consoleVerticalScrollHandoff(allowsVerticalScrolling: allowsVerticalScrolling, onExpand: onRequestExpansion, onCollapse: onRequestCollapse)
        .navigationTitle("Manage fields").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton().tint(VowbaseTheme.rose) } }
        .sheet(item: $editor) { VenueFieldEditorView(store: store, column: $0) }
        .sheet(isPresented: $isCreating) { VenueFieldEditorView(store: store, column: nil) }
        .alert("Delete “\(pendingDeletion?.label ?? "")”?", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), presenting: pendingDeletion) { column in
            Button("Delete field", role: .destructive) { Task { await store.deleteVenueCustomColumn(column) } }
            Button("Cancel", role: .cancel) {}
        } message: { column in
            let count = store.venueUsageCount(for: column)
            Text(count == 0 ? "No venues hold a value for this field." : "This permanently removes the value stored for \(count) venue\(count == 1 ? "" : "s").")
        }
    }
}

private struct VenueFieldEditorView: View {
    let store: VowbaseWorkspaceStore
    let column: VenueCustomColumn?
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var kind: VenueCustomColumnKind
    @State private var options: [String]
    @State private var hidden: Bool
    @State private var newOption = ""
    @State private var isSaving = false

    init(store: VowbaseWorkspaceStore, column: VenueCustomColumn?) {
        self.store = store; self.column = column
        _label = State(initialValue: column?.label ?? "")
        _kind = State(initialValue: column?.kind ?? .text)
        _options = State(initialValue: column.map(VenueCustomFields.options(in:)) ?? [])
        _hidden = State(initialValue: column?.hidden ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label", text: $label).textInputAutocapitalization(.words)
                    LabeledContent("Key", value: column?.key ?? store.proposedVenueCustomKey(for: label))
                        .font(.callout.monospaced()).foregroundStyle(VowbaseTheme.mutedInk)
                }
                Section {
                    ForEach(VenueCustomColumnKind.allCases, id: \.self) { option in
                        Button { if column == nil || option == kind || store.venueUsageCount(for: column!) == 0 { kind = option } } label: {
                            HStack { Image(systemName: option.symbol).frame(width: 24); Text(option.title); Spacer(); if option == kind { Image(systemName: "checkmark") } }
                        }.foregroundStyle(VowbaseTheme.ink)
                    }
                } header: { Text("Kind") } footer: { if let column, store.venueUsageCount(for: column) > 0 { Text("Kind cannot change once a venue holds a value.") } }
                if kind == .select { optionsSection }
                Section { Toggle("Hidden", isOn: $hidden).tint(VowbaseTheme.rose) }
            }
            .navigationTitle(column == nil ? "Add field" : "Edit field").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(column == nil ? "Add" : "Save") { save() }.disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving) }
            }
        }
    }

    private var optionsSection: some View {
        Section("Options") {
            ForEach(options, id: \.self) { option in
                HStack { Text(option); Spacer(); Button(role: .destructive) { options.removeAll { $0 == option } } label: { Image(systemName: "trash") } }
            }.onMove { options.move(fromOffsets: $0, toOffset: $1) }
            HStack { TextField("Add an option", text: $newOption); Button("Add") { let value = newOption.trimmingCharacters(in: .whitespacesAndNewlines); guard !value.isEmpty, !options.contains(value) else { return }; options.append(value); newOption = "" } }
        }
    }

    private func save() {
        isSaving = true
        Task {
            let ok: Bool
            if let column { ok = await store.updateVenueCustomColumn(column, label: label, kind: kind, options: kind == .select ? options : [], hidden: hidden) }
            else { ok = await store.createVenueCustomColumn(label: label, kind: kind, options: kind == .select ? options : []) }
            isSaving = false; if ok { dismiss() }
        }
    }
}

extension VenueCustomColumnKind {
    var title: String { switch self { case .text: "Text"; case .number: "Number"; case .select: "Select"; case .checkbox: "Checkbox"; case .rank: "Rank (1–5)" } }
    var symbol: String { switch self { case .text: "textformat"; case .number: "number"; case .select: "list.bullet"; case .checkbox: "checkmark.square"; case .rank: "5.circle" } }
}
