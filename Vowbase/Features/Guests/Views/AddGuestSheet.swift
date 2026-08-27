import SwiftUI
import UIKit

/// Creation stays an atomic commit with an explicit Save.
///
/// Inline autosave is right for a record that exists and wrong for one that
/// does not, so this sheet keeps a Save button — but it no longer caps what can
/// be captured. Essentials sit at the medium detent; More details grows the
/// sheet in place so the name you just typed stays visible.
@MainActor
struct AddGuestSheet: View {
    let store: VowbaseWorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFirstNameFocused: Bool

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var location = ""
    @State private var selection: AppleMapsAddressSelection?
    @State private var email = ""
    @State private var phone = ""
    @State private var rsvp: RSVPStatus = .notInvited
    @State private var plusLimit = 0
    @State private var plusGuests = [PlusGuestEntry]()
    @State private var customValues = [String: JSONValue]()
    @State private var isSaving = false
    @State private var failureMessage: String?
    @State private var detent: PresentationDetent = .medium

    /// Someone who adds one guest with a meal choice is adding forty, so the
    /// disclosure state persists for the session.
    @AppStorage("guestAddShowsMoreDetails") private var showsMoreDetails = false

    private var canSave: Bool { !firstName.trimmed.isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                essentialsSection
                if showsMoreDetails {
                    moreDetailsSection
                }
                if let failureMessage {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(failureMessage)
                                .font(.footnote)
                                .foregroundStyle(VowbaseTheme.rose)
                            Button("Retry") { save() }
                                .font(.footnote.weight(.semibold))
                                .buttonStyle(.bordered)
                                .tint(VowbaseTheme.rose)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .contentMargins(.horizontal, VowbaseControlMetric.screenInset, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(VowbaseTheme.background)
            .tint(VowbaseTheme.rose)
            .navigationTitle("Add Guest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear { isFirstNameFocused = true }
        }
        .presentationDetents([.medium, .large], selection: $detent)
    }

    // MARK: Sections

    private var essentialsSection: some View {
        Section {
            TextField("First name", text: $firstName)
                .focused($isFirstNameFocused)
                .textInputAutocapitalization(.words)
            TextField("Last name (optional)", text: $lastName)
                .textInputAutocapitalization(.words)
            Picker("RSVP", selection: $rsvp) {
                ForEach(RSVPStatus.allCases, id: \.self) { status in
                    Text(status.title).tag(status)
                }
            }
            AppleMapsAddressField(
                text: $location,
                selection: $selection,
                placeholder: "Address or location (optional)"
            )
            Picker("Additional guests", selection: $plusLimit) {
                Text("None").tag(0)
                ForEach(1...10, id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            }
            .onChange(of: plusLimit) { _, count in
                if count < plusGuests.count {
                    plusGuests.removeLast(plusGuests.count - count)
                } else {
                    plusGuests.append(contentsOf: (plusGuests.count..<count).map { _ in PlusGuestEntry() })
                }
            }
            ForEach($plusGuests) { $plus in
                LabeledContent("Plus guest") {
                    VStack(alignment: .trailing, spacing: 6) {
                        TextField("First name", text: $plus.firstName)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                        TextField("Last name", text: $plus.lastName)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                    }
                }
            }

            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    showsMoreDetails.toggle()
                    // Grow in place rather than pushing: the essentials must
                    // stay on screen while the rest is filled in.
                    detent = showsMoreDetails ? .large : .medium
                }
            } label: {
                HStack {
                    Spacer()
                    Text(showsMoreDetails ? "Fewer details" : "More details")
                    Image(systemName: showsMoreDetails ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                    Spacer()
                }
            }
            .tint(VowbaseTheme.rose)
            .accessibilityHint(showsMoreDetails
                               ? "Hides contact and custom fields"
                               : "Shows contact and custom fields")
        }
    }

    /// Contact and custom fields share one section rather than three separate
    /// blocks of header/footer chrome — the disclosure button already explains
    /// what "More details" reveals, so the fields don't need their own
    /// sub-headings to be legible.
    private var moreDetailsSection: some View {
        Section {
            TextField("Email (optional)", text: $email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
            TextField("Phone (optional)", text: $phone)
                .keyboardType(.phonePad)
            ForEach(store.visibleCustomColumns) { column in
                customField(column)
            }
        } footer: {
            if store.customFieldsUnavailable {
                Text("Custom fields couldn’t be loaded. You can still save this guest and fill them in later.")
            } else if store.visibleCustomColumns.isEmpty {
                Text("Add custom fields from Manage fields on the Guests tab.")
            }
        }
    }

    @ViewBuilder
    private func customField(_ column: GuestCustomColumn) -> some View {
        switch column.kind {
        case .checkbox:
            Toggle(column.label, isOn: Binding(
                get: { customValues[column.key] == .bool(true) },
                set: { customValues[column.key] = $0 ? .bool(true) : nil }
            ))
            .tint(VowbaseTheme.rose)

        case .select:
            Picker(column.label, selection: Binding(
                get: { GuestCustomFields.displayText(customValues[column.key], kind: column.kind) ?? "" },
                set: { customValues[column.key] = $0.isEmpty ? nil : .string($0) }
            )) {
                Text("Not set").tag("")
                ForEach(GuestCustomFields.options(in: column), id: \.self) { option in
                    Text(option).tag(option)
                }
            }

        case .text, .number:
            // A bare TextField loses its identity once filled in — its
            // placeholder is the only label, and placeholders disappear on
            // input. LabeledContent keeps the field's name pinned in place,
            // matching how Group and Meal choice already read.
            LabeledContent(column.label) {
                TextField("", text: Binding(
                    get: { GuestCustomFields.displayText(customValues[column.key], kind: column.kind) ?? "" },
                    set: { customValues[column.key] = GuestCustomFields.encode($0, kind: column.kind) }
                ))
                .multilineTextAlignment(.trailing)
                .keyboardType(column.kind == .number ? .decimalPad : .default)
            }
        }
    }

    // MARK: Save

    private func save() {
        isSaving = true
        failureMessage = nil
        Task {
            let created = await store.createGuest(
                firstName: firstName,
                lastName: lastName,
                location: location,
                selection: selection,
                rsvp: rsvp,
                email: email,
                phone: phone,
                plusGuests: plusGuests.map { GuestPlusDraft(firstName: $0.firstName, lastName: $0.lastName) },
                customFields: customValues
            )
            isSaving = false
            guard let created else {
                // Everything entered stays on the sheet; only the error is new.
                failureMessage = store.errorMessage ?? "Couldn’t save this guest. Your details are still here."
                return
            }
            _ = created
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        }
    }
}

private struct PlusGuestEntry: Identifiable {
    let id = UUID()
    var firstName = ""
    var lastName = ""
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfBlank: String? { trimmed.isEmpty ? nil : trimmed }
}

#if DEBUG
#Preview("Add guest") {
    AddGuestSheet(store: VowbaseWorkspaceStore(testingWorkspace: true))
}
#endif
