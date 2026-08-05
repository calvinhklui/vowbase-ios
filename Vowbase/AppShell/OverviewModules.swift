import SwiftUI

// MARK: - Module contract (spec §11.1)

/// Drives sort order among modules and each module's eyebrow/dot color.
/// Not every module computes this the same way — see each module's own
/// urgency logic — but the three tiers mean the same thing everywhere:
/// something to fix now, something to watch, or purely informational.
enum ModuleUrgency: Int, Comparable {
    case blocking = 0
    case soon = 1
    case ambient = 2

    static func < (lhs: ModuleUrgency, rhs: ModuleUrgency) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Nudges (spec §11.3)

/// Stable across app versions so a later domain's rules (a vendor payment
/// due, an event with no location) can append `NudgeID` cases without
/// disturbing these. Once `Task.coversNudge` exists server-side, this is
/// also the type that field would hold — see the note on `NudgeRules` for
/// why that field isn't built yet.
enum NudgeID: String, Hashable, Sendable {
    case addFirstVenue
    case pickAVenue
    case guestsWithoutLocation
    case rsvpsOutstanding
}

/// An app-noticed condition, not a task — spec §11.3's table is explicit
/// that these are a different kind of thing: no due date, no owner, no
/// status, gone the moment the underlying condition resolves rather than
/// requiring someone to mark it done.
struct Nudge: Identifiable {
    let id: NudgeID
    let message: String
    let destination: PlanLens
    /// Drives the row's dot: filled for an unresolved core decision
    /// (venue), outlined for lower-urgency housekeeping (guest data).
    let isUrgent: Bool
}

/// The five ordered rules from spec §11.3, evaluated fresh on every render —
/// nudges are recomputed, never stored.
///
/// **What's deliberately not built:** `Task.coversNudge`, the field that
/// would let a promoted task suppress its originating nudge. That field
/// needs a new column on the `wedding_tasks` table; this repository has no
/// migration tooling and no Supabase project checked in, so there is no way
/// to add one from here. Without it, a nudge keeps showing even after
/// you've promoted it into a task, until the underlying condition itself
/// resolves. Text-matching the task title against the nudge message was
/// considered and rejected — spec §11.3 rules it out by name, since it
/// produces false positives on any wedding whose planner names a task
/// something like "Guest locations."
@MainActor
enum NudgeRules {
    static func applicable(store: VowbaseWorkspaceStore) -> [Nudge] {
        let venues = store.venues
        let guests = store.guests
        let hasBookedVenue = venues.contains { $0.status == .booked }
        let touredCount = venues.filter { $0.status == .toured }.count

        var nudges: [Nudge] = []

        // Rules 1–2: dropped entirely once a venue is booked (rule 5) —
        // the core decision is made, so there's nothing left to nudge about.
        if !hasBookedVenue {
            if venues.isEmpty {
                nudges.append(Nudge(id: .addFirstVenue, message: "Add your first venue", destination: .venues, isUrgent: true))
            } else if touredCount >= 2 {
                nudges.append(Nudge(
                    id: .pickAVenue,
                    message: "Pick a venue — \(touredCount) toured, none held",
                    destination: .venues,
                    isUrgent: true
                ))
            }
        }

        let unlocatedCount = guests.filter { !$0.isMappable }.count
        if unlocatedCount > 0 {
            let guestWord = unlocatedCount == 1 ? "guest has" : "guests have"
            nudges.append(Nudge(
                id: .guestsWithoutLocation,
                message: "\(unlocatedCount) \(guestWord) no location",
                destination: .guests,
                isUrgent: false
            ))
        }

        if let daysUntil = WeddingCountdownFormatter.daysUntilWedding(store.wedding?.weddingDate), daysUntil <= 120 {
            let pendingCount = guests.filter { $0.rsvp == .pending }.count
            if pendingCount > 0 {
                let rsvpWord = pendingCount == 1 ? "RSVP" : "RSVPs"
                nudges.append(Nudge(
                    id: .rsvpsOutstanding,
                    message: "\(pendingCount) \(rsvpWord) outstanding",
                    destination: .guests,
                    isUrgent: false
                ))
            }
        }

        return Array(nudges.prefix(2))
    }
}

// MARK: - Needs you: relevant tasks

enum NeedsYouTasks {
    /// Overdue first, then due within 7 days — real commitments, capped at
    /// three, sorted the same way the Tasks list itself sorts: due date,
    /// then priority, then title.
    static func relevant(from tasks: [WeddingTask]) -> [WeddingTask] {
        guard let boundary = Calendar.current.date(byAdding: .day, value: 7, to: Date()) else { return [] }
        let candidates = tasks.filter { task in
            guard task.effectiveStatus != .done,
                  let raw = task.dueDate,
                  let due = TaskDueDateFormatter.date(from: raw) else { return false }
            return due <= boundary
        }
        let sorted = candidates.sorted { lhs, rhs in
            let lhsDue = lhs.dueDate.flatMap(TaskDueDateFormatter.date) ?? .distantFuture
            let rhsDue = rhs.dueDate.flatMap(TaskDueDateFormatter.date) ?? .distantFuture
            if lhsDue != rhsDue { return lhsDue < rhsDue }
            let lhsRank = priorityRank(lhs.priority)
            let rhsRank = priorityRank(rhs.priority)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return Array(sorted.prefix(3))
    }

    static func isOverdue(_ task: WeddingTask) -> Bool {
        guard let raw = task.dueDate, let due = TaskDueDateFormatter.date(from: raw) else { return false }
        return due < Calendar.current.startOfDay(for: Date())
    }

    private static func priorityRank(_ priority: WeddingTaskPriority?) -> Int {
        switch priority {
        case .urgent: 0
        case .high: 1
        case .medium: 2
        case .low: 3
        case nil: 4
        }
    }
}

// MARK: - Module shell

/// The shared chrome every module renders inside: an eyebrow title and a
/// card surface. Content is bespoke per module — Countdown, Needs You,
/// Reach, and Guests don't share a common shape, so this wraps them rather
/// than forcing them through one generic template.
struct OverviewModuleCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(VowbaseTheme.mutedInk)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(VowbaseTheme.border, lineWidth: 1)
        }
    }
}

private struct ModuleRow: View {
    let isUrgent: Bool
    let text: String
    let onTap: () -> Void
    var onPromote: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    Circle()
                        .strokeBorder(VowbaseTheme.mutedInk, lineWidth: isUrgent ? 0 : 1.4)
                        .background(Circle().fill(isUrgent ? VowbaseTheme.rose : .clear))
                        .frame(width: 8, height: 8)
                    Text(text)
                        .font(.system(size: 14))
                        .foregroundStyle(VowbaseTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                }
            }
            .buttonStyle(.plain)

            if let onPromote {
                Button(action: onPromote) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(VowbaseTheme.rose)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Turn into a task")
            }
        }
    }
}

// MARK: - Countdown module

struct CountdownModule: View {
    let store: VowbaseWorkspaceStore
    @State private var isSettingDate = false

    var body: some View {
        OverviewModuleCard(title: "COUNTDOWN") {
            // The whole card is the control, in both states. When only the
            // empty state was tappable the date became uneditable the moment
            // it was set — this is the app's one and only route to changing
            // it, since there's no wedding-settings screen yet.
            Button {
                isSettingDate = true
            } label: {
                if let weddingDate = store.wedding?.weddingDate,
                   let date = WeddingCountdownFormatter.date(from: weddingDate) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(date.formatted(.dateTime.month(.abbreviated).day().year()))
                            .font(.system(size: 20, weight: .regular, design: .serif))
                            .foregroundStyle(VowbaseTheme.ink)
                        Spacer(minLength: 8)
                        if let countdown = WeddingCountdownFormatter.countdownPhrase(for: weddingDate) {
                            Text(countdown)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(VowbaseTheme.mutedInk)
                        }
                    }
                    .contentShape(Rectangle())
                } else {
                    Text("Add your wedding date")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(VowbaseTheme.rose)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Changes your wedding date")
        }
        .sheet(isPresented: $isSettingDate) {
            SetWeddingDateSheet(store: store)
        }
    }

    /// Blocking when unset — spec §11.2.
    var urgency: ModuleUrgency { store.wedding?.weddingDate == nil ? .blocking : .ambient }
}

// MARK: - Needs you module

struct NeedsYouModule: View {
    let store: VowbaseWorkspaceStore
    let taskStore: TaskStore
    let onSelectTask: (WeddingTask) -> Void
    let onSelectNudge: (Nudge) -> Void
    let onPromoteNudge: (Nudge) -> Void

    private var tasks: [WeddingTask] { NeedsYouTasks.relevant(from: taskStore.tasks) }
    private var nudges: [Nudge] { NudgeRules.applicable(store: store) }

    /// Spec §11.3: "If neither produces a row, the module hides." An empty
    /// Needs You is worse than none — this is why it's the one module the
    /// Overview stack can render as nothing at all, not even an empty state.
    var hasContent: Bool { !tasks.isEmpty || !nudges.isEmpty }

    var urgency: ModuleUrgency {
        if tasks.contains(where: NeedsYouTasks.isOverdue) || nudges.contains(where: \.isUrgent) {
            return .blocking
        }
        return hasContent ? .soon : .ambient
    }

    var body: some View {
        if hasContent {
            OverviewModuleCard(title: "NEEDS YOU") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(tasks) { task in
                        ModuleRow(
                            isUrgent: NeedsYouTasks.isOverdue(task),
                            text: task.title,
                            onTap: { onSelectTask(task) }
                        )
                    }
                    ForEach(nudges) { nudge in
                        ModuleRow(
                            isUrgent: nudge.isUrgent,
                            text: nudge.message,
                            onTap: { onSelectNudge(nudge) },
                            onPromote: store.canManageTasks ? { onPromoteNudge(nudge) } : nil
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Reach module

struct ReachModule: View {
    let store: VowbaseWorkspaceStore
    let onTapReadout: () -> Void

    private var leadingVenue: MVPVenue? {
        store.venues.first { $0.id == store.selectedVenueID }
    }

    /// `.idle` renders nothing at all, so a card in that state would be a
    /// title and a venue name above dead space — which reads as a failure
    /// rather than as "nothing to say yet". The module hides instead, the
    /// same rule Needs You follows.
    var hasContent: Bool {
        guard leadingVenue != nil else { return false }
        if case .idle = store.travelImpact { return false }
        return true
    }

    var body: some View {
        if let venue = leadingVenue, hasContent {
            OverviewModuleCard(title: "REACH") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(venue.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(VowbaseTheme.ink)
                    VenueImpactRow(state: store.travelImpact, onTap: onTapReadout)
                }
            }
        }
    }
}

// MARK: - Guests module

struct GuestsModule: View {
    let store: VowbaseWorkspaceStore
    let onAddGuest: () -> Void

    private var guests: [Guest] { store.allGuestRecords }

    var body: some View {
        OverviewModuleCard(title: "GUESTS") {
            if guests.isEmpty {
                Button("Add your first guest", action: onAddGuest)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(VowbaseTheme.rose)
                    .buttonStyle(.plain)
            } else {
                let accepted = guests.filter { $0.rsvpStatus == .accepted }.count
                let pending = guests.filter { $0.rsvpStatus == .pending }.count
                Text("\(guests.count) invited · \(accepted) accepted · \(pending) pending")
                    .font(.system(size: 14))
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
        }
    }
}
