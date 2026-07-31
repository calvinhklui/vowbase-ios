import SwiftUI

/// Replaces `IdentityBar`. One row, 52 pt, floating material capsule — spec §5.
///
/// The search glyph expands the row in place to a full-width field. The
/// field itself is inert here: it takes text but returns nothing. Wiring it
/// to real cross-lens results (venues, guests, places — spec §5.1) is a
/// deliberately separate follow-up, not part of this pass.
struct ContextBar: View {
    let store: VowbaseWorkspaceStore
    let onSignOut: () -> Void

    @State private var isAccountMenuPresented = false
    @State private var isSearching = false
    @State private var searchQuery = ""
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isSearching {
                searchField
            } else {
                monogram
                titleLine
                Spacer(minLength: 0)
                searchButton
            }
        }
        .padding(8)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(VowbaseTheme.border.opacity(0.8), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 14, y: 5)
        .confirmationDialog(
            "Your Vowbase account",
            isPresented: $isAccountMenuPresented,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive, action: onSignOut)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can sign back in with Apple or Google at any time.")
        }
        .animation(.snappy(duration: 0.22), value: isSearching)
    }

    // MARK: Default state

    private var monogram: some View {
        Button { isAccountMenuPresented = true } label: {
            Text(weddingInitials)
                .font(.system(size: 14, weight: .regular, design: .serif))
                .frame(width: 36, height: 36)
                .background(VowbaseTheme.blush)
                .clipShape(Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Account")
        .accessibilityHint("Opens account actions")
    }

    // The date used to live here too, as either a countdown or an "Add your
    // date" button — moved out now that the Overview lens's Countdown
    // module (spec §11.2) is the one place that fact lives, and dropping it
    // gives the couple's own name the room it needs not to truncate.
    private var titleLine: some View {
        Text(store.weddingTitle)
            .font(.system(size: 17, weight: .regular, design: .serif))
            .foregroundStyle(VowbaseTheme.ink)
            .lineLimit(1)
    }

    private var searchButton: some View {
        Button {
            isSearching = true
            isSearchFieldFocused = true
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(VowbaseTheme.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search")
    }

    // MARK: Search state

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(VowbaseTheme.mutedInk)
            TextField("Search", text: $searchQuery)
                .focused($isSearchFieldFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            Button {
                isSearchFieldFocused = false
                isSearching = false
                searchQuery = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(VowbaseTheme.mutedInk)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel search")
        }
        .padding(.leading, 8)
    }

    private var weddingInitials: String {
        store.weddingTitle
            .split { !$0.isLetter }
            .compactMap(\.first)
            .prefix(2)
            .map { String($0).uppercased() }
            .joined(separator: "&")
    }
}

/// The minimum viable route for "Add your date": a single `DatePicker` and a
/// Save button, not a wedding-settings screen — nothing else about the
/// wedding record is editable from the app yet, and this phase doesn't ask
/// for that.
struct SetWeddingDateSheet: View {
    let store: VowbaseWorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var isSaving = false
    @State private var failureMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Wedding date", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(VowbaseTheme.rose)

                if let failureMessage {
                    Section {
                        Text(failureMessage)
                            .font(.footnote)
                            .foregroundStyle(VowbaseTheme.rose)
                    }
                }
            }
            .navigationTitle("Add your date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        failureMessage = nil
        Task {
            let didSave = await store.updateWeddingDate(date)
            isSaving = false
            if didSave {
                dismiss()
            } else {
                failureMessage = store.errorMessage ?? "Couldn’t save your date. Please try again."
            }
        }
    }
}
