import SwiftUI

// MARK: - Console detents

/// The console's three stops, wrapping `PresentationDetent` so the shell can
/// also reason about the resolved point height for camera insets and FAB
/// placement — `PresentationDetent` itself is an opaque value type and can't
/// be pattern-matched back apart. See spec §7.1.
///
/// SwiftUI has no API for a sheet's live drag position, only its settled
/// detent. Camera insets and the FAB therefore snap to whichever detent the
/// console has come to rest at, rather than tracking the drag continuously.
enum ConsoleDetent: CaseIterable {
    case peek
    case half
    case full

    /// Peek has to fit everything the console stacks at rest, or its content
    /// runs underneath the lens rail — which is what made the rail look like
    /// it was covering every lens. The arithmetic, top to bottom:
    ///
    ///     27  grabber (22 pt of clearance + a 5 pt capsule)
    ///     14  stack spacing
    ///     31  header — the lens title
    ///     14  stack spacing
    ///    150  venue metric filters plus the venue card
    ///      8  breathing room
    ///     86  lens rail (70 pt tall, 16 pt of padding)
    ///
    /// Anything added to the console's resting stack has to be paid for here.
    static let peekHeight: CGFloat = 331
    /// The default focused-lens stop is intentionally taller than the system
    /// medium detent so Venues and Guests have room for their metrics and list.
    static let halfFraction: CGFloat = 0.6

    var presentationDetent: PresentationDetent {
        switch self {
        case .peek: .height(Self.peekHeight)
        case .half: .fraction(Self.halfFraction)
        // Deliberately not .large: that system detent reserves a visible
        // gap at the top as an affordance. There's nothing under the
        // console worth keeping visible once you've dragged this far, so
        // .full covers the context bar too rather than peeking it out.
        case .full: .fraction(1.0)
        }
    }

    /// The console's resolved height in points, given the screen height it's
    /// measured against — `.half`/`.full` are screen fractions.
    func pointHeight(in screenHeight: CGFloat) -> CGFloat {
        switch self {
        case .peek: Self.peekHeight
        case .half: screenHeight * Self.halfFraction
        case .full: screenHeight
        }
    }
}

// MARK: - Console scroll handoff

/// Gives the focused-lens roots a Flighty-style vertical gesture handoff.
/// Before full height, vertical content scrolling is disabled and an upward
/// flick advances the sheet by one detent. At full height the ScrollView owns
/// vertical movement; only a downward flick from its measured top edge asks
/// the sheet to collapse.
private struct ConsoleVerticalScrollHandoff: ViewModifier {
    let allowsVerticalScrolling: Bool
    let onExpand: () -> Void
    let onCollapse: () -> Void

    @State private var contentOffset: CGFloat = 0

    private let flickThreshold: CGFloat = 36
    private let topTolerance: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scrollDisabled(!allowsVerticalScrolling)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, newOffset in
                contentOffset = newOffset
            }
            .simultaneousGesture(verticalHandoffGesture)
    }

    private var verticalHandoffGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                let vertical = value.predictedEndTranslation.height
                let horizontal = value.predictedEndTranslation.width
                guard abs(vertical) > abs(horizontal) else { return }

                if !allowsVerticalScrolling, vertical < -flickThreshold {
                    onExpand()
                } else if allowsVerticalScrolling,
                          contentOffset <= topTolerance,
                          vertical > flickThreshold {
                    onCollapse()
                }
            }
    }
}

extension View {
    func consoleVerticalScrollHandoff(
        allowsVerticalScrolling: Bool,
        onExpand: @escaping () -> Void,
        onCollapse: @escaping () -> Void
    ) -> some View {
        modifier(
            ConsoleVerticalScrollHandoff(
                allowsVerticalScrolling: allowsVerticalScrolling,
                onExpand: onExpand,
                onCollapse: onCollapse
            )
        )
    }
}

/// A single adaptive material sits behind every console root and pushed
/// detail. Feature hosts keep their scroll backgrounds transparent so this
/// remains visible as the presentation resizes between detents.
struct ConsolePresentationBackground: View {
    var body: some View {
        Group {
            if #available(iOS 26, *) {
                Color.clear
                    .glassEffect(.regular, in: .rect(cornerRadius: 28))
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Selection-aware header

/// The console's header, two lines, 16 pt insets. Shows the lens's state at a
/// glance with nothing selected, or the selected object and its consequence
/// otherwise. See spec §7.2.
///
/// The impact readout (§8) isn't wired yet — Phase 4 — so a selected venue's
/// second line shows its location rather than a fabricated travel figure.
struct ConsoleHeader: View {
    let title: String
    let trailing: String?
    let subline: String?
    let addAction: (() -> Void)?
    let addAccessibilityLabel: String?
    let addSystemImage: String
    init(
        title: String,
        trailing: String?,
        subline: String?,
        addAction: (() -> Void)? = nil,
        addAccessibilityLabel: String? = nil,
        addSystemImage: String = "plus"
    ) {
        self.title = title
        self.trailing = trailing
        self.subline = subline
        self.addAction = addAction
        self.addAccessibilityLabel = addAccessibilityLabel
        self.addSystemImage = addSystemImage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .displayTitle()
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }
                if let addAction {
                    Button(action: addAction) {
                        Image(systemName: addSystemImage)
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .background(VowbaseTheme.blush, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(VowbaseTheme.rose)
                    .accessibilityLabel(addAccessibilityLabel ?? "Add")
                }
            }
            if let subline {
                Text(subline)
                    .font(.system(size: 14))
                    .foregroundStyle(VowbaseTheme.mutedInk)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: subline == nil ? 38 : 60, alignment: .leading)
    }
}

extension ConsoleHeader {
    /// The Venues lens always keeps its own title, including when a venue is
    /// selected on the map. Status counts live in the compact metric rail.
    init(
        venues _: [MVPVenue],
        addAction: (() -> Void)? = nil
    ) {
        title = "Venues"
        trailing = nil
        subline = nil
        self.addAction = addAction
        addAccessibilityLabel = "Add Venue"
        addSystemImage = "plus"
    }

    /// No selection: the Guests lens's own state at a glance.
    init(
        guests: [Guest],
        addAction: (() -> Void)? = nil
    ) {
        title = "Guests"
        trailing = nil
        subline = nil
        self.addAction = addAction
        addAccessibilityLabel = "Add Guest"
        addSystemImage = "plus"
    }

    /// Tasks has no map selection to reflect — always its own state at a glance.
    init(
        openTaskCount: Int,
        dueSoonCount: Int,
        addAction: (() -> Void)? = nil
    ) {
        title = "Tasks"
        trailing = nil
        subline = "\(openTaskCount) open" + (dueSoonCount > 0 ? " · \(dueSoonCount) due this week" : "")
        self.addAction = addAction
        addAccessibilityLabel = "Add Task"
        addSystemImage = "plus"
    }
}

// MARK: - Venue impact header (selected venue)

/// The header for a selected venue: name and status on the first line, the
/// impact readout (spec §8) on the second — replacing `ConsoleHeader`'s
/// plain-string subline, since this row needs its own tap target and a
/// per-state layout, not just a different string.
struct VenueImpactHeader: View {
    let venue: MVPVenue
    let impact: TravelImpactState
    let onOpenDetails: () -> Void
    let onTapReadout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onOpenDetails) {
                HStack(alignment: .firstTextBaseline) {
                    Text(venue.name)
                        .font(.system(size: 22, weight: .regular, design: .serif))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(venue.status.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(VowbaseTheme.mutedInk)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }
            }
            .buttonStyle(.plain)
            VenueImpactRow(state: impact, onTap: onTapReadout)
        }
    }
}

/// The readout row itself, spec §8 and §8.1. Every non-idle, non-loading
/// state is a tap target: a real number routes to the guests it describes,
/// an unavailable one routes to its own fix.
struct VenueImpactRow: View {
    let state: TravelImpactState
    let onTap: () -> Void

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Calculating guest travel…")
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
            .font(.system(size: 14))
        case let .unavailable(reason):
            Button(action: onTap) {
                HStack(spacing: 6) {
                    Text(reason.message)
                        .foregroundStyle(VowbaseTheme.mutedInk)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if reason == .requestFailed {
                        Text("Retry")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(VowbaseTheme.rose)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(VowbaseTheme.mutedInk)
                    }
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 14))
        case let .ready(readout):
            Button(action: onTap) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(VowbaseTheme.rose)
                        .frame(width: 7, height: 7)
                    Text(readout.summaryText)
                        .foregroundStyle(VowbaseTheme.mutedInk)
                        .lineLimit(1)
                    if readout.isEstimated {
                        Text("Est.")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(VowbaseTheme.mutedInk)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(VowbaseTheme.border.opacity(0.6), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 14))
        }
    }
}

private extension TravelUnavailableReason {
    var message: String {
        switch self {
        case .venueMissingCoordinate:
            "Add this venue's location to see guest travel"
        case .noMappableGuests:
            "No guest locations yet — add some to see travel"
        case .requestFailed:
            "Guest travel unavailable"
        }
    }
}

// MARK: - Venue rail (peek)

/// The peek-detent card rail, shared by the Overview lens and the Venues
/// lens's own peek state — both show the same shortlist. Redesigned per
/// spec §7.3: two facts instead of four, location dropped because the card
/// is anchored to a pin already on screen.
struct VenueRailContent: View {
    let store: VowbaseWorkspaceStore
    let onSelect: (MVPVenue) -> Void
    let onOpenDetails: (MVPVenue) -> Void

    @State private var selectedStatus: VenueStatus?

    private let lifecycleOrder: [VenueStatus] = [
        .considering, .contacted, .toured,
        .shortlisted, .negotiating, .booked, .passed,
    ]

    private var visibleVenues: [MVPVenue] {
        store.venues.filter { selectedStatus == nil || $0.status == selectedStatus }
    }

    var body: some View {
        if store.venues.isEmpty {
            Text("Add a venue to start your shortlist.")
                .font(.system(size: 16))
                .foregroundStyle(VowbaseTheme.mutedInk)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                statusMetricPills

                if visibleVenues.isEmpty {
                    Text("No venues match this status.")
                        .font(.system(size: 16))
                        .foregroundStyle(VowbaseTheme.mutedInk)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(visibleVenues) { venue in
                                    Button {
                                        if venue.id == store.selectedVenueID {
                                            onOpenDetails(venue)
                                        } else {
                                            onSelect(venue)
                                        }
                                    } label: {
                                        VenueRailCard(venue: venue, selected: venue.id == store.selectedVenueID)
                                    }
                                    .buttonStyle(.plain)
                                    .id(venue.id)
                                }
                            }
                            .padding(.horizontal, 18)
                        }
                        .onChange(of: store.selectedVenueID) { _, selectedID in
                            guard let selectedID else { return }
                            if !visibleVenues.contains(where: { $0.id == selectedID }) {
                                selectedStatus = nil
                            }
                            withAnimation(.snappy(duration: 0.25, extraBounce: 0)) {
                                proxy.scrollTo(selectedID, anchor: .center)
                            }
                        }
                    }
                    .contentMargins(.trailing, 18, for: .scrollContent)
                }
            }
        }
    }

    private var statusMetricPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(lifecycleOrder, id: \.self) { status in
                    let isSelected = selectedStatus == status
                    let venueCount = store.venues.count { $0.status == status }
                    Button {
                        selectedStatus = isSelected ? nil : status
                    } label: {
                        CompactMetricFilterPill(
                            count: venueCount,
                            title: status.title,
                            isSelected: isSelected
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(status.title), \(venueCount) venues")
                    .accessibilityHint(isSelected ? "Double tap to show all venues" : "Double tap to filter the venue rail")
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                }
            }
            .padding(.horizontal, 18)
        }
        .contentMargins(.trailing, 18, for: .scrollContent)
        .animation(.easeInOut(duration: 0.18), value: selectedStatus)
    }
}

private struct VenueRailCard: View {
    let venue: MVPVenue
    let selected: Bool

    var body: some View {
        HStack(spacing: 0) {
            VowbaseVenueImage(url: venue.photoURL, cacheKey: venue.coverPhotoCacheKey)
                .frame(width: 88, height: 104)
            VStack(alignment: .leading, spacing: 7) {
                Text(venue.name)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                VenueRailFactMatrix(venue: venue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        // Anchor the image-containing HStack to the card's leading edge; a
        // centered fixed frame otherwise leaves an apparent white gutter
        // before the photo when the text column is narrower than the card.
        .frame(width: 260, height: 104, alignment: .leading)
        .background(VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    selected ? VowbaseTheme.rose : VowbaseTheme.border.opacity(0.65),
                    lineWidth: selected ? 4 : 1
                )
        }
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }
}

private struct VenueRailFactMatrix: View {
    let venue: MVPVenue

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                VenueRailFact(label: "guests", value: venue.capacity, systemImage: "person.2")
                VenueRailFact(label: "venue est.", value: venue.estimate, systemImage: "dollarsign.circle")
            }
            GridRow {
                VenueRailFact(label: "all-in est.", value: venue.allInEstimate, systemImage: "dollarsign.square")
                VenueRailFact(label: "available", value: venue.availableDates, systemImage: "calendar")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct VenueRailFact: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(label, systemImage: systemImage)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(VowbaseTheme.mutedInk)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(VowbaseTheme.ink)
                .lineLimit(1)
        }
        .frame(width: 70, alignment: .leading)
    }
}

// MARK: - Guest rail (peek)

/// The Guests lens's own peek state: avatar, name, RSVP, and the wedding's
/// chosen subtitle column — the same display resolver the Guests list uses.
struct GuestRailContent: View {
    let store: VowbaseWorkspaceStore
    let selectedGuestID: UUID?
    let onSelect: (MVPGuest) -> Void

    @State private var metricConfiguration = GuestMetricConfiguration.default(columns: [])
    @State private var selectedMetricID: String?

    private var selectedMetric: GuestMetric? {
        metricConfiguration.metrics.first(where: { $0.id == selectedMetricID })
    }

    /// Match the full Guests surface's default ordering, then narrow that
    /// same result when a compact metric pill is selected.
    private var visibleGuests: [MVPGuest] {
        store.filteredGuests(
            searchText: "",
            filters: GuestFilterSet(),
            sort: .nameAscending,
            metric: selectedMetric
        )
    }

    var body: some View {
        Group {
            if store.guests.isEmpty {
                Text("Add a guest to start your list.")
                    .font(.system(size: 16))
                    .foregroundStyle(VowbaseTheme.mutedInk)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    metricFilterPills

                    if visibleGuests.isEmpty {
                        Text("No guests match this metric.")
                            .font(.system(size: 16))
                            .foregroundStyle(VowbaseTheme.mutedInk)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(visibleGuests) { guest in
                                    Button { onSelect(guest) } label: {
                                        GuestRailCard(guest: guest, selected: guest.id == selectedGuestID)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 18)
                        }
                        .contentMargins(.trailing, 18, for: .scrollContent)
                    }
                }
            }
        }
        .task(id: store.wedding?.id) {
            let configuration = GuestMetricConfigurationStorage.load(
                weddingID: store.wedding?.id,
                columns: store.visibleCustomColumns
            )
            metricConfiguration = configuration
            clearUnavailableMetric(in: configuration)
        }
        .onChange(of: store.visibleCustomColumns) { _, columns in
            let configuration = metricConfiguration.normalized(columns: columns)
            metricConfiguration = configuration
            clearUnavailableMetric(in: configuration)
        }
    }

    private var metricFilterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(metricConfiguration.shownMetrics) { metric in
                    let isSelected = selectedMetricID == metric.id
                    Button {
                        selectedMetricID = isSelected ? nil : metric.id
                    } label: {
                        CompactMetricFilterPill(
                            count: metric.count(in: store.allGuestRecords),
                            title: metric.cardTitle,
                            isSelected: isSelected
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(metric.name), \(metric.count(in: store.allGuestRecords)) guests")
                    .accessibilityHint(isSelected ? "Double tap to show all guests" : "Double tap to filter the guest rail")
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                }
            }
            .padding(.horizontal, 18)
        }
        .contentMargins(.trailing, 18, for: .scrollContent)
        .animation(.easeInOut(duration: 0.18), value: selectedMetricID)
    }

    private func clearUnavailableMetric(in configuration: GuestMetricConfiguration) {
        if let selectedMetricID,
           !configuration.shownMetrics.contains(where: { $0.id == selectedMetricID }) {
            self.selectedMetricID = nil
        }
    }
}

/// The compact count-and-label capsule shared by the console rails and the
/// full Venues and Guests roots. Selection stays outside this view so every
/// host can use the same presentation with its own filtering state.
struct CompactMetricFilterPill: View {
    let count: Int
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("\(count)")
                .font(.system(size: 16, weight: .semibold, design: .default))
                .monospacedDigit()
                .foregroundStyle(VowbaseTheme.rose)
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundStyle(VowbaseTheme.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(
            isSelected ? VowbaseTheme.blush : VowbaseTheme.background,
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(isSelected ? VowbaseTheme.rose : VowbaseTheme.border.opacity(0.65), lineWidth: isSelected ? 2 : 1)
        }
        .frame(minHeight: VowbaseControlMetric.minimumTapTarget)
        .contentShape(Capsule())
    }
}

/// A 36 pt visual control contained in a 44 pt hit target. Keeping the hit
/// target separate lets the root tool row stay compact without reducing its
/// accessibility or touch size.
struct CompactConsoleCircleControl: View {
    let systemImage: String
    var isActive = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isActive ? .white : VowbaseTheme.ink)
            .frame(width: 36, height: 36)
            .background(isActive ? VowbaseTheme.rose : VowbaseTheme.background, in: Circle())
            .overlay(Circle().stroke(VowbaseTheme.border, lineWidth: 1))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }
}

struct CompactConsoleSearchField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(VowbaseTheme.mutedInk)
            TextField(placeholder, text: $text)
                .focused($isFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 36)
        .background(VowbaseTheme.background, in: Capsule())
        .overlay(Capsule().stroke(VowbaseTheme.border, lineWidth: 1))
        .frame(maxWidth: .infinity, minHeight: VowbaseControlMetric.minimumTapTarget)
    }
}

private struct GuestRailCard: View {
    let guest: MVPGuest
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(guest.peekInitials)
                .font(.system(size: 17, weight: .regular, design: .serif))
                .frame(width: 46, height: 46)
                .background(VowbaseTheme.blush, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(guest.peekName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(VowbaseTheme.ink)
                    .lineLimit(1)
                if let subtitle = guest.subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(VowbaseTheme.mutedInk)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        // Width is intentionally unset — a fixed width stretched every card
        // to the same size regardless of name length, which centered short
        // content (avatar included) inside the leftover space instead of
        // letting it sit flush against the leading edge.
        .frame(height: 78)
        .background(VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    selected ? VowbaseTheme.rose : VowbaseTheme.border.opacity(0.65),
                    lineWidth: selected ? 4 : 1
                )
        }
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }
}

private extension MVPGuest {
    var peekLastName: String? {
        let candidate = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty || candidate == "?" ? nil : candidate
    }

    var peekName: String {
        let trimmedFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return [trimmedFirstName.isEmpty ? nil : trimmedFirstName, peekLastName]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    var peekInitials: String {
        [firstName.first, peekLastName?.first]
            .compactMap { $0 }
            .map { String($0).uppercased() }
            .joined()
    }
}
