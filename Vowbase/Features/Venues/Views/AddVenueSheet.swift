import SwiftUI
import UIKit

@MainActor
struct AddVenueSheet: View {
    let store: VowbaseWorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var name = ""
    @State private var location = ""
    @State private var selection: AppleMapsAddressSelection?
    @State private var status: VenueStatus = .considering
    @State private var customValues = [String: JSONValue]()
    @State private var showsMoreDetails = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Venue name", text: $name)
                        .focused($isNameFocused)
                        .textInputAutocapitalization(.words)
                    AppleMapsAddressField(
                        text: $location,
                        selection: $selection,
                        placeholder: "Address or location (optional)"
                    )
                    Picker("Status", selection: $status) {
                        ForEach([VenueStatus.considering, .contacted, .toured, .shortlisted], id: \.self) {
                            Text($0.title).tag($0)
                        }
                    }
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { showsMoreDetails.toggle() }
                    } label: {
                        Label(showsMoreDetails ? "Fewer details" : "More details", systemImage: showsMoreDetails ? "chevron.up" : "chevron.down")
                    }
                }
                if showsMoreDetails { customFieldsSection }
            }
            .contentMargins(.horizontal, VowbaseControlMetric.screenInset, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(VowbaseTheme.background)
            .tint(VowbaseTheme.rose)
            .navigationTitle("Add Venue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    VowbaseConfirmationToolbarButton(
                        "Save Venue",
                        isDisabled: name.trimmed.isEmpty || isSaving
                    ) {
                        saveVenue()
                    }
                }
            }
            .onAppear { isNameFocused = true }
        }
    }

    private func saveVenue() {
        isSaving = true
        Task {
            let didSave = await store.createVenue(
                name: name,
                location: location,
                selection: selection,
            status: status,
            customFields: customValues
            )
            isSaving = false
            guard didSave else {
                store.presentSaveFailure(retry: saveVenue, discard: { dismiss() })
                return
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        }
    }

    @ViewBuilder
    private var customFieldsSection: some View {
        Section("Custom Fields") {
            if store.venueCustomFieldsUnavailable {
                Text("Custom fields couldn’t be loaded. You can add this venue and fill them in later.")
                    .font(.footnote).foregroundStyle(VowbaseTheme.mutedInk)
            } else if store.visibleVenueCustomColumns.isEmpty {
                Text("No custom fields yet. Add them from Manage fields on the Venues tab.")
                    .font(.footnote).foregroundStyle(VowbaseTheme.mutedInk)
            } else {
                ForEach(store.visibleVenueCustomColumns) { column in
                    VenueCustomFieldInput(column: column, values: $customValues)
                }
            }
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfBlank: String? { trimmed.isEmpty ? nil : trimmed }
}

/// Shared creation control for all visible venue custom-field kinds. Rank is
/// deliberately an explicit five-button scale, never a free-form numeric box.
struct VenueCustomFieldInput: View {
    let column: VenueCustomColumn
    @Binding var values: [String: JSONValue]

    private var value: JSONValue? { values[column.key] }

    var body: some View {
        switch column.kind {
        case .checkbox:
            Toggle(column.label, isOn: Binding(
                get: { value == .bool(true) },
                set: { values[column.key] = $0 ? .bool(true) : .bool(false) }
            )).tint(VowbaseTheme.rose)
        case .select:
            Picker(column.label, selection: Binding(
                get: { VenueCustomFields.displayText(value, kind: .select) ?? "" },
                set: { values[column.key] = $0.isEmpty ? nil : .string($0) }
            )) {
                Text("Not set").tag("")
                ForEach(VenueCustomFields.options(in: column), id: \.self) { Text($0).tag($0) }
            }
        case .text, .number:
            LabeledContent(column.label) {
                TextField("", text: Binding(
                    get: { VenueCustomFields.displayText(value, kind: column.kind) ?? "" },
                    set: { values[column.key] = VenueCustomFields.encode($0, kind: column.kind) }
                ))
                .multilineTextAlignment(.trailing)
                .keyboardType(column.kind == .number ? .decimalPad : .default)
            }
        case .rank:
            LabeledContent(column.label) {
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { score in
                        Button("\(score)") { values[column.key] = .number(Double(score)) }
                            .buttonStyle(.bordered)
                            .tint(rank == score ? VowbaseTheme.rose : VowbaseTheme.mutedInk)
                            .accessibilityLabel("\(column.label), \(score) of 5")
                    }
                    if rank != nil {
                        Button("Clear") { values[column.key] = nil }
                            .font(.caption)
                            .accessibilityLabel("Clear \(column.label)")
                    }
                }
            }
        }
    }

    private var rank: Int? {
        guard case let .number(value)? = value, value.rounded() == value, (1...5).contains(Int(value)) else { return nil }
        return Int(value)
    }
}

#Preview("Add venue") {
    AddVenueSheet(store: VowbaseWorkspaceStore())
}
