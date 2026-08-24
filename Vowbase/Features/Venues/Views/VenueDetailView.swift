import SwiftUI
import UIKit

/// Fields the Venue Detail screen edits inline. `status` never becomes `focusedField`
/// (it commits synchronously from a `Menu`) but shares the same saving/error dictionaries
/// as every other field so failure handling stays uniform.
private enum VenueEditableField: Hashable {
    case name, status, location
    case capacityMin, capacityMax
    case estimate, allInEstimate, availableDates, notes
    case website, contactName, contactEmail, contactPhone
}

struct VenueDetailView: View {
    let venue: MVPVenue
    let store: VowbaseWorkspaceStore
    @Binding var isNoteEditing: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDeletion = false
    /// `nil` keeps the cover photo as the hero. A gallery selection is local to this
    /// detail presentation, so navigating to a different venue always starts at its cover.
    @State private var selectedHeroPhotoURL: URL?

    /// Which row currently shows a TextField. Kept separate from `focusedField`: a
    /// TextField conditionally mounted in the same instant its own `@FocusState` target
    /// is set doesn't reliably pick up real keyboard focus in SwiftUI. `editingField`
    /// mounts the field first; each TextField's own `.onAppear` claims focus once it
    /// actually exists, which is what real commit/blur behavior is driven from.
    @State private var editingField: VenueEditableField?
    @FocusState private var focusedField: VenueEditableField?
    @State private var draftText = ""
    @State private var capacityMinDraft = ""
    @State private var capacityMaxDraft = ""
    @State private var optimisticValues: [VenueEditableField: String] = [:]
    @State private var optimisticStatus: VenueStatus?
    @State private var fieldErrors: [VenueEditableField: String] = [:]
    @State private var savingFields: Set<VenueEditableField> = []
    @State private var flashingFields: Set<VenueEditableField> = []

    @State private var locationDraft = ""
    @State private var locationSuggestions: [GeocodeResult] = []
    @State private var locationSearchTask: Task<Void, Never>?

    /// The screen must read live data by id — `venue` is a snapshot captured at
    /// navigation-push time and never refreshes on its own when `store.venues` changes.
    private var currentVenue: MVPVenue {
        store.venues.first(where: { $0.id == venue.id }) ?? venue
    }

    private var displayStatus: VenueStatus { optimisticStatus ?? currentVenue.status }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VowbaseVenueImage(
                    url: selectedHeroPhotoURL ?? currentVenue.photoURL,
                    cacheKey: selectedHeroPhotoURL == nil ? currentVenue.coverPhotoCacheKey : nil
                )
                    .frame(height: 270)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                if currentVenue.photoURLs.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(currentVenue.photoURLs.dropFirst(), id: \.absoluteString) { photoURL in
                                Button {
                                    selectedHeroPhotoURL = photoURL
                                } label: {
                                    VowbaseVenueImage(url: photoURL)
                                        .frame(width: 108, height: 76)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(
                                                    selectedHeroPhotoURL == photoURL ? VowbaseTheme.rose : .clear,
                                                    lineWidth: 2
                                                )
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Show photo")
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    inlineTextField(.name, placeholder: "Venue name", font: VowbaseType.screenDisplay, autocapitalization: .words)
                    errorCaption(.name)

                    Menu {
                        ForEach([
                            VenueStatus.suggested, .considering, .contacted, .toured,
                            .shortlisted, .negotiating, .booked, .passed,
                        ], id: \.self) { status in
                            Button(status.title) { commitStatus(status) }
                        }
                    } label: {
                        StatusCapsule(status: displayStatus)
                    }
                    errorCaption(.status)

                    locationRow
                }

                if let summary = currentVenue.summary?.nilIfBlank {
                    Text(summary)
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }

                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], alignment: .leading, spacing: 18) {
                    capacityCell
                    factCell(icon: "dollarsign.circle", field: .estimate, placeholder: "Add venue est.", caption: "venue est.")
                    factCell(icon: "dollarsign.square", field: .allInEstimate, placeholder: "Add all-in est.", caption: "all-in est.")
                    factCell(icon: "calendar", field: .availableDates, placeholder: "Add dates", caption: "available dates")
                }
                .padding()
                .background(VowbaseTheme.blush, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Details")
                        .font(.title2.weight(.semibold))
                    detailRow(title: "Website", field: .website, icon: "link", placeholder: "Add website", keyboardType: .URL, autocapitalization: .never)
                    detailRow(title: "Contact", field: .contactName, icon: "person", placeholder: "Add contact", autocapitalization: .words)
                    detailRow(title: "Email", field: .contactEmail, icon: "envelope", placeholder: "Add email", keyboardType: .emailAddress, autocapitalization: .never)
                    detailRow(title: "Phone", field: .contactPhone, icon: "phone", placeholder: "Add phone", keyboardType: .phonePad)
                }
                .padding()
                .background(VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(VowbaseTheme.border, lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.title2.weight(.semibold))
                    if editingField == .notes {
                        TextField("Add notes", text: $draftText, axis: .vertical)
                            .focused($focusedField, equals: .notes)
                            .onAppear { focusedField = .notes }
                            .font(.body)
                            .foregroundStyle(VowbaseTheme.ink)
                            .textInputAutocapitalization(.sentences)
                            .lineLimit(1...)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        let value = displayValue(for: .notes)
                        Button {
                            beginEditingSimple(.notes)
                        } label: {
                            noteDisplay(value)
                        }
                        .buttonStyle(.plain)
                    }
                    errorCaption(.notes)
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.never)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !savingFields.isEmpty {
                Rectangle().fill(VowbaseTheme.rose).frame(height: 2)
            }
        }
        .vowbaseScrollClearance(includesQuickAdd: editingField != .notes)
        .navigationTitle(currentVenue.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(editingField == .notes)
        .toolbar {
            if editingField == .notes {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        finishNotesEditing()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete Venue", role: .destructive) { isConfirmingDeletion = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
            ToolbarItem(placement: .keyboard) {
                if editingField == .notes {
                    Button("Save") {
                        finishNotesEditing()
                    }
                    .fontWeight(.semibold)
                    .padding(.bottom, 16)
                }
            }
        }
        .alert("Delete \(currentVenue.name)?", isPresented: $isConfirmingDeletion) {
            Button("Delete", role: .destructive) {
                deleteVenue()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the venue from your wedding workspace.")
        }
        .onChange(of: focusedField) { oldValue, newValue in
            guard let oldValue else { return }
            let stayedWithinCapacityPair =
                (oldValue == .capacityMin || oldValue == .capacityMax)
                    && (newValue == .capacityMin || newValue == .capacityMax)
            guard !stayedWithinCapacityPair else { return }
            // `editingField != oldValue` means something already explicitly handled this
            // transition (a tap straight into a different field, or a location suggestion
            // pick that already committed) — skip the generic auto-commit in that case.
            guard editingField == oldValue else { return }
            editingField = nil
            dispatchCommit(oldValue)
        }
        .onChange(of: editingField) { _, newValue in
            isNoteEditing = newValue == .notes
        }
        .onDisappear {
            focusedField = nil
            editingField = nil
            isNoteEditing = false
            locationSearchTask?.cancel()
        }
    }

    private func deleteVenue() {
        Task {
            guard await store.deleteVenue(venue) else {
                store.presentSaveFailure(retry: deleteVenue)
                return
            }
            dismiss()
        }
    }

    // MARK: - Shared field editing

    @ViewBuilder
    private func inlineTextField(
        _ field: VenueEditableField,
        placeholder: String,
        font: Font,
        keyboardType: UIKeyboardType = .default,
        autocapitalization: TextInputAutocapitalization = .sentences
    ) -> some View {
        if editingField == field {
            TextField(placeholder, text: $draftText)
                .focused($focusedField, equals: field)
                .onAppear { focusedField = field }
                .font(font)
                .foregroundStyle(VowbaseTheme.ink)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
                .submitLabel(.done)
                .onSubmit { focusedField = nil }
        } else {
            let value = displayValue(for: field)
            Button {
                beginEditingSimple(field)
            } label: {
                Text(value.isEmpty ? placeholder : value)
                    .font(font)
                    .foregroundStyle(
                        flashingFields.contains(field) ? VowbaseTheme.rose :
                            value.isEmpty ? VowbaseTheme.mutedInk : VowbaseTheme.ink
                    )
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func errorCaption(_ field: VenueEditableField) -> some View {
        if let error = fieldErrors[field] {
            Text(error)
                .font(.caption)
                .foregroundStyle(VowbaseTheme.rose)
        }
    }

    @ViewBuilder
    private func factCell(icon: String, field: VenueEditableField, placeholder: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label {
                inlineTextField(field, placeholder: placeholder, font: .system(size: 16, weight: .semibold))
            } icon: {
                Image(systemName: icon)
            }
            Text(caption)
                .font(.system(size: 13))
                .foregroundStyle(VowbaseTheme.mutedInk)
            errorCaption(field)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func detailRow(
        title: String,
        field: VenueEditableField,
        icon: String,
        placeholder: String,
        keyboardType: UIKeyboardType = .default,
        autocapitalization: TextInputAutocapitalization = .sentences
    ) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            LabeledContent(title) {
                Label {
                    inlineTextField(field, placeholder: placeholder, font: .subheadline, keyboardType: keyboardType, autocapitalization: autocapitalization)
                        .multilineTextAlignment(.trailing)
                } icon: {
                    Image(systemName: icon)
                }
                .font(.subheadline)
                .foregroundStyle(VowbaseTheme.mutedInk)
            }
            errorCaption(field)
        }
    }

    @ViewBuilder
    private var capacityCell: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label {
                if editingField == .capacityMin || editingField == .capacityMax {
                    HStack(spacing: 4) {
                        TextField("Min", text: $capacityMinDraft)
                            .focused($focusedField, equals: .capacityMin)
                            .onAppear { if editingField == .capacityMin { focusedField = .capacityMin } }
                            .keyboardType(.numberPad)
                            .frame(width: 40)
                        Text("–")
                        TextField("Max", text: $capacityMaxDraft)
                            .focused($focusedField, equals: .capacityMax)
                            .onAppear { if editingField == .capacityMax { focusedField = .capacityMax } }
                            .keyboardType(.numberPad)
                            .frame(width: 40)
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(VowbaseTheme.ink)
                } else {
                    Button {
                        beginEditingCapacity()
                    } label: {
                        Text(capacityDisplayValue)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(
                                flashingFields.contains(.capacityMin) ? VowbaseTheme.rose :
                                    isCapacityUnset ? VowbaseTheme.mutedInk : VowbaseTheme.ink
                            )
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            } icon: {
                Image(systemName: "person.2")
            }
            Text("guests")
                .font(.system(size: 13))
                .foregroundStyle(VowbaseTheme.mutedInk)
            errorCaption(.capacityMin)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isCapacityUnset: Bool {
        currentVenue.capacityMin == nil && currentVenue.capacityMax == nil && currentVenue.capacityTextOverride == nil
    }

    private var capacityDisplayValue: String {
        if let override = optimisticValues[.capacityMin] { return override }
        return isCapacityUnset ? "Add capacity" : currentVenue.capacity
    }

    @ViewBuilder
    private var locationRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if editingField == .location {
                TextField("Address or location", text: $locationDraft)
                    .focused($focusedField, equals: .location)
                    .onAppear { focusedField = .location }
                    .font(.subheadline)
                    .foregroundStyle(VowbaseTheme.ink)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .onChange(of: locationDraft) { _, newValue in searchLocation(newValue) }
            } else {
                Button {
                    beginEditingLocation()
                } label: {
                    Label(displayValue(for: .location), systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(flashingFields.contains(.location) ? VowbaseTheme.rose : VowbaseTheme.mutedInk)
                }
                .buttonStyle(.plain)
            }
            if editingField == .location, !locationSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(locationSuggestions.enumerated()), id: \.offset) { _, result in
                        Button {
                            selectLocationSuggestion(result)
                        } label: {
                            Text(result.displayName)
                                .font(.subheadline)
                                .foregroundStyle(VowbaseTheme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 8)
                        if result.displayName != locationSuggestions.last?.displayName {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 10)
                .background(VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(VowbaseTheme.border, lineWidth: 1)
                }
            }
            if currentVenue.coordinate == nil {
                Text("Not on map")
                    .font(.caption)
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
            errorCaption(.location)
        }
    }

    // MARK: - Field state helpers

    private func displayValue(for field: VenueEditableField) -> String {
        optimisticValues[field] ?? rawStringValue(for: field)
    }

    @ViewBuilder
    private func noteDisplay(_ value: String) -> some View {
        let foreground = flashingFields.contains(.notes) ? VowbaseTheme.rose :
            value.isEmpty ? VowbaseTheme.mutedInk : VowbaseTheme.ink

        if value.isEmpty {
            Text("Add notes")
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(value.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                    let formattedLine = NoteDisplayLine(line)
                    if formattedLine.isBullet {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                            Text(formattedLine.content)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Text(formattedLine.content)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
        }
    }

    private func rawStringValue(for field: VenueEditableField) -> String {
        switch field {
        case .name: currentVenue.name
        case .estimate: currentVenue.venueEstimateTextRaw ?? ""
        case .allInEstimate: currentVenue.allInEstimate == "Not added" ? "" : currentVenue.allInEstimate
        case .availableDates: currentVenue.availableDates == "Not added" ? "" : currentVenue.availableDates
        case .notes: currentVenue.ourNotes ?? ""
        case .website: currentVenue.website ?? ""
        case .contactName: currentVenue.contactName ?? ""
        case .contactEmail: currentVenue.contactEmail ?? ""
        case .contactPhone: currentVenue.contactPhone ?? ""
        case .location: currentVenue.location == "Location not added" ? "" : currentVenue.location
        case .status, .capacityMin, .capacityMax: ""
        }
    }

    private func beginEditingSimple(_ field: VenueEditableField) {
        draftText = rawStringValue(for: field)
        fieldErrors[field] = nil
        editingField = field
    }

    /// The detail screen keeps ownership of a notes edit. Its Back action ends the
    /// edit instead of allowing the containing NavigationStack to pop the venue.
    private func finishNotesEditing() {
        guard editingField == .notes else { return }
        if focusedField == .notes {
            focusedField = nil
        } else {
            editingField = nil
            dispatchCommit(.notes)
        }
    }

    private func beginEditingCapacity() {
        capacityMinDraft = currentVenue.capacityMin.map(String.init) ?? ""
        capacityMaxDraft = currentVenue.capacityMax.map(String.init) ?? ""
        fieldErrors[.capacityMin] = nil
        editingField = .capacityMin
    }

    private func beginEditingLocation() {
        locationDraft = rawStringValue(for: .location)
        locationSuggestions = []
        fieldErrors[.location] = nil
        editingField = .location
    }

    private func dispatchCommit(_ field: VenueEditableField) {
        switch field {
        case .capacityMin, .capacityMax: commitCapacity()
        case .location: commitLocation()
        default: commitSimpleField(field)
        }
    }

    private func flash(_ field: VenueEditableField) {
        withAnimation(.easeInOut(duration: 0.15)) { _ = flashingFields.insert(field) }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeInOut(duration: 0.15)) { _ = flashingFields.remove(field) }
        }
    }

    private func commitStatus(_ status: VenueStatus) {
        guard status != currentVenue.status else { return }
        let venueID = currentVenue.id
        optimisticStatus = status
        fieldErrors[.status] = nil
        savingFields.insert(.status)
        Task {
            let result = await store.patchVenue(id: venueID, VenuePatch(status: status))
            savingFields.remove(.status)
            optimisticStatus = nil
            if result == nil {
                fieldErrors[.status] = "Couldn't save — Retry"
                flash(.status)
            }
        }
    }

    private func makePatch(for field: VenueEditableField, trimmed: String) -> VenuePatch? {
        switch field {
        case .name:
            return trimmed.isEmpty ? nil : VenuePatch(name: trimmed)
        case .estimate:
            return VenuePatch(venueEstimateText: trimmed.isEmpty ? .null : .value(trimmed))
        case .allInEstimate:
            return VenuePatch(allInEstimateText: trimmed.isEmpty ? .null : .value(trimmed))
        case .availableDates:
            return VenuePatch(availableDatesText: trimmed.isEmpty ? .null : .value(trimmed))
        case .website:
            return VenuePatch(website: trimmed.isEmpty ? .null : .value(trimmed))
        case .contactName:
            return VenuePatch(contactName: trimmed.isEmpty ? .null : .value(trimmed))
        case .contactEmail:
            return VenuePatch(contactEmail: trimmed.isEmpty ? .null : .value(trimmed))
        case .contactPhone:
            return VenuePatch(contactPhone: trimmed.isEmpty ? .null : .value(trimmed))
        case .notes:
            return VenuePatch(ourNotes: trimmed.isEmpty ? .null : .value(trimmed))
        case .status, .location, .capacityMin, .capacityMax:
            return nil
        }
    }

    private func commitSimpleField(_ field: VenueEditableField) {
        let trimmed = draftText.trimmed
        let current = rawStringValue(for: field)
        guard trimmed != current else { return }
        guard let patch = makePatch(for: field, trimmed: trimmed) else { return }
        let venueID = currentVenue.id
        optimisticValues[field] = trimmed
        fieldErrors[field] = nil
        savingFields.insert(field)
        Task {
            let result = await store.patchVenue(id: venueID, patch)
            savingFields.remove(field)
            optimisticValues[field] = nil
            if result == nil {
                fieldErrors[field] = "Couldn't save — Retry"
                flash(field)
            }
        }
    }

    private func commitCapacity() {
        let minValue = Int(capacityMinDraft.trimmed)
        let maxValue = Int(capacityMaxDraft.trimmed)
        guard minValue != currentVenue.capacityMin
            || maxValue != currentVenue.capacityMax
            || currentVenue.capacityTextOverride != nil else { return }
        let venueID = currentVenue.id
        // Editing the numeric pair always wins over a stale text override, so the freshly
        // typed numbers are what the cell shows afterward rather than old research prose.
        optimisticValues[.capacityMin] = VenueCapacityFormatter.string(minimum: minValue, maximum: maxValue)
        fieldErrors[.capacityMin] = nil
        savingFields.insert(.capacityMin)
        let patch = VenuePatch(
            capacityMin: minValue.map(NullablePatch.value) ?? .null,
            capacityMax: maxValue.map(NullablePatch.value) ?? .null,
            capacityText: .null
        )
        Task {
            let result = await store.patchVenue(id: venueID, patch)
            savingFields.remove(.capacityMin)
            optimisticValues[.capacityMin] = nil
            if result == nil {
                fieldErrors[.capacityMin] = "Couldn't save — Retry"
                flash(.capacityMin)
            }
        }
    }

    private func searchLocation(_ query: String) {
        locationSearchTask?.cancel()
        let trimmed = query.trimmed
        guard !trimmed.isEmpty else {
            locationSuggestions = []
            return
        }
        locationSearchTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            let results = await store.geocodeSuggestions(for: trimmed)
            guard !Task.isCancelled else { return }
            locationSuggestions = results
        }
    }

    private func selectLocationSuggestion(_ result: GeocodeResult) {
        locationSearchTask?.cancel()
        locationSuggestions = []
        editingField = nil
        focusedField = nil
        commitLocation(selected: result)
    }

    /// Committing a typed string with no selection stores the literal text and clears
    /// coordinates; committing a selected suggestion stores its normalized label and
    /// coordinates. Spec §4.6 — this is what keeps the map tab from silently drifting.
    private func commitLocation(selected: GeocodeResult? = nil) {
        locationSearchTask?.cancel()
        let venueID = currentVenue.id
        let patch: VenuePatch
        let display: String

        if let selected {
            patch = VenuePatch(
                location: .value(selected.displayName),
                address: .value(selected.displayName),
                city: selected.city.map(NullablePatch.value) ?? .null,
                state: selected.region.map(NullablePatch.value) ?? .null,
                country: selected.country.map(NullablePatch.value) ?? .null,
                latitude: .value(selected.latitude),
                longitude: .value(selected.longitude)
            )
            display = selected.displayName
        } else {
            let trimmed = locationDraft.trimmed
            let current = rawStringValue(for: .location)
            guard trimmed != current else { return }
            if trimmed.isEmpty {
                patch = VenuePatch(location: .null, address: .null, city: .null, state: .null, country: .null, latitude: .null, longitude: .null)
                display = "Location not added"
            } else {
                patch = VenuePatch(location: .value(trimmed), address: .value(trimmed), city: .null, state: .null, country: .null, latitude: .null, longitude: .null)
                display = trimmed
            }
        }

        optimisticValues[.location] = display
        fieldErrors[.location] = nil
        savingFields.insert(.location)
        Task {
            let result = await store.patchVenue(id: venueID, patch)
            savingFields.remove(.location)
            optimisticValues[.location] = nil
            if result == nil {
                fieldErrors[.location] = "Couldn't save — Retry"
                flash(.location)
            }
        }
    }
}

private struct NoteDisplayLine {
    let content: String
    let isBullet: Bool

    init(_ rawValue: String) {
        let leadingWhitespaceTrimmed = rawValue.drop(while: \.isWhitespace)
        guard let marker = leadingWhitespaceTrimmed.first,
              marker == "-" || marker == "*" || marker == "•"
        else {
            content = rawValue
            isBullet = false
            return
        }

        content = String(leadingWhitespaceTrimmed.dropFirst().drop(while: \.isWhitespace))
        isBullet = true
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfBlank: String? { trimmed.isEmpty ? nil : trimmed }
}
