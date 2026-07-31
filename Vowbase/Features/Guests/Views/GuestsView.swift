import SwiftUI

// MARK: - Guests

/// The Guests lens's half/full console content — see `VenuesView`'s doc
/// comment for how this fits into the console. Its own header is gone; the
/// shared `ConsoleHeader` covers it now.
@MainActor
struct GuestsView: View {
    let store: VowbaseWorkspaceStore
    /// Owned by `WeddingAppShell` — see `VenuesView.path`'s doc comment.
    @Binding var path: NavigationPath
    @State private var query = ""
    @State private var filters = GuestFilterSet()
    @State private var sort: GuestSortOrder = .nameAscending
    @State private var showsFilter = false

    private var visibleGuests: [MVPGuest] {
        store.filteredGuests(searchText: query, filters: filters, sort: sort)
    }

    private var records: [Guest] { store.allGuestRecords }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    toolRow
                    if filters.conditionCount > 0 {
                        activeFilterTokens
                    }
                    guestList
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            .vowbaseScrollClearance()
            .refreshable {
                await store.load()
            }
            .navigationBarHidden(true)
            .navigationDestination(for: MVPGuest.self) { guest in
                GuestDetailView(guest: guest, store: store)
            }
            .navigationDestination(for: GuestsRoute.self) { route in
                switch route {
                case .customFields:
                    GuestFieldListView(store: store)
                }
            }
            .sheet(isPresented: $showsFilter) {
                GuestFilterSheet(store: store, searchText: query, filters: $filters)
            }
        }
    }

    // MARK: Controls

    private var toolRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(VowbaseTheme.mutedInk)
                TextField("Search guests", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(VowbaseTheme.mutedInk)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VowbaseTheme.border, lineWidth: 1))

            filtersButton
            overflowMenu
        }
    }

    private var filtersButton: some View {
        Button {
            showsFilter = true
        } label: {
            Label("Filters", systemImage: "slider.horizontal.3")
                .labelStyle(.iconOnly)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(filters.conditionCount > 0 ? .white : VowbaseTheme.ink)
                .frame(width: 52, height: 52)
                .background(
                    filters.conditionCount > 0 ? VowbaseTheme.rose : VowbaseTheme.background,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VowbaseTheme.border, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if filters.conditionCount > 0 {
                        Text("\(filters.conditionCount)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(VowbaseTheme.rose)
                            .padding(4)
                            .background(VowbaseTheme.background, in: Circle())
                            .overlay(Circle().stroke(VowbaseTheme.rose, lineWidth: 1))
                            .offset(x: 5, y: -5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            filters.conditionCount > 0
                ? "Filters, \(filters.conditionCount) active"
                : "Filters"
        )
    }

    private var overflowMenu: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                ForEach(GuestSortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            Divider()
            Button {
                path.append(GuestsRoute.customFields)
            } label: {
                Label("Manage fields", systemImage: "list.bullet.rectangle")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(VowbaseTheme.ink)
                .frame(width: 52, height: 52)
                .background(VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VowbaseTheme.border, lineWidth: 1))
        }
        .accessibilityLabel("Sort and manage fields")
    }

    /// A filtered list should never look like the whole list. Every active
    /// condition — RSVP included, now that it has no dedicated chip row —
    /// is named here and removable in one tap. One consistent capsule shape
    /// and size for every active filter, not two different components.
    private var activeFilterTokens: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(tokens, id: \.id) { token in
                    Button {
                        token.remove(&filters)
                    } label: {
                        HStack(spacing: 6) {
                            Text(token.title)
                                .font(.system(size: 16, weight: .medium))
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(VowbaseTheme.rose, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove filter \(token.title)")
                }
                Button("Clear all") {
                    filters = GuestFilterSet()
                }
                .font(.system(size: 16, weight: .medium))
                .tint(VowbaseTheme.mutedInk)
            }
        }
    }

    private var tokens: [GuestFilterToken] {
        GuestFilterToken.tokens(for: filters, columns: store.visibleCustomColumns)
    }

    // MARK: List and empty states

    @ViewBuilder
    private var guestList: some View {
        if visibleGuests.isEmpty {
            emptyState
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(visibleGuests.enumerated()), id: \.element.id) { index, guest in
                    NavigationLink(value: guest) {
                        GuestRow(guest: guest)
                    }
                    .buttonStyle(.plain)
                    if index < visibleGuests.count - 1 {
                        Divider().padding(.leading, 72)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if records.isEmpty {
            ContentUnavailableView {
                Text("Start your guest list.")
            } description: {
                Text("Add the people you want there, then track RSVPs and where they’re travelling from.")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        } else if filters.conditionCount > 0 {
            VStack(spacing: 12) {
                ContentUnavailableView(
                    "No guests match these filters",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(filterSummary)
                )
                Button("Clear filters") {
                    filters = GuestFilterSet()
                }
                .font(.system(size: 16, weight: .semibold))
                .tint(VowbaseTheme.rose)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        } else {
            ContentUnavailableView(
                "No guests match “\(query)”",
                systemImage: "magnifyingglass",
                description: Text("Search covers names, email, phone, custom fields, and city.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        }
    }

    private var filterSummary: String {
        "Active: " + tokens.map(\.title).joined(separator: ", ")
    }
}

enum GuestsRoute: Hashable {
    case customFields
}

/// One removable condition shown beneath the chips.
private struct GuestFilterToken: Identifiable {
    let id: String
    let title: String
    let remove: (inout GuestFilterSet) -> Void

    static func tokens(
        for filters: GuestFilterSet,
        columns: [GuestCustomColumn]
    ) -> [GuestFilterToken] {
        var tokens = [GuestFilterToken]()

        for status in RSVPStatus.allCases where filters.rsvpStatuses.contains(status) {
            tokens.append(
                GuestFilterToken(id: "rsvp-\(status.rawValue)", title: status.title) { set in
                    set.rsvpStatuses.remove(status)
                }
            )
        }
        for bucket in filters.locations.sorted(by: { $0.title < $1.title }) {
            tokens.append(
                GuestFilterToken(id: "location-\(bucket.title)", title: bucket.title) { set in
                    set.locations.remove(bucket)
                }
            )
        }
        if filters.mappableOnly {
            tokens.append(GuestFilterToken(id: "mappable", title: "Mappable only") { $0.mappableOnly = false })
        }
        if filters.email != .any {
            let title = filters.email == .present ? "Has email" : "No email"
            tokens.append(GuestFilterToken(id: "email", title: title) { $0.email = .any })
        }
        if filters.phone != .any {
            let title = filters.phone == .present ? "Has phone" : "No phone"
            tokens.append(GuestFilterToken(id: "phone", title: title) { $0.phone = .any })
        }
        for column in columns {
            guard let condition = filters.customConditions[column.key], condition.isActive else { continue }
            let value: String
            switch condition {
            case let .anyOf(values):
                value = values
                    .sorted()
                    .map { $0 == GuestCustomCondition.emptyToken ? "Empty" : $0 }
                    .joined(separator: ", ")
            case let .checkbox(expected):
                value = expected ? "Yes" : "No"
            }
            tokens.append(
                GuestFilterToken(id: "custom-\(column.key)", title: "\(column.label): \(value)") { set in
                    set.customConditions.removeValue(forKey: column.key)
                }
            )
        }
        return tokens
    }
}

/// Structured conditions, not a query builder.
///
/// One sentence at the top states the AND/OR rule, which is what lets the sheet
/// omit a boolean operator control entirely.
@MainActor
private struct GuestFilterSheet: View {
    let store: VowbaseWorkspaceStore
    let searchText: String
    @Binding var filters: GuestFilterSet
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GuestFilterSet
    @State private var expandedColumn: String?

    init(store: VowbaseWorkspaceStore, searchText: String, filters: Binding<GuestFilterSet>) {
        self.store = store
        self.searchText = searchText
        _filters = filters
        _draft = State(initialValue: filters.wrappedValue)
    }

    private var records: [Guest] { store.allGuestRecords }

    /// The exact list the button promises, search included, so the count can
    /// never disagree with what appears after applying.
    private var previewCount: Int {
        GuestQuery.apply(
            to: records,
            columns: store.visibleCustomColumns,
            searchText: searchText,
            filters: draft,
            sort: .nameAscending
        ).count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Guests match **all** of the conditions below.")
                        .font(.footnote)
                        .foregroundStyle(VowbaseTheme.mutedInk)
                        .listRowBackground(Color.clear)
                }
                rsvpSection
                locationSection
                detailsSection
                customSection
            }
            .scrollContentBackground(.hidden)
            .background(VowbaseTheme.groupedBackground)
            .tint(VowbaseTheme.rose)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                footer
            }
        }
    }

    private var rsvpSection: some View {
        Section("RSVP") {
            ForEach(RSVPStatus.allCases, id: \.self) { status in
                checkRow(
                    title: status.title,
                    count: GuestQuery.count(records, rsvp: status),
                    isOn: draft.rsvpStatuses.contains(status)
                ) {
                    if draft.rsvpStatuses.contains(status) {
                        draft.rsvpStatuses.remove(status)
                    } else {
                        draft.rsvpStatuses.insert(status)
                    }
                }
            }
        }
    }

    private var locationSection: some View {
        Section {
            ForEach(GuestQuery.locationBuckets(in: records), id: \.self) { bucket in
                checkRow(
                    title: bucket.title,
                    count: GuestQuery.count(records, in: bucket),
                    isOn: draft.locations.contains(bucket)
                ) {
                    if draft.locations.contains(bucket) {
                        draft.locations.remove(bucket)
                    } else {
                        draft.locations.insert(bucket)
                    }
                }
            }
            Toggle("Only mappable guests", isOn: $draft.mappableOnly)
                .tint(VowbaseTheme.rose)
        } header: {
            Text("Location")
        } footer: {
            Text("Mappable means the address resolved to city precision, which is all the map ever receives.")
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            presenceRow("Email", selection: $draft.email)
            presenceRow("Phone", selection: $draft.phone)
        }
    }

    @ViewBuilder
    private var customSection: some View {
        let columns = store.visibleCustomColumns
        if store.customFieldsUnavailable {
            Section("Custom fields") {
                Text("Custom fields couldn’t be loaded, so they can’t be filtered right now.")
                    .font(.footnote)
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
        } else if !columns.isEmpty {
            Section("Custom fields") {
                ForEach(columns) { column in
                    customRows(for: column)
                }
            }
        }
    }

    @ViewBuilder
    private func customRows(for column: GuestCustomColumn) -> some View {
        switch column.kind {
        case .checkbox:
            let current = draft.customConditions[column.key]
            LabeledContent(column.label) {
                Picker(column.label, selection: Binding(
                    get: {
                        if case let .checkbox(flag) = current { return flag ? "yes" : "no" }
                        return "any"
                    },
                    set: { value in
                        switch value {
                        case "yes": draft.customConditions[column.key] = .checkbox(true)
                        case "no": draft.customConditions[column.key] = .checkbox(false)
                        default: draft.customConditions.removeValue(forKey: column.key)
                        }
                    }
                )) {
                    Text("Any").tag("any")
                    Text("Yes").tag("yes")
                    Text("No").tag("no")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)
            }
        case .select, .text, .number:
            let counts = GuestQuery.optionCounts(records, column: column)
            let selected = selectedValues(for: column.key)
            Button {
                expandedColumn = expandedColumn == column.key ? nil : column.key
            } label: {
                HStack {
                    Text(column.label).foregroundStyle(VowbaseTheme.ink)
                    Spacer()
                    Text(summary(for: column))
                        .foregroundStyle(selected.isEmpty ? VowbaseTheme.mutedInk : VowbaseTheme.rose)
                        .lineLimit(1)
                    Image(systemName: expandedColumn == column.key ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }
            }
            if expandedColumn == column.key {
                ForEach(availableValues(for: column, counts: counts.options), id: \.self) { value in
                    checkRow(
                        title: value,
                        count: counts.options[value] ?? 0,
                        isOn: selected.contains(value),
                        indented: true
                    ) {
                        toggleValue(value, for: column.key)
                    }
                }
                checkRow(
                    title: "Empty",
                    count: counts.empty,
                    isOn: selected.contains(GuestCustomCondition.emptyToken),
                    indented: true
                ) {
                    toggleValue(GuestCustomCondition.emptyToken, for: column.key)
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                filters = draft
                dismiss()
            } label: {
                Text(previewCount == 0
                     ? "No guests match"
                     : "Show \(previewCount) guest\(previewCount == 1 ? "" : "s")")
            }
            .buttonStyle(VowbasePrimaryButtonStyle())
            .disabled(previewCount == 0)

            if previewCount == 0 {
                Text("Loosen a condition to get results back.")
                    .font(.footnote)
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }

            Button("Clear all") {
                draft = GuestFilterSet()
                expandedColumn = nil
            }
            .font(.system(size: 16))
            .tint(VowbaseTheme.rose)
            .disabled(draft.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    // MARK: Row helpers

    private func checkRow(
        title: String,
        count: Int,
        isOn: Bool,
        indented: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 19))
                    .foregroundStyle(isOn ? VowbaseTheme.rose : VowbaseTheme.mutedInk)
                Text(title)
                    .foregroundStyle(VowbaseTheme.ink)
                Spacer()
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
            .padding(.leading, indented ? 16 : 0)
        }
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func presenceRow(_ label: String, selection: Binding<GuestPresenceFilter>) -> some View {
        LabeledContent(label) {
            Picker(label, selection: selection) {
                ForEach(GuestPresenceFilter.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 170)
        }
    }

    // MARK: Condition plumbing

    private func selectedValues(for key: String) -> Set<String> {
        if case let .anyOf(values) = draft.customConditions[key] { return values }
        return []
    }

    private func toggleValue(_ value: String, for key: String) {
        var values = selectedValues(for: key)
        if values.contains(value) {
            values.remove(value)
        } else {
            values.insert(value)
        }
        if values.isEmpty {
            draft.customConditions.removeValue(forKey: key)
        } else {
            draft.customConditions[key] = .anyOf(values)
        }
    }

    /// Declared options plus any value guests actually hold, so a renamed or
    /// removed option is still filterable while data references it.
    private func availableValues(for column: GuestCustomColumn, counts: [String: Int]) -> [String] {
        var values = GuestCustomFields.options(in: column)
        for stored in counts.keys where !values.contains(stored) {
            values.append(stored)
        }
        return values
    }

    private func summary(for column: GuestCustomColumn) -> String {
        switch draft.customConditions[column.key] {
        case let .anyOf(values) where !values.isEmpty:
            return values
                .sorted()
                .map { $0 == GuestCustomCondition.emptyToken ? "Empty" : $0 }
                .joined(separator: ", ")
        case let .checkbox(flag):
            return flag ? "Yes" : "No"
        default:
            return "Any"
        }
    }
}

private struct GuestRow: View {
    let guest: MVPGuest

    var body: some View {
        HStack(spacing: 14) {
            Text(guest.initials)
                .font(.system(size: 22, weight: .regular, design: .serif))
                .frame(width: 58, height: 58)
                .background(VowbaseTheme.blush, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(guest.name)
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                    .foregroundStyle(VowbaseTheme.ink)
                if let subtitle = guest.subtitle {
                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(VowbaseTheme.mutedInk)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            RSVPStatusCapsule(status: guest.rsvp)
        }
        .padding(.vertical, 18)
        .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview("Filters") {
    @Previewable @State var filters = GuestFilterSet()
    GuestFilterSheet(
        store: VowbaseWorkspaceStore(testingWorkspace: true),
        searchText: "",
        filters: $filters
    )
}
#endif
