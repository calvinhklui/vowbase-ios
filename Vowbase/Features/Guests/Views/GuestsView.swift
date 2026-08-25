import SwiftUI

// MARK: - Guests

/// The Guests lens content stays mounted as the console moves through its
/// detents. Its own header is gone; the shared `ConsoleHeader` covers it.
@MainActor
struct GuestsView: View {
    let store: VowbaseWorkspaceStore
    /// Owned by `WeddingAppShell` — see `VenuesView.path`'s doc comment.
    @Binding var path: NavigationPath
    @State private var query = ""
    @State private var filters = GuestFilterSet()
    @State private var sort: GuestSortOrder = .nameAscending
    @State private var showsFilter = false
    @State private var metricConfiguration = GuestMetricConfiguration.default(columns: [])
    @State private var selectedMetricID: String?

    private var visibleGuests: [MVPGuest] {
        store.filteredGuests(
            searchText: query,
            filters: filters,
            sort: sort,
            metric: selectedMetric
        )
    }

    private var records: [Guest] { store.allGuestRecords }
    private var selectedMetric: GuestMetric? {
        metricConfiguration.metrics.first(where: { $0.id == selectedMetricID })
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    metricCards
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
                case .customizeMetrics:
                    CustomizeGuestMetricsView(
                        configuration: $metricConfiguration,
                        columns: store.visibleCustomColumns,
                        guests: records
                    )
                case .customFields:
                    GuestFieldListView(store: store)
                }
            }
            .sheet(isPresented: $showsFilter) {
                GuestFilterSheet(store: store, searchText: query, filters: $filters)
            }
            .task(id: store.wedding?.id) {
                let configuration = GuestMetricConfigurationStorage.load(
                    weddingID: store.wedding?.id,
                    columns: store.visibleCustomColumns
                )
                metricConfiguration = configuration
                if let selectedMetricID,
                   !configuration.shownMetrics.contains(where: { $0.id == selectedMetricID }) {
                    self.selectedMetricID = nil
                }
            }
            .onChange(of: metricConfiguration) { _, configuration in
                if let selectedMetricID,
                   !configuration.shownMetrics.contains(where: { $0.id == selectedMetricID }) {
                    self.selectedMetricID = nil
                }
                GuestMetricConfigurationStorage.save(configuration, weddingID: store.wedding?.id)
            }
            .onChange(of: store.visibleCustomColumns) { _, columns in
                metricConfiguration = metricConfiguration.normalized(columns: columns)
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
            Button {
                path.append(GuestsRoute.customizeMetrics)
            } label: {
                Label("Customize metrics", systemImage: "slider.horizontal.3")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(VowbaseTheme.ink)
                .frame(width: 52, height: 52)
                .background(VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VowbaseTheme.border, lineWidth: 1))
        }
        .accessibilityLabel("Sort, manage fields, and customize metrics")
    }

    private var metricCards: some View {
        GuestMetricCards(
            configuration: metricConfiguration,
            guests: records,
            selectedMetricID: $selectedMetricID
        )
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
            GuestLedger(
                guests: visibleGuests,
                customColumns: store.visibleCustomColumns,
                store: store
            )
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
        } else if filters.conditionCount > 0 || selectedMetric != nil {
            VStack(spacing: 12) {
                ContentUnavailableView(
                    "No guests match these filters",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(filterSummary)
                )
                Button("Clear filters") {
                    filters = GuestFilterSet()
                    selectedMetricID = nil
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
        let parts = tokens.map(\.title) + (selectedMetric.map { [$0.name] } ?? [])
        return "Active: " + parts.joined(separator: ", ")
    }
}

enum GuestsRoute: Hashable {
    case customizeMetrics
    case customFields
}

enum GuestMetricConfigurationStorage {
    private static let keyPrefix = "guestMetricConfiguration."

    static func load(weddingID: UUID?, columns: [GuestCustomColumn]) -> GuestMetricConfiguration {
        let fallback = GuestMetricConfiguration.default(columns: columns)
        guard let weddingID,
              let data = UserDefaults.standard.data(forKey: key(for: weddingID)),
              let stored = try? JSONDecoder().decode(GuestMetricConfiguration.self, from: data)
        else {
            return fallback
        }
        return stored.normalized(columns: columns)
    }

    static func save(_ configuration: GuestMetricConfiguration, weddingID: UUID?) {
        guard let weddingID,
              let data = try? JSONEncoder().encode(configuration) else { return }
        UserDefaults.standard.set(data, forKey: key(for: weddingID))
    }

    private static func key(for weddingID: UUID) -> String {
        keyPrefix + weddingID.uuidString.lowercased()
    }
}

/// Shared metric filter control for the full Guests list and the console's
/// compact guest rail. Its selection is intentionally binding-driven so each
/// host decides how the selected metric filters or orders its own guest list.
struct GuestMetricCards: View {
    let configuration: GuestMetricConfiguration
    let guests: [Guest]
    @Binding var selectedMetricID: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: VowbaseSpace.small) {
                ForEach(configuration.shownMetrics) { metric in
                    let isSelected = selectedMetricID == metric.id

                    Button {
                        selectedMetricID = isSelected ? nil : metric.id
                    } label: {
                        GuestMetricCard(
                            metric: metric,
                            guestCount: metric.count(in: guests),
                            isSelected: isSelected
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(metric.name), \(metric.count(in: guests)) guests")
                    .accessibilityHint(isSelected ? "Double tap to show all guests" : "Double tap to filter the guest list")
                }
            }
            .padding(.vertical, VowbaseSpace.small)
        }
        .contentMargins(.horizontal, 1, for: .scrollContent)
        .animation(.easeInOut(duration: 0.18), value: selectedMetricID)
    }
}

private struct GuestMetricCard: View {
    let metric: GuestMetric
    let guestCount: Int
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: VowbaseSpace.xSmall) {
            Text("\(guestCount)")
                .font(.system(.title2, design: .serif, weight: .regular))
                .foregroundStyle(isSelected ? VowbaseTheme.rose : VowbaseTheme.ink)
                .monospacedDigit()
            Spacer(minLength: 0)
            Text(metric.cardTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? VowbaseTheme.rose : VowbaseTheme.mutedInk)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, VowbaseSpace.medium)
        .padding(.vertical, 10)
        .frame(width: 88, height: 76, alignment: .leading)
        .background(
            isSelected ? VowbaseTheme.blush : VowbaseDesign.surface,
            in: RoundedRectangle(cornerRadius: VowbaseRadius.small, style: .continuous)
        )
        .overlay {
            if !isSelected {
                RoundedRectangle(cornerRadius: VowbaseRadius.small, style: .continuous)
                    .stroke(VowbaseTheme.border.opacity(0.3), lineWidth: 1)
            }
        }
    }
}

@MainActor
private struct CustomizeGuestMetricsView: View {
    @Binding var configuration: GuestMetricConfiguration
    let columns: [GuestCustomColumn]
    let guests: [Guest]

    @Environment(\.dismiss) private var dismiss
    @State private var draft: GuestMetricConfiguration
    @State private var showsAddMetric = false

    init(
        configuration: Binding<GuestMetricConfiguration>,
        columns: [GuestCustomColumn],
        guests: [Guest]
    ) {
        _configuration = configuration
        self.columns = columns
        self.guests = guests
        _draft = State(initialValue: configuration.wrappedValue.normalized(columns: columns))
    }

    var body: some View {
        Form {
            Section {
                Text("Choose up to \(GuestMetricConfiguration.maximumShownMetrics) cards. Drag to reorder. Cards filter the guest list when tapped.")
                    .font(.footnote)
                    .foregroundStyle(VowbaseTheme.mutedInk)
                    .listRowBackground(Color.clear)
            }

            Section("Shown on Guests") {
                ForEach(draft.shownMetrics) { metric in
                    metricRow(metric, action: { draft.disable(metric.id) }, actionSymbol: "minus")
                }
                .onMove { source, destination in
                    draft.moveShown(from: source, to: destination)
                }
            }

            Section("Available Metrics") {
                Button {
                    showsAddMetric = true
                } label: {
                    Label("Add Metric", systemImage: "plus.circle")
                        .foregroundStyle(VowbaseTheme.rose)
                }
                .disabled(draft.shownMetrics.count >= GuestMetricConfiguration.maximumShownMetrics)

                ForEach(draft.availableMetrics) { metric in
                    metricRow(metric, action: { draft.enable(metric.id) }, actionSymbol: "plus")
                        .disabled(draft.shownMetrics.count >= GuestMetricConfiguration.maximumShownMetrics)
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .background(VowbaseTheme.groupedBackground)
        .tint(VowbaseTheme.rose)
        .navigationTitle("Customize metrics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    configuration = draft
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showsAddMetric) {
            AddGuestMetricView(columns: columns, guests: guests) { name, condition in
                _ = draft.addCustom(name: name, condition: condition)
            }
        }
    }

    private func metricRow(
        _ metric: GuestMetric,
        action: @escaping () -> Void,
        actionSymbol: String
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(metric.name)
                    .foregroundStyle(VowbaseTheme.ink)
                Text(metric.condition.summary(columns: columns))
                    .font(.footnote)
                    .foregroundStyle(VowbaseTheme.mutedInk)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button(action: action) {
                Image(systemName: actionSymbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(VowbaseTheme.rose)
                    .frame(width: 32, height: 32)
                    .background(VowbaseTheme.blush, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(actionSymbol == "minus" ? "Hide \(metric.name)" : "Show \(metric.name)")
        }
        .padding(.vertical, 5)
    }
}

@MainActor
private struct AddGuestMetricView: View {
    let columns: [GuestCustomColumn]
    let guests: [Guest]
    let onAdd: (String, GuestMetricCondition) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var fieldID = "rsvp"
    @State private var rsvp = RSVPStatus.accepted
    @State private var addressPresence = GuestPresenceFilter.absent
    @State private var customValue = ""
    @State private var checkboxValue = true

    private var fields: [MetricField] {
        [.rsvp, .address] + columns.map(MetricField.custom)
    }

    private var field: MetricField {
        fields.first(where: { $0.id == fieldID }) ?? .rsvp
    }

    private var values: [String] {
        guard case let .custom(column) = field else { return [] }
        let fromGuests = guests.compactMap { guest in
            GuestCustomFields.displayText(
                GuestCustomFields.value(in: guest.customFields, for: column.key),
                kind: column.kind
            )
        }
        let options = GuestCustomFields.options(in: column)
        return Array(Set(options + fromGuests)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var condition: GuestMetricCondition? {
        switch field {
        case .rsvp:
            return .rsvp([rsvp])
        case .address:
            return .address(addressPresence)
        case let .custom(column):
            switch column.kind {
            case .checkbox:
                return .customCheckbox(key: column.key, expected: checkboxValue)
            case .text, .number, .select:
                guard !customValue.isEmpty else { return nil }
                return .customValue(key: column.key, value: customValue)
            }
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var previewCount: Int { condition.map { $0.matchesCount(in: guests) } ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Preview") {
                    VStack(spacing: 8) {
                        Text(trimmedName.isEmpty ? "New metric" : trimmedName)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(VowbaseTheme.mutedInk)
                        Text("\(previewCount)")
                            .font(.system(size: 34, weight: .regular, design: .rounded))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .listRowBackground(VowbaseTheme.background)
                }

                Section("Card") {
                    TextField("Metric name", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section("Count guests where") {
                    Picker("Field", selection: $fieldID) {
                        ForEach(fields) { field in
                            Text(field.title).tag(field.id)
                        }
                    }

                    LabeledContent("Condition") {
                        Text(field.conditionLabel)
                            .foregroundStyle(VowbaseTheme.mutedInk)
                    }

                    conditionValueControl

                    if let condition {
                        Text("\(condition.summary(columns: columns)) · \(previewCount) guest\(previewCount == 1 ? "" : "s") match")
                            .font(.footnote)
                            .foregroundStyle(VowbaseTheme.mutedInk)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(VowbaseTheme.groupedBackground)
            .tint(VowbaseTheme.rose)
            .navigationTitle("Add metric")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let condition else { return }
                        onAdd(trimmedName, condition)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty || condition == nil)
                }
            }
            .onChange(of: fieldID) { _, _ in
                customValue = values.first ?? ""
            }
            .onAppear {
                customValue = values.first ?? ""
            }
        }
    }

    @ViewBuilder
    private var conditionValueControl: some View {
        switch field {
        case .rsvp:
            Picker("Value", selection: $rsvp) {
                ForEach(RSVPStatus.allCases, id: \.self) { status in
                    Text(status.title).tag(status)
                }
            }
        case .address:
            Picker("Value", selection: $addressPresence) {
                Text("Has address").tag(GuestPresenceFilter.present)
                Text("Missing address").tag(GuestPresenceFilter.absent)
            }
        case let .custom(column):
            if column.kind == .checkbox {
                Picker("Value", selection: $checkboxValue) {
                    Text("Yes").tag(true)
                    Text("No").tag(false)
                }
            } else if values.isEmpty {
                LabeledContent("Value") {
                    Text("No values yet")
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }
            } else {
                Picker("Value", selection: $customValue) {
                    ForEach(values, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
            }
        }
    }

    private enum MetricField: Identifiable {
        case rsvp
        case address
        case custom(GuestCustomColumn)

        var id: String {
            switch self {
            case .rsvp: "rsvp"
            case .address: "address"
            case let .custom(column): "custom-\(column.key)"
            }
        }

        var title: String {
            switch self {
            case .rsvp: "RSVP status"
            case .address: "Address"
            case let .custom(column): column.label
            }
        }

        var conditionLabel: String {
            "is"
        }
    }
}

private extension GuestMetricCondition {
    func matchesCount(in guests: [Guest]) -> Int {
        guests.count(where: matches)
    }
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

// MARK: - Guest ledger

/// A compact, spreadsheet-like guest list. The leading name column stays in
/// place while one shared horizontal scroller reveals all remaining fields.
/// Keeping every attribute row inside the same scroller is what keeps headers
/// and rows aligned as the user scrolls sideways.
@MainActor
private struct GuestLedger: View {
    let guests: [MVPGuest]
    let customColumns: [GuestCustomColumn]
    let store: VowbaseWorkspaceStore

    private let nameColumnWidth: CGFloat = 148
    private let headerHeight: CGFloat = 36
    private let rowHeight: CGFloat = 50

    private var columns: [GuestLedgerColumn] {
        let preferred = GuestDisplayResolver.subtitleColumn(in: customColumns)
        let remaining = customColumns.filter { $0.id != preferred?.id }
        let leading = preferred.map(GuestLedgerColumn.custom).map { [$0] } ?? []
        return leading
            + [.rsvp]
            + remaining.map(GuestLedgerColumn.custom)
            + [.location, .email, .phone, .plusGuests]
    }

    /// Resolve records and plus-one text once per render rather than doing
    /// store lookups from every visible cell.
    private var rows: [GuestLedgerRowModel] {
        let recordsByID = Dictionary(uniqueKeysWithValues: store.allGuestRecords.map { ($0.id, $0) })
        let namedPlusCounts = Dictionary(grouping: store.allGuestRecords.compactMap { record in
            record.plusOfGuestID.map { ($0, record) }
        }, by: \.0).mapValues(\.count)

        return guests.map { guest in
            let record = recordsByID[guest.id]
            let plusGuestsText: String?
            if let hostID = record?.plusOfGuestID, let host = recordsByID[hostID] {
                let hostName = [host.firstName, host.lastName]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                plusGuestsText = hostName.isEmpty ? "Linked guest" : "Guest of \(hostName)"
            } else if let limit = record?.plusLimit, limit > 0 {
                plusGuestsText = "\(namedPlusCounts[guest.id, default: 0]) of \(limit) named"
            } else {
                plusGuestsText = nil
            }
            return GuestLedgerRowModel(guest: guest, record: record, plusGuestsText: plusGuestsText)
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    fullWidthHeaders
                    ForEach(rows) { row in
                        NavigationLink(value: row.guest) {
                            GuestLedgerAttributeRow(
                                row: row,
                                columns: columns,
                                nameColumnWidth: nameColumnWidth,
                                rowHeight: rowHeight
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(accessibilityLabel(for: row))
                        .accessibilityHint("Shows guest details")
                        Divider()
                    }
                }
            }
            .accessibilityLabel("Guest details columns")

            nameColumnOverlay
                .frame(width: nameColumnWidth)
                .background(VowbaseTheme.background)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(VowbaseTheme.border)
                        .frame(width: 1)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private var nameColumnOverlay: some View {
        VStack(spacing: 0) {
            Text("Name")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(VowbaseTheme.mutedInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .frame(height: headerHeight)

            ForEach(rows) { row in
                Text(row.guest.name)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(VowbaseTheme.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .frame(height: rowHeight)
                Divider()
            }
        }
    }

    private var fullWidthHeaders: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: nameColumnWidth)
            ForEach(columns) { column in
                Text(column.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(VowbaseTheme.mutedInk)
                    .lineLimit(1)
                    .frame(width: column.width, alignment: .leading)
                    .padding(.horizontal, 8)
            }
        }
        .frame(height: headerHeight)
    }

    private func accessibilityLabel(for row: GuestLedgerRowModel) -> String {
        let values = columns.compactMap { column -> String? in
            let value: String?
            switch column {
            case .rsvp:
                value = row.guest.rsvp.title
            default:
                value = row.value(for: column)
            }
            return value.map { "\(column.title): \($0)" }
        }
        return (["Open \(row.guest.name)"] + values).joined(separator: ", ")
    }
}

private enum GuestLedgerColumn: Identifiable {
    case custom(GuestCustomColumn)
    case rsvp
    case location
    case email
    case phone
    case plusGuests

    var id: String {
        switch self {
        case let .custom(column): "custom-\(column.id.uuidString)"
        case .rsvp: "rsvp"
        case .location: "location"
        case .email: "email"
        case .phone: "phone"
        case .plusGuests: "plus-guests"
        }
    }

    var title: String {
        switch self {
        case let .custom(column): column.label
        case .rsvp: "RSVP"
        case .location: "Location"
        case .email: "Email"
        case .phone: "Phone"
        case .plusGuests: "Plus-one"
        }
    }

    var width: CGFloat {
        switch self {
        case .rsvp: 88
        case .location: 120
        case .email: 160
        case .phone: 120
        case .plusGuests: 132
        case .custom: 124
        }
    }
}

@MainActor
private struct GuestLedgerAttributeRow: View {
    let row: GuestLedgerRowModel
    let columns: [GuestLedgerColumn]
    let nameColumnWidth: CGFloat
    let rowHeight: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: nameColumnWidth)
            ForEach(columns) { column in
                cell(for: column)
                    .frame(width: column.width, alignment: .leading)
                    .padding(.horizontal, 8)
            }
        }
        .frame(height: rowHeight)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func cell(for column: GuestLedgerColumn) -> some View {
        switch column {
        case .rsvp:
            Text(row.guest.rsvp.title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(rsvpColor)
                .lineLimit(1)
        default:
            let value = row.value(for: column)
            Text(value ?? "—")
                .font(.system(size: 16))
                .foregroundStyle(value == nil ? VowbaseTheme.mutedInk : VowbaseTheme.ink)
                .lineLimit(1)
        }
    }

    private var rsvpColor: Color {
        switch row.guest.rsvp {
        case .maybe: VowbaseTheme.guestBlue
        case .accepted: VowbaseTheme.ink
        case .pending, .declined: VowbaseTheme.rose
        case .notInvited: VowbaseTheme.mutedInk
        }
    }

}

private struct GuestLedgerRowModel: Identifiable {
    let guest: MVPGuest
    let record: Guest?
    let plusGuestsText: String?

    var id: UUID { guest.id }

    func value(for column: GuestLedgerColumn) -> String? {
        switch column {
        case let .custom(column):
            return GuestCustomFields.displayText(
                record.flatMap { GuestCustomFields.value(in: $0.customFields, for: column.key) },
                kind: column.kind
            )
        case .location:
            return guest.location
        case .email:
            return guest.email
        case .phone:
            return guest.phone
        case .plusGuests:
            return plusGuestsText
        case .rsvp:
            return nil
        }
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
