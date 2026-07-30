import SwiftUI
import UIKit

@MainActor
struct AddVenueSheet: View {
    let store: VowbaseWorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var name = ""
    @State private var location = ""
    @State private var status: VenueStatus = .considering
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("First, the essentials") {
                    TextField("Venue name", text: $name)
                        .focused($isNameFocused)
                        .textInputAutocapitalization(.words)
                    TextField("Address or location (optional)", text: $location)
                        .textInputAutocapitalization(.words)
                    Picker("Status", selection: $status) {
                        ForEach([VenueStatus.considering, .contacted, .toured, .shortlisted], id: \.self) {
                            Text($0.title).tag($0)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(VowbaseTheme.background)
            .tint(VowbaseTheme.rose)
            .navigationTitle("Add venue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save venue") {
                        saveVenue()
                    }
                    .disabled(name.trimmed.isEmpty || isSaving)
                }
            }
            .onAppear { isNameFocused = true }
        }
    }

    private func saveVenue() {
        isSaving = true
        Task {
            let didSave = await store.createVenue(name: name, location: location, status: status)
            isSaving = false
            guard didSave else {
                store.presentSaveFailure(retry: saveVenue, discard: { dismiss() })
                return
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfBlank: String? { trimmed.isEmpty ? nil : trimmed }
}

#Preview("Add venue") {
    AddVenueSheet(store: VowbaseWorkspaceStore())
}
