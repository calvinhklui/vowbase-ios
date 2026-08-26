import SwiftUI
import UIKit

/// The guest record, edited in place.
///
/// There is no view mode and no edit mode: every row is a live control styled
/// to read as static text until focused, and each commits on its own.
@MainActor
struct GuestDetailView: View {
    let guest: MVPGuest
    let store: VowbaseWorkspaceStore
    let allowsVerticalScrolling: Bool
    let onRequestExpansion: () -> Void
    let onRequestCollapse: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDeletion = false
    @State private var undo: GuestUndo?

    init(
        guest: MVPGuest,
        store: VowbaseWorkspaceStore,
        allowsVerticalScrolling: Bool = true,
        onRequestExpansion: @escaping () -> Void = {},
        onRequestCollapse: @escaping () -> Void = {}
    ) {
        self.guest = guest
        self.store = store
        self.allowsVerticalScrolling = allowsVerticalScrolling
        self.onRequestExpansion = onRequestExpansion
        self.onRequestCollapse = onRequestCollapse
    }

    /// The server-confirmed record. Rows read through this so a successful save
    /// adopts whatever the server actually stored.
    private var record: Guest? { store.guestRecord(id: guest.id) }

    var body: some View {
        List {
            if let record {
                header(record)
                rsvpSection(record)
                plusGuestsSection(record)
                contactSection(record)
                locationSection(record)
                customFieldsSection(record)
                metadataSection(record)
            }
        }
        .consoleVerticalScrollHandoff(
            allowsVerticalScrolling: allowsVerticalScrolling,
            onExpand: onRequestExpansion,
            onCollapse: onRequestCollapse
        )
        .scrollContentBackground(.hidden)
        .vowbaseScrollClearance()
        .navigationTitle("Guest")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete Guest", role: .destructive) { isConfirmingDeletion = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let undo {
                GuestUndoToast(undo: undo) { self.undo = nil }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: undo?.id)
        .alert("Delete \(guest.name)?", isPresented: $isConfirmingDeletion) {
            Button("Delete Guest", role: .destructive) {
                deleteGuest()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the guest from your wedding workspace.")
        }
    }

    // MARK: Sections

    private func header(_ record: Guest) -> some View {
        Section {
            HStack(spacing: 16) {
                Text(guest.initials)
                    .font(.system(size: 30, design: .serif))
                    .frame(width: 76, height: 76)
                    .background(VowbaseTheme.blush, in: Circle())
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        GuestInlineField(
                            stored: record.firstName,
                            placeholder: "First",
                            isRequired: true,
                            font: .system(size: 21, design: .serif),
                            saveState: store.saveState(.init(guestID: guest.id, field: .firstName)),
                            capitalization: .words,
                            hugsContent: true,
                            commit: { await store.commitField(.firstName, for: guest.id, value: $0) }
                        )
                        GuestInlineField(
                            stored: record.lastName ?? "",
                            placeholder: "Last",
                            font: .system(size: 21, design: .serif),
                            saveState: store.saveState(.init(guestID: guest.id, field: .lastName)),
                            capitalization: .words,
                            hugsContent: true,
                            commit: { await store.commitField(.lastName, for: guest.id, value: $0) }
                        )
                        Spacer(minLength: 0)
                    }
                    RSVPStatusCapsule(status: record.rsvpStatus ?? .notInvited)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func rsvpSection(_ record: Guest) -> some View {
        Section {
            let key = GuestFieldKey(guestID: guest.id, field: "rsvpStatus")
            let current = record.rsvpStatus ?? .notInvited
            LabeledContent("Status") {
                HStack(spacing: 8) {
                    GuestSaveIndicator(state: store.saveState(key))
                    Menu {
                        ForEach(RSVPStatus.allCases, id: \.self) { status in
                            Button {
                                changeRSVP(to: status, from: current)
                            } label: {
                                if status == current {
                                    Label(status.title, systemImage: "checkmark")
                                } else {
                                    Text(status.title)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(current.title)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                        .foregroundStyle(VowbaseTheme.ink)
                    }
                }
            }
            if let responded = record.rsvpDate {
                LabeledContent("Responded", value: responded.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
        } header: {
            Text("RSVP")
        }
    }

    private func contactSection(_ record: Guest) -> some View {
        Section("Contact") {
            inlineRow(.email, stored: record.email ?? "", keyboard: .emailAddress)
            inlineRow(.phone, stored: record.phone ?? "", keyboard: .phonePad)
        }
    }

    @ViewBuilder
    private func plusGuestsSection(_ record: Guest) -> some View {
        if let host = store.plusHost(for: record) {
            Section("Guest group") {
                LabeledContent("Plus guest of", value: [host.firstName, host.lastName].compactMap { $0 }.joined(separator: " "))
            }
        } else if record.plusLimit > 0 {
            let linked = store.plusGuests(for: record.id)
            Section {
                LabeledContent("Places", value: "\(linked.count) of \(record.plusLimit) named")
                ForEach(linked) { plus in
                    if let destination = store.guests.first(where: { $0.id == plus.id }) {
                        NavigationLink(value: destination) {
                            Text([plus.firstName, plus.lastName].compactMap { $0 }.joined(separator: " "))
                        }
                    }
                }
                if linked.count < record.plusLimit {
                    Text("\(record.plusLimit - linked.count) open place\(record.plusLimit - linked.count == 1 ? "" : "s")")
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }
            } header: {
                Text("Additional guests")
            } footer: {
                Text("Each named plus is a regular guest linked to this invitation.")
            }
        }
    }

    private func locationSection(_ record: Guest) -> some View {
        Section("Location") {
            let key = GuestFieldKey(guestID: guest.id, field: "address")
            LabeledContent("Address") {
                GuestInlineField(
                    stored: record.address ?? "",
                    placeholder: "Not added",
                    saveState: store.saveState(key),
                    capitalization: .words,
                    commit: { await store.commitAddress(for: guest.id, value: $0) }
                )
            }
            GuestDerivedLocationRow(record: record, isResolving: store.saveState(key) == .saving)
        }
    }

    @ViewBuilder
    private func customFieldsSection(_ record: Guest) -> some View {
        let columns = store.visibleCustomColumns
        Section {
            if store.customFieldsUnavailable {
                Text("Custom fields couldn’t be loaded. The rest of this guest is up to date.")
                    .font(.footnote)
                    .foregroundStyle(VowbaseTheme.mutedInk)
            } else if columns.isEmpty {
                NavigationLink(value: GuestsRoute.customFields) {
                    Text("Add a field").foregroundStyle(VowbaseTheme.rose)
                }
            } else {
                ForEach(columns) { column in
                    GuestCustomFieldRow(
                        column: column,
                        record: record,
                        state: store.saveState(.customField(guestID: guest.id, key: column.key)),
                        commit: { value in store.commitCustomField(column, for: guest.id, value: value) },
                        onCleared: { previous in
                            offerUndo("\(column.label) cleared") {
                                store.commitCustomField(column, for: guest.id, value: previous)
                            }
                        }
                    )
                }
                NavigationLink(value: GuestsRoute.customFields) {
                    Text("Add a field").foregroundStyle(VowbaseTheme.rose)
                }
            }
        } header: {
            HStack {
                Text("Custom Fields")
                Spacer()
                NavigationLink(value: GuestsRoute.customFields) {
                    Image(systemName: "list.bullet.rectangle")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(VowbaseTheme.rose)
                .accessibilityLabel("Manage fields")
            }
            .textCase(nil)
        } footer: {
            if !columns.isEmpty {
                Text("Fields appear in the order set on Manage fields. Hidden fields keep their data.")
            }
        }
    }

    private func metadataSection(_ record: Guest) -> some View {
        Section {
            LabeledContent("Added", value: record.createdAt.formatted(date: .abbreviated, time: .omitted))
                .foregroundStyle(VowbaseTheme.mutedInk)
        }
    }

    // MARK: Helpers

    private func inlineRow(
        _ field: GuestEditableField,
        stored: String,
        keyboard: UIKeyboardType
    ) -> some View {
        LabeledContent(field.label) {
            GuestInlineField(
                stored: stored,
                placeholder: "Not added",
                isRequired: field.isRequired,
                saveState: store.saveState(.init(guestID: guest.id, field: field)),
                keyboard: keyboard,
                commit: { await store.commitField(field, for: guest.id, value: $0) }
            )
        }
    }

    private func changeRSVP(to status: RSVPStatus, from previous: RSVPStatus) {
        Task {
            guard await store.commitRSVP(status, for: guest.id) else { return }
            offerUndo("RSVP set to \(status.title)") {
                Task { await store.commitRSVP(previous, for: guest.id) }
            }
        }
    }

    private func offerUndo(_ message: String, action: @escaping () -> Void) {
        let entry = GuestUndo(message: message, action: action)
        undo = entry
        Task {
            try? await Task.sleep(for: .seconds(5))
            if undo?.id == entry.id { undo = nil }
        }
    }

    private func deleteGuest() {
        Task {
            guard await store.deleteGuest(guest) else {
                store.presentSaveFailure(retry: deleteGuest)
                return
            }
            dismiss()
        }
    }
}

private struct GuestUndo: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let action: () -> Void

    static func == (lhs: GuestUndo, rhs: GuestUndo) -> Bool { lhs.id == rhs.id }
}

private struct GuestUndoToast: View {
    let undo: GuestUndo
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(undo.message)
                .font(.system(size: 15))
                .foregroundStyle(VowbaseTheme.background)
            Spacer(minLength: 8)
            Button("Undo") {
                undo.action()
                dismiss()
            }
            .font(.system(size: 15, weight: .semibold))
            .tint(VowbaseTheme.rose)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(VowbaseTheme.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A value that reads as text and edits as text, with no mode switch.
///
/// Commits on blur or return. A failed save leaves the typed value in place
/// rather than reverting to what the server holds.
/// Reports the natural width of whatever it's attached to, so a sibling can
/// be resized to match. `TextField` alone won't hug its own text reliably
/// when unconstrained — its ideal-size computation isn't as precise as
/// `Text`'s — so measuring a hidden `Text` with the same string is the
/// robust way to size a field to its content rather than to available space.
private struct GuestInlineFieldWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct GuestInlineField: View {
    let stored: String
    var placeholder: String = "Not added"
    var isRequired: Bool = false
    var font: Font = .body
    let saveState: GuestFieldSaveState?
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    /// When true, the field sizes itself to its own text instead of expanding
    /// to fill the row — for adjacent short fields like First/Last name,
    /// where a flexible TextField would otherwise claim roughly half the row
    /// no matter how short the actual name is, leaving a wide gap between them.
    var hugsContent: Bool = false
    let commit: (String) async -> Void

    @State private var draft = ""
    @State private var showsRequiredWarning = false
    @State private var measuredWidth: CGFloat?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField(placeholder, text: $draft)
                    .font(font)
                    .focused($isFocused)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(capitalization)
                    .autocorrectionDisabled(keyboard == .emailAddress)
                    .submitLabel(.done)
                    .onSubmit { isFocused = false }
                    .background(alignment: .leading) {
                        if hugsContent {
                            Text(draft.isEmpty ? placeholder : draft)
                                .font(font)
                                .lineLimit(1)
                                .fixedSize()
                                .hidden()
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: GuestInlineFieldWidthKey.self,
                                            value: proxy.size.width
                                        )
                                    }
                                )
                        }
                    }
                    .onPreferenceChange(GuestInlineFieldWidthKey.self) { width in
                        guard hugsContent else { return }
                        measuredWidth = width
                    }
                    .frame(width: hugsContent ? max(measuredWidth ?? 0, 16) + 6 : nil)
                if saveState == .saving || saveState == .saved {
                    GuestSaveIndicator(state: saveState)
                }
            }
            .padding(.horizontal, isFocused ? 8 : 0)
            .padding(.vertical, isFocused ? 6 : 0)
            .background {
                if isFocused {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(VowbaseTheme.blush)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(VowbaseTheme.rose, lineWidth: 1.5)
                        )
                }
            }

            if showsRequiredWarning {
                Text("First name can’t be empty.")
                    .font(.caption)
                    .foregroundStyle(VowbaseTheme.rose)
            }
            if case let .failed(pending) = saveState {
                GuestSaveFailureNote {
                    Task { await commit(pending ?? draft) }
                }
            }
        }
        .onAppear { draft = stored }
        .onChange(of: stored) { _, newValue in
            // Adopt the server-confirmed value, but never yank text out from
            // under someone who is still typing.
            if !isFocused { draft = newValue }
        }
        .onChange(of: isFocused) { wasFocused, focused in
            guard wasFocused, !focused else { return }
            let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            if isRequired, trimmed.isEmpty {
                draft = stored
                showsRequiredWarning = true
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    showsRequiredWarning = false
                }
                return
            }
            Task { await commit(draft) }
        }
    }
}

private struct GuestSaveIndicator: View {
    let state: GuestFieldSaveState?

    var body: some View {
        switch state {
        case .saving:
            ProgressView().controlSize(.mini)
        case .saved:
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.green)
                .transition(.opacity)
        case .failed, .none:
            EmptyView()
        }
    }
}

private struct GuestSaveFailureNote: View {
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("Couldn’t save. Your value is still here.")
                .font(.caption)
                .foregroundStyle(VowbaseTheme.rose)
            Spacer(minLength: 4)
            Button("Retry", action: retry)
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(VowbaseTheme.rose)
        }
        .padding(.top, 2)
    }
}

/// Read-only context derived from the address.
///
/// These are outputs of geocoding, not blanks the user failed to fill, so the
/// row explains their state instead of presenting empty inputs.
private struct GuestDerivedLocationRow: View {
    let record: Guest
    let isResolving: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isResolving {
                HStack(spacing: 8) {
                    Text("Locating…").foregroundStyle(VowbaseTheme.mutedInk)
                    ProgressView().controlSize(.mini)
                }
            } else if record.originPrecision == "city", let label = record.originLabel {
                HStack(spacing: 8) {
                    Text(label)
                    Text("City")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(VowbaseTheme.guestBlue.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(VowbaseTheme.guestBlue)
                }
                Text("Shown on the map as part of a city cluster. The exact address never leaves this screen.")
                    .font(.caption)
                    .foregroundStyle(VowbaseTheme.mutedInk)
            } else if record.address?.nilIfBlank != nil {
                Text("Location not mapped").foregroundStyle(VowbaseTheme.mutedInk)
                Text("This address didn’t resolve to a city, so no map cluster includes this guest.")
                    .font(.caption)
                    .foregroundStyle(VowbaseTheme.mutedInk)
            } else {
                Text("No location").foregroundStyle(VowbaseTheme.mutedInk)
                Text("Add an address to include this guest in the map’s city clusters.")
                    .font(.caption)
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
        }
        .padding(.vertical, 2)
    }
}

/// One custom field, rendered with the single control its kind allows.
private struct GuestCustomFieldRow: View {
    let column: GuestCustomColumn
    let record: Guest
    let state: GuestFieldSaveState?
    let commit: (JSONValue?) -> Void
    let onCleared: (JSONValue?) -> Void

    private var stored: JSONValue? {
        GuestCustomFields.value(in: record.customFields, for: column.key)
    }

    var body: some View {
        if GuestCustomFields.isUnsupported(stored, kind: column.kind) {
            unsupportedRow
        } else {
            switch column.kind {
            case .checkbox: checkboxRow
            case .select: selectRow
            case .text, .number: textRow
            }
        }
    }

    private var unsupportedRow: some View {
        LabeledContent(column.label) {
            HStack(spacing: 8) {
                Text("Unsupported value")
                    .foregroundStyle(VowbaseTheme.mutedInk)
                Button("Clear") { commit(nil) }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(VowbaseTheme.rose)
            }
        }
    }

    private var checkboxRow: some View {
        Toggle(isOn: Binding(
            get: { stored == .bool(true) },
            set: { commit($0 ? .bool(true) : nil) }
        )) {
            HStack(spacing: 8) {
                Text(column.label)
                GuestSaveIndicator(state: state)
            }
        }
        .tint(VowbaseTheme.rose)
    }

    private var selectRow: some View {
        let options = GuestCustomFields.options(in: column)
        let current = GuestCustomFields.displayText(stored, kind: column.kind)
        // A value the column no longer offers is still shown, so the user can
        // see what is there before replacing it.
        let isOrphaned = current.map { !options.contains($0) } ?? false

        return LabeledContent(column.label) {
            HStack(spacing: 8) {
                GuestSaveIndicator(state: state)
                Menu {
                    if let current, isOrphaned {
                        Button {
                        } label: {
                            Label("\(current) — no longer an option", systemImage: "checkmark")
                        }
                        .disabled(true)
                    }
                    ForEach(options, id: \.self) { option in
                        Button {
                            commit(.string(option))
                        } label: {
                            if option == current {
                                Label(option, systemImage: "checkmark")
                            } else {
                                Text(option)
                            }
                        }
                    }
                    if current != nil {
                        Divider()
                        Button("Clear", role: .destructive) {
                            let previous = stored
                            commit(nil)
                            onCleared(previous)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(current ?? "Not set")
                            .foregroundStyle(current == nil ? VowbaseTheme.mutedInk : VowbaseTheme.ink)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                }
            }
        }
    }

    private var textRow: some View {
        LabeledContent(column.label) {
            GuestInlineField(
                stored: GuestCustomFields.displayText(stored, kind: column.kind) ?? "",
                saveState: state,
                keyboard: column.kind == .number ? .decimalPad : .default,
                capitalization: column.kind == .number ? .never : .sentences,
                commit: { text in
                    commit(GuestCustomFields.encode(text, kind: column.kind))
                }
            )
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfBlank: String? { trimmed.isEmpty ? nil : trimmed }
}

#if DEBUG
#Preview("Guest detail") {
    let store = VowbaseWorkspaceStore(testingWorkspace: true)
    NavigationStack {
        if let guest = store.guests.first {
            GuestDetailView(guest: guest, store: store)
        }
    }
}
#endif
