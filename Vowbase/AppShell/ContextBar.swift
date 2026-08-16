import SwiftUI

/// Replaces `IdentityBar`. One row, 52 pt, floating material capsule — spec §5.
struct ContextBar: View {
    let store: VowbaseWorkspaceStore
    let onRequestSignOut: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            monogram
            titleLine
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(VowbaseTheme.border.opacity(0.8), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 14, y: 5)
    }

    // MARK: Default state

    private var monogram: some View {
        Button(action: onRequestSignOut) {
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
        .accessibilityHint("Opens sign out confirmation")
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

    private var weddingInitials: String {
        store.weddingTitle
            .split { !$0.isLetter }
            .compactMap(\.first)
            .prefix(2)
            .map { String($0).uppercased() }
            .joined(separator: "&")
    }
}

/// The only route to the workspace's wedding timing. It edits the same
/// specific-date/range fields as web settings and clears the inactive shape
/// whenever the couple switches modes.
struct SetWeddingDateSheet: View {
    private enum DateMode: String, CaseIterable, Identifiable {
        case specific
        case range

        var id: Self { self }
        var title: String { self == .specific ? "A date" : "A range" }
    }

    let store: VowbaseWorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var mode: DateMode = .specific
    @State private var date = Date()
    @State private var rangeStart = Date()
    @State private var rangeEnd = Date()
    @State private var isSaving = false
    @State private var failureMessage: String?

    private var existingDate: Date? {
        store.wedding?.weddingDate.flatMap(WeddingCountdownFormatter.date(from:))
    }

    private var existingRangeStart: Date? {
        store.wedding?.dateRangeStart.flatMap(WeddingCountdownFormatter.date(from:))
    }

    private var existingRangeEnd: Date? {
        store.wedding?.dateRangeEnd.flatMap(WeddingCountdownFormatter.date(from:))
    }

    private var hasExistingTiming: Bool {
        existingDate != nil || existingRangeStart != nil || existingRangeEnd != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("When", selection: $mode) {
                        ForEach(DateMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    if mode == .specific {
                        DatePicker("Wedding date", selection: $date, displayedComponents: .date)
                    } else {
                        DatePicker("Earliest", selection: $rangeStart, displayedComponents: .date)
                        DatePicker(
                            "Latest",
                            selection: $rangeEnd,
                            in: rangeStart...,
                            displayedComponents: .date
                        )
                    }
                }
                .tint(VowbaseTheme.rose)

                if hasExistingTiming {
                    Section {
                        Button("Remove wedding timing", role: .destructive) { clear() }
                            .disabled(isSaving)
                    }
                }

                if let failureMessage {
                    Section {
                        Text(failureMessage)
                            .font(.footnote)
                            .foregroundStyle(VowbaseTheme.rose)
                    }
                }
            }
            .onAppear {
                if let existingDate {
                    mode = .specific
                    date = existingDate
                } else if existingRangeStart != nil || existingRangeEnd != nil {
                    mode = .range
                    rangeStart = existingRangeStart ?? existingRangeEnd ?? Date()
                    rangeEnd = max(existingRangeEnd ?? rangeStart, rangeStart)
                }
            }
            .onChange(of: rangeStart) { _, newStart in
                if rangeEnd < newStart { rangeEnd = newStart }
            }
            .navigationTitle(hasExistingTiming ? "Wedding timing" : "Add wedding timing")
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
            let didSave = switch mode {
            case .specific:
                await store.updateWeddingDate(date)
            case .range:
                await store.updateWeddingDateRange(start: rangeStart, end: rangeEnd)
            }
            isSaving = false
            if didSave {
                dismiss()
            } else {
                failureMessage = store.errorMessage ?? "Couldn’t save your date. Please try again."
            }
        }
    }

    private func clear() {
        isSaving = true
        failureMessage = nil
        Task {
            let didClear = await store.clearWeddingDates()
            isSaving = false
            if didClear {
                dismiss()
            } else {
                failureMessage = store.errorMessage ?? "Couldn’t remove your timing. Please try again."
            }
        }
    }
}
