import SwiftUI
import UIKit
import QuickLook

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
    let onViewOnMap: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDeletion = false
    /// `nil` keeps the cover photo as the hero. A gallery selection is local to this
    /// detail presentation, so navigating to a different venue always starts at its cover.
    @State private var selectedHeroPhotoURL: URL?
    @State private var isDetailsEditing = false
    @State private var websiteDraft = ""
    @State private var contactNameDraft = ""
    @State private var contactEmailDraft = ""
    @State private var contactPhoneDraft = ""
    @State private var notesDraft = ""
    @State private var detailsSaveError: String?
    @State private var isSavingDetails = false
    @State private var documentPreview: VenueDocumentPreview?
    @State private var downloadingAttachmentID: UUID?
    @State private var documentDownloadError: String?

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

    init(
        venue: MVPVenue,
        store: VowbaseWorkspaceStore,
        isNoteEditing: Binding<Bool>,
        onViewOnMap: @escaping () -> Void = {}
    ) {
        self.venue = venue
        self.store = store
        self._isNoteEditing = isNoteEditing
        self.onViewOnMap = onViewOnMap
    }

    /// The screen must read live data by id — `venue` is a snapshot captured at
    /// navigation-push time and never refreshes on its own when `store.venues` changes.
    private var currentVenue: MVPVenue {
        store.venues.first(where: { $0.id == venue.id }) ?? venue
    }

    private var displayStatus: VenueStatus { optimisticStatus ?? currentVenue.status }
    private var heroPhotoURL: URL? { selectedHeroPhotoURL ?? currentVenue.photoURL }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VowbaseVenueImage(
                    url: heroPhotoURL,
                    cacheKey: selectedHeroPhotoURL == nil ? currentVenue.coverPhotoCacheKey : nil
                )
                    .frame(height: 270)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                if !currentVenue.photoURLs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(currentVenue.photoURLs, id: \.absoluteString) { photoURL in
                                Button {
                                    selectedHeroPhotoURL = photoURL == currentVenue.photoURL ? nil : photoURL
                                } label: {
                                    VowbaseVenueImage(url: photoURL)
                                        .frame(width: 108, height: 76)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(
                                                    heroPhotoURL == photoURL ? VowbaseTheme.rose : .clear,
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

                detailsSection
                documentsSection
                notesSection
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.never)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !savingFields.isEmpty {
                Rectangle().fill(VowbaseTheme.rose).frame(height: 2)
            }
        }
        .vowbaseScrollClearance(includesQuickAdd: !isDetailsEditing)
        .navigationTitle(currentVenue.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isDetailsEditing)
        .toolbar {
            if isDetailsEditing {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        cancelDetailsEditing()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close editing")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveDetails()
                    }
                    .fontWeight(.semibold)
                    .disabled(isSavingDetails)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Delete Venue", role: .destructive) { isConfirmingDeletion = true }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
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
        .sheet(item: $documentPreview) { preview in
            VenueDocumentQuickLookPreview(url: preview.url)
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
        .onChange(of: isDetailsEditing) { _, newValue in
            isNoteEditing = newValue
        }
        .onDisappear {
            focusedField = nil
            editingField = nil
            isDetailsEditing = false
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
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Details")
                    .font(.title2.weight(.semibold))
                Spacer()
                if !isDetailsEditing {
                    Button {
                        beginDetailsEditing()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Edit venue details and notes")
                }
            }

            if isDetailsEditing {
                detailsEditor
            } else {
                detailsReadOnly
            }
        }
        .padding()
        .background(VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VowbaseTheme.border, lineWidth: 1)
        }
    }

    private var detailsReadOnly: some View {
        VStack(alignment: .leading, spacing: 12) {
            detailReadOnlyRow(
                title: "Website",
                value: currentVenue.website,
                placeholder: "Not added",
                icon: "link",
                destination: websiteURL(from: currentVenue.website)
            )
            detailReadOnlyRow(
                title: "Contact",
                value: currentVenue.contactName,
                placeholder: "Not added",
                icon: "person",
                destination: nil
            )
            detailReadOnlyRow(
                title: "Email",
                value: currentVenue.contactEmail,
                placeholder: "Not added",
                icon: "envelope",
                destination: emailURL(from: currentVenue.contactEmail)
            )
            detailReadOnlyRow(
                title: "Phone",
                value: currentVenue.contactPhone,
                placeholder: "Not added",
                icon: "phone",
                destination: phoneURL(from: currentVenue.contactPhone)
            )

        }
    }

    private var detailsEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            detailEditorRow("Website", text: $websiteDraft, placeholder: "Add website", keyboardType: .URL, autocapitalization: .never)
            detailEditorRow("Contact", text: $contactNameDraft, placeholder: "Add contact", autocapitalization: .words)
            detailEditorRow("Email", text: $contactEmailDraft, placeholder: "Add email", keyboardType: .emailAddress, autocapitalization: .never)
            detailEditorRow("Phone", text: $contactPhoneDraft, placeholder: "Add phone", keyboardType: .phonePad)
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.title2.weight(.semibold))
            if isDetailsEditing {
                TextField("Add notes", text: $notesDraft, axis: .vertical)
                    .font(.body)
                    .foregroundStyle(VowbaseTheme.ink)
                    .textInputAutocapitalization(.sentences)
                    .lineLimit(3...)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button {
                    beginDetailsEditing()
                } label: {
                    noteDisplay(displayValue(for: .notes))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit venue notes")
            }

            if let detailsSaveError {
                Text(detailsSaveError)
                    .font(.caption)
                    .foregroundStyle(VowbaseTheme.rose)
            }
        }
        .padding()
        .background(VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VowbaseTheme.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func detailReadOnlyRow(
        title: String,
        value: String?,
        placeholder: String,
        icon: String,
        destination: URL?
    ) -> some View {
        LabeledContent(title) {
            if let value = value?.nilIfBlank {
                if let destination {
                    Link(destination: destination) {
                        Label(value, systemImage: icon)
                            .lineLimit(1)
                    }
                    .tint(VowbaseTheme.rose)
                } else {
                    Label(value, systemImage: icon)
                        .lineLimit(1)
                        .foregroundStyle(VowbaseTheme.ink)
                }
            } else {
                Label(placeholder, systemImage: icon)
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }
        }
        .font(.subheadline)
    }

    private func detailEditorRow(
        _ title: String,
        text: Binding<String>,
        placeholder: String,
        keyboardType: UIKeyboardType = .default,
        autocapitalization: TextInputAutocapitalization = .sentences
    ) -> some View {
        LabeledContent(title) {
            TextField(placeholder, text: text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Documents")
                .font(.title2.weight(.semibold))

            let attachments = currentVenue.attachments.filter {
                $0.parent == .venue && $0.parentID == currentVenue.id
            }
            if store.isLoadingVenueAttachments(for: currentVenue.id), attachments.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading documents…")
                }
                .font(.subheadline)
                .foregroundStyle(VowbaseTheme.mutedInk)
            } else if attachments.isEmpty {
                ContentUnavailableView(
                    "No documents yet",
                    systemImage: "doc",
                    description: Text("Contracts, proposals, and PDFs for this venue will appear here."))
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(attachments) { attachment in
                    Button {
                        downloadAndPreview(attachment)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: documentIcon(for: attachment))
                                .font(.title3)
                                .foregroundStyle(VowbaseTheme.rose)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(attachment.fileName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(VowbaseTheme.ink)
                                    .lineLimit(1)
                                Text(documentSubtitle(for: attachment))
                                    .font(.caption)
                                    .foregroundStyle(VowbaseTheme.mutedInk)
                            }
                            Spacer(minLength: 0)
                            if downloadingAttachmentID == attachment.id {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.down.circle")
                                    .foregroundStyle(VowbaseTheme.mutedInk)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(downloadingAttachmentID != nil)

                    if attachment.id != attachments.last?.id {
                        Divider()
                    }
                }
            }

            if let error = store.venueAttachmentError(for: currentVenue.id) ?? documentDownloadError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(VowbaseTheme.rose)
            }
        }
        .padding()
        .background(VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VowbaseTheme.border, lineWidth: 1)
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
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Button {
                        beginEditingLocation()
                    } label: {
                        Label(displayValue(for: .location), systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                            .foregroundStyle(flashingFields.contains(.location) ? VowbaseTheme.rose : VowbaseTheme.mutedInk)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    Button("View on map", action: onViewOnMap)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(VowbaseTheme.rose)
                }
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

    private func beginDetailsEditing() {
        websiteDraft = currentVenue.website ?? ""
        contactNameDraft = currentVenue.contactName ?? ""
        contactEmailDraft = currentVenue.contactEmail ?? ""
        contactPhoneDraft = currentVenue.contactPhone ?? ""
        notesDraft = currentVenue.ourNotes ?? ""
        detailsSaveError = nil
        isDetailsEditing = true
    }

    /// Back leaves the editor in the venue detail rather than popping its navigation
    /// destination. Draft values are intentionally discarded; Save is the one commit point.
    private func cancelDetailsEditing() {
        focusedField = nil
        isDetailsEditing = false
        detailsSaveError = nil
    }

    private func saveDetails() {
        let original = VenueDetailsDraft(venue: currentVenue)
        let draft = VenueDetailsDraft(
            website: websiteDraft,
            contactName: contactNameDraft,
            contactEmail: contactEmailDraft,
            contactPhone: contactPhoneDraft,
            notes: notesDraft
        )
        let patch = draft.patch(comparedWith: original)
        guard !patch.isEmpty else {
            isDetailsEditing = false
            return
        }

        isSavingDetails = true
        detailsSaveError = nil
        let venueID = currentVenue.id
        Task {
            let result = await store.patchVenue(id: venueID, patch)
            isSavingDetails = false
            guard result != nil else {
                detailsSaveError = "Couldn't save details. Try again."
                return
            }
            focusedField = nil
            isDetailsEditing = false
        }
    }

    private func websiteURL(from value: String?) -> URL? {
        guard let value = value?.trimmed, !value.isEmpty else { return nil }
        let candidate = value.contains("://") ? value : "https://\(value)"
        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else { return nil }
        return url
    }

    private func emailURL(from value: String?) -> URL? {
        guard let value = value?.trimmed, value.contains("@"),
              !value.contains(where: { $0.isWhitespace })
        else { return nil }
        return URL(string: "mailto:\(value)")
    }

    private func phoneURL(from value: String?) -> URL? {
        guard let value = value?.trimmed else { return nil }
        let dialing = value.filter { $0.isNumber || $0 == "+" || $0 == "*" || $0 == "#" }
        guard dialing.contains(where: \.isNumber) else { return nil }
        return URL(string: "tel:\(dialing)")
    }

    private func documentIcon(for attachment: Attachment) -> String {
        let isPDF = attachment.mimeType?.lowercased() == "application/pdf"
            || attachment.fileName.lowercased().hasSuffix(".pdf")
        return isPDF ? "doc.richtext" : "doc"
    }

    private func documentSubtitle(for attachment: Attachment) -> String {
        let type = attachment.mimeType?.nilIfBlank ?? "Document"
        guard let sizeBytes = attachment.sizeBytes else { return type }
        return "\(type) · \(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file))"
    }

    private func downloadAndPreview(_ attachment: Attachment) {
        guard attachment.parent == .venue, attachment.parentID == currentVenue.id else { return }
        downloadingAttachmentID = attachment.id
        documentDownloadError = nil
        Task {
            do {
                let data = try await store.downloadVenueAttachment(attachment)
                let fileName = URL(fileURLWithPath: attachment.fileName).lastPathComponent
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(attachment.id.uuidString)-\(fileName)")
                try data.write(to: destination, options: .atomic)
                documentPreview = VenueDocumentPreview(id: attachment.id, url: destination)
            } catch {
                documentDownloadError = "Couldn't download \(attachment.fileName). Try again."
            }
            downloadingAttachmentID = nil
        }
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

private struct VenueDetailsDraft {
    let website: String
    let contactName: String
    let contactEmail: String
    let contactPhone: String
    let notes: String

    init(venue: MVPVenue) {
        website = venue.website ?? ""
        contactName = venue.contactName ?? ""
        contactEmail = venue.contactEmail ?? ""
        contactPhone = venue.contactPhone ?? ""
        notes = venue.ourNotes ?? ""
    }

    init(website: String, contactName: String, contactEmail: String, contactPhone: String, notes: String) {
        self.website = website
        self.contactName = contactName
        self.contactEmail = contactEmail
        self.contactPhone = contactPhone
        self.notes = notes
    }

    func patch(comparedWith original: Self) -> VenuePatch {
        VenuePatch(
            contactName: nullablePatch(contactName, comparedWith: original.contactName),
            contactEmail: nullablePatch(contactEmail, comparedWith: original.contactEmail),
            contactPhone: nullablePatch(contactPhone, comparedWith: original.contactPhone),
            website: nullablePatch(website, comparedWith: original.website),
            ourNotes: nullablePatch(notes, comparedWith: original.notes)
        )
    }

    private func nullablePatch(_ value: String, comparedWith original: String) -> NullablePatch<String> {
        let trimmed = value.trimmed
        guard trimmed != original.trimmed else { return .unchanged }
        return trimmed.isEmpty ? .null : .value(trimmed)
    }
}

private struct VenueDocumentPreview: Identifiable {
    let id: UUID
    let url: URL
}

private struct VenueDocumentQuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
            url as NSURL
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
