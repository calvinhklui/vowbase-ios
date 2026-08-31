import SwiftUI

struct VenueMetricPills: View {
    let configuration: VenueMetricConfiguration
    let venues: [Venue]
    @Binding var selectedMetricID: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(configuration.shownMetrics) { metric in
                    let isSelected = selectedMetricID == metric.id
                    let count = metric.count(in: venues)

                    Button {
                        selectedMetricID = isSelected ? nil : metric.id
                    } label: {
                        CompactMetricFilterPill(
                            count: count,
                            title: metric.cardTitle,
                            isSelected: isSelected
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(metric.name), \(count) venue\(count == 1 ? "" : "s")")
                    .accessibilityHint(isSelected ? "Double tap to show all venues" : "Double tap to filter the venue list")
                }
            }
        }
        .scrollDisabled(false)
        .contentMargins(.horizontal, 1, for: .scrollContent)
        .animation(.easeInOut(duration: 0.18), value: selectedMetricID)
    }
}

@MainActor
struct CustomizeVenueMetricsView: View {
    @Binding var configuration: VenueMetricConfiguration
    let columns: [VenueCustomColumn]
    let venues: [Venue]
    let allowsVerticalScrolling: Bool
    let onRequestExpansion: () -> Void
    let onRequestCollapse: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: VenueMetricConfiguration

    init(
        configuration: Binding<VenueMetricConfiguration>,
        columns: [VenueCustomColumn],
        venues: [Venue],
        allowsVerticalScrolling: Bool,
        onRequestExpansion: @escaping () -> Void,
        onRequestCollapse: @escaping () -> Void
    ) {
        _configuration = configuration
        self.columns = columns
        self.venues = venues
        self.allowsVerticalScrolling = allowsVerticalScrolling
        self.onRequestExpansion = onRequestExpansion
        self.onRequestCollapse = onRequestCollapse
        _draft = State(initialValue: configuration.wrappedValue.normalized(columns: columns))
    }

    var body: some View {
        Form {
            Section {
                Text("Drag to reorder. Cards filter the venue list when tapped. Metrics are shared with the web app.")
                    .font(.footnote)
                    .foregroundStyle(VowbaseTheme.mutedInk)
                    .listRowBackground(Color.clear)
            }

            Section("Shown on Venues") {
                ForEach(draft.shownMetrics) { metric in
                    metricRow(metric, action: { draft.disable(metric.id) }, actionSymbol: "minus")
                }
                .onMove { source, destination in
                    draft.moveShown(from: source, to: destination)
                }
            }

            Section("Available Metrics") {
                ForEach(draft.availableMetrics) { metric in
                    metricRow(metric, action: { draft.enable(metric.id) }, actionSymbol: "plus")
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .consoleVerticalScrollHandoff(
            allowsVerticalScrolling: allowsVerticalScrolling,
            onExpand: onRequestExpansion,
            onCollapse: onRequestCollapse
        )
        .scrollContentBackground(.hidden)
        .background(VowbaseTheme.groupedBackground)
        .tint(VowbaseTheme.rose)
        .navigationTitle("Customize Metrics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    configuration = draft
                    dismiss()
                }
            }
        }
    }

    private func metricRow(
        _ metric: VenueMetric,
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
private struct AddVenueMetricView: View {
    let columns: [VenueCustomColumn]
    let venues: [Venue]
    let onAdd: (String, VenueMetricCondition) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var fieldID = "status"
    @State private var status = VenueStatus.considering
    @State private var presence = VenueMetricPresence.absent
    @State private var customValue = ""
    @State private var checkboxValue = true

    private var fields: [MetricField] {
        [.status, .location, .capacity, .estimate] + columns.map(MetricField.custom)
    }

    private var field: MetricField {
        fields.first(where: { $0.id == fieldID }) ?? .status
    }

    private var values: [String] {
        guard case let .custom(column) = field else { return [] }
        let fromVenues = venues.compactMap { venue in
            VenueCustomFields.displayText(
                VenueCustomFields.value(in: venue.customFields, for: column.key),
                kind: column.kind
            )
        }
        let configured = column.kind == .rank
            ? (1...5).map(String.init)
            : VenueCustomFields.options(in: column)
        return Array(Set(configured + fromVenues)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private var condition: VenueMetricCondition? {
        switch field {
        case .status:
            return .status([status])
        case .location:
            return .location(presence)
        case .capacity:
            return .capacity(presence)
        case .estimate:
            return .estimate(presence)
        case let .custom(column):
            switch column.kind {
            case .checkbox:
                return .customCheckbox(key: column.key, expected: checkboxValue)
            case .text, .number, .select, .rank:
                guard !customValue.isEmpty else { return nil }
                return .customValue(key: column.key, value: customValue)
            }
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var previewCount: Int { condition.map { condition in venues.count(where: condition.matches) } ?? 0 }

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

                Section("Count venues where") {
                    Picker("Field", selection: $fieldID) {
                        ForEach(fields) { field in
                            Text(field.title).tag(field.id)
                        }
                    }

                    LabeledContent("Condition") {
                        Text("is")
                            .foregroundStyle(VowbaseTheme.mutedInk)
                    }

                    conditionValueControl

                    if let condition {
                        Text("\(condition.summary(columns: columns)) · \(previewCount) venue\(previewCount == 1 ? "" : "s") match")
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
        case .status:
            Picker("Value", selection: $status) {
                ForEach(VenueStatus.metricOrder, id: \.self) { status in
                    Text(status.title).tag(status)
                }
            }
        case .location, .capacity, .estimate:
            Picker("Value", selection: $presence) {
                Text("Has a value").tag(VenueMetricPresence.present)
                Text("Missing").tag(VenueMetricPresence.absent)
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
        case status
        case location
        case capacity
        case estimate
        case custom(VenueCustomColumn)

        var id: String {
            switch self {
            case .status: "status"
            case .location: "location"
            case .capacity: "capacity"
            case .estimate: "estimate"
            case let .custom(column): "custom-\(column.key)"
            }
        }

        var title: String {
            switch self {
            case .status: "Status"
            case .location: "Location"
            case .capacity: "Capacity"
            case .estimate: "Estimate"
            case let .custom(column): column.label
            }
        }
    }
}
