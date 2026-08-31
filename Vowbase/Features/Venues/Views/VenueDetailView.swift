import SwiftUI
import UIKit
import QuickLook
import PhotosUI
import UniformTypeIdentifiers

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
    let allowsVerticalScrolling: Bool
    let onRequestExpansion: () -> Void
    let onRequestCollapse: () -> Void
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
    @State private var documentPreviewTemporaryURL: URL?
    @State private var downloadingDocumentID: UUID?
    @State private var documentDownloadError: String?
    @State private var isImportingDocument = false
    @State private var isUploadingDocument = false
    @State private var deletingDocumentID: UUID?
    @State private var pendingDocumentDeletion: VenueDocument?

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    @State private var deletingPhotoID: String?
    @State private var pendingPhotoDeletion: VenuePhotoDeletionTarget?
    @State private var photoOperationError: String?

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
    @State private var locationSelection: AppleMapsAddressSelection?

    private var shareURL: URL? {
        store.wedding.map { VowbaseDeepLink.venue(weddingID: $0.id, venueID: venue.id).url }
    }

    init(
        venue: MVPVenue,
        store: VowbaseWorkspaceStore,
        isNoteEditing: Binding<Bool>,
        onViewOnMap: @escaping () -> Void = {},
        allowsVerticalScrolling: Bool = true,
        onRequestExpansion: @escaping () -> Void = {},
        onRequestCollapse: @escaping () -> Void = {}
    ) {
        self.venue = venue
        self.store = store
        self._isNoteEditing = isNoteEditing
        self.onViewOnMap = onViewOnMap
        self.allowsVerticalScrolling = allowsVerticalScrolling
        self.onRequestExpansion = onRequestExpansion
        self.onRequestCollapse = onRequestCollapse
    }

    /// The screen must read live data by id — `venue` is a snapshot captured at
    /// navigation-push time and never refreshes on its own when `store.venues` changes.
    private var currentVenue: MVPVenue {
        store.venues.first(where: { $0.id == venue.id }) ?? venue
    }

    private func displayedPhotoItems(for venue: MVPVenue) -> [VenuePhotoItem] {
        var items = [VenuePhotoItem]()
        var seen = Set<URL>()
        if let coverURL = venue.coverPhotoURL, seen.insert(coverURL).inserted {
            items.append(.init(
                id: "cover-\(venue.id.uuidString)",
                url: coverURL,
                deletionTarget: .cover(venueID: venue.id)
            ))
        }
        for display in venue.photos {
            guard let url = display.url, seen.insert(url).inserted else { continue }
            items.append(.init(
                id: display.id.uuidString,
                url: url,
                deletionTarget: .gallery(display.photo)
            ))
        }
        return items
    }

    var body: some View {
        // `store.venues` builds display models on demand. Resolve this venue once per
        // render pass, then reuse that snapshot for the scroll content and chrome.
        let currentVenue = self.currentVenue
        let photoItems = displayedPhotoItems(for: currentVenue)
        let heroPhotoURL = selectedHeroPhotoURL ?? currentVenue.photoURL

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroPhoto(photoItems: photoItems, venue: currentVenue, heroPhotoURL: heroPhotoURL)
                if !photoItems.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(photoItems) { photo in
                                Button {
                                    selectedHeroPhotoURL = photo.url == currentVenue.photoURL ? nil : photo.url
                                } label: {
                                    VowbaseVenueImage(url: photo.url)
                                        .frame(width: 108, height: 76)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(
                                                    heroPhotoURL == photo.url ? VowbaseTheme.rose : .clear,
                                                    lineWidth: 2
                                                )
                                        }
                                        .overlay {
                                            if deletingPhotoID == photo.deletionTarget.id {
                                                ProgressView()
                                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                    .background(.ultraThinMaterial)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Show photo")
                                .contextMenu {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        pendingPhotoDeletion = photo.deletionTarget
                                    }
                                }
                            }
                            addPhotoPicker(width: 74, height: 76)
                        }
                    }
                }

                if isUploadingPhoto {
                    Label("Uploading photo…", systemImage: "arrow.up.circle")
                        .font(.caption)
                        .foregroundStyle(VowbaseTheme.mutedInk)
                } else if let error = store.venuePhotoError(for: currentVenue.id) ?? photoOperationError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(VowbaseTheme.rose)
                }

                VStack(alignment: .leading, spacing: 8) {
                    venueHeader(venue: currentVenue)
                    errorCaption(.name)
                    errorCaption(.status)

                    locationRow(venue: currentVenue)
                }

                if let summary = currentVenue.summary?.nilIfBlank {
                    Text(summary)
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }

                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], alignment: .leading, spacing: 18) {
                    capacityCell(venue: currentVenue)
                    factCell(venue: currentVenue, icon: "dollarsign.circle", field: .estimate, placeholder: "Add venue est.", caption: "venue est.")
                    factCell(venue: currentVenue, icon: "dollarsign.square", field: .allInEstimate, placeholder: "Add all-in est.", caption: "all-in est.")
                    factCell(venue: currentVenue, icon: "calendar", field: .availableDates, placeholder: "Add dates", caption: "available dates")
                }
                .padding()
                .background(VowbaseTheme.blush, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                venueCustomFieldsSection(venue: currentVenue)
                detailsSection(venue: currentVenue)
                documentsSection(venue: currentVenue)
                notesSection(venue: currentVenue)
            }
            .padding(16)
            .containerRelativeFrame(.horizontal, alignment: .leading)
            .clipped()
        }
        .consoleVerticalScrollHandoff(
            allowsVerticalScrolling: allowsVerticalScrolling,
            onExpand: onRequestExpansion,
            onCollapse: onRequestCollapse
        )
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
                    VowbaseConfirmationToolbarButton("Save Venue", isDisabled: isSavingDetails) {
                        saveDetails()
                    }
                }
            } else {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        beginDetailsEditing()
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Edit venue details and notes")

                    if let shareURL {
                        ShareLink(item: shareURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share venue")
                    }

                    Button {
                        isConfirmingDeletion = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Delete Venue")
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
        .sheet(item: $documentPreview, onDismiss: {
            if let documentPreviewTemporaryURL {
                try? FileManager.default.removeItem(at: documentPreviewTemporaryURL)
            }
            documentPreviewTemporaryURL = nil
        }) { preview in
            VenueDocumentPreviewSheet(url: preview.url)
        }
        .fileImporter(
            isPresented: $isImportingDocument,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false,
            onCompletion: importDocument
        )
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            importPhoto(item)
        }
        .alert(item: $pendingDocumentDeletion) { document in
            Alert(
                title: Text("Delete \(document.fileName)?"),
                message: Text("This permanently removes the document from this venue."),
                primaryButton: .destructive(Text("Delete")) { deleteDocument(document) },
                secondaryButton: .cancel()
            )
        }
        .alert(item: $pendingPhotoDeletion) { target in
            Alert(
                title: Text("Delete photo?"),
                message: Text("This permanently removes the photo from this venue."),
                primaryButton: .destructive(Text("Delete")) { deletePhoto(target) },
                secondaryButton: .cancel()
            )
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
            if let documentPreviewTemporaryURL {
                try? FileManager.default.removeItem(at: documentPreviewTemporaryURL)
            }
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

    @ViewBuilder
    private func venueCustomFieldsSection(venue: MVPVenue) -> some View {
        let columns = store.visibleVenueCustomColumns
        if store.venueCustomFieldsUnavailable {
            VStack(alignment: .leading, spacing: 4) {
                Text("Custom Fields").font(.title2.weight(.semibold))
                Text("Custom fields couldn’t be loaded. The rest of this venue is up to date.")
                    .font(.footnote).foregroundStyle(VowbaseTheme.mutedInk)
            }
        } else if !columns.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Custom Fields").font(.title2.weight(.semibold))
                    Spacer()
                    NavigationLink(value: VenuesRoute.customFields) {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    .accessibilityLabel("Manage fields")
                }
                ForEach(columns) { column in
                    VenueCustomFieldDetailRow(
                        column: column,
                        stored: VenueCustomFields.value(in: store.venueRecord(id: venue.id)?.customFields ?? .object([:]), for: column.key),
                        state: store.venueCustomFieldSaveState(.init(venueID: venue.id, key: column.key)),
                        commit: { store.commitVenueCustomField(column, for: venue.id, value: $0) }
                    )
                }
            }
            .padding()
            .background(VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VowbaseTheme.border, lineWidth: 1) }
        }
    }

    @ViewBuilder
    private func heroPhoto(
        photoItems: [VenuePhotoItem],
        venue: MVPVenue,
        heroPhotoURL: URL?
    ) -> some View {
        if photoItems.isEmpty {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                VowbaseVenueImage(
                    url: nil,
                    placeholderSystemImage: "photo.badge.plus"
                )
                .frame(height: 270)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    if isUploadingPhoto {
                        ProgressView()
                            .controlSize(.large)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.ultraThinMaterial)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isUploadingPhoto)
            .accessibilityLabel("Add venue photo")
        } else {
            VowbaseVenueImage(
                url: heroPhotoURL,
                cacheKey: selectedHeroPhotoURL == nil ? venue.coverPhotoCacheKey : nil
            )
            .frame(height: 270)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func addPhotoPicker(width: CGFloat, height: CGFloat) -> some View {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            VowbaseVenueImage(
                url: nil,
                placeholderSystemImage: "photo.badge.plus",
                placeholderIconSize: 18
            )
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(VowbaseTheme.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isUploadingPhoto)
        .accessibilityLabel("Add venue photo")
    }

    private func importPhoto(_ item: PhotosPickerItem) {
        guard !isUploadingPhoto else { return }
        isUploadingPhoto = true
        photoOperationError = nil
        Task { @MainActor in
            defer {
                isUploadingPhoto = false
                selectedPhotoItem = nil
            }
            do {
                guard let sourceData = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: sourceData),
                      let jpegData = image.jpegData(compressionQuality: 0.9) else {
                    throw VenueDetailImportError.invalidPhoto
                }
                guard await store.uploadVenuePhoto(data: jpegData, venueID: currentVenue.id) else {
                    return
                }
                selectedHeroPhotoURL = nil
            } catch is CancellationError {
                return
            } catch {
                photoOperationError = "Couldn’t add that photo. Try another image."
            }
        }
    }

    private func deletePhoto(_ target: VenuePhotoDeletionTarget) {
        guard deletingPhotoID == nil else { return }
        deletingPhotoID = target.id
        photoOperationError = nil
        Task { @MainActor in
            let deleted: Bool
            switch target {
            case let .cover(venueID):
                deleted = await store.deleteVenueCoverPhoto(venueID: venueID)
            case let .gallery(photo):
                deleted = await store.deleteVenuePhoto(photo)
            }
            if deleted {
                selectedHeroPhotoURL = nil
            }
            deletingPhotoID = nil
        }
    }

    // MARK: - Shared field editing

    private func venueHeader(venue: MVPVenue) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                venueTitle(venue: venue, prefersIntrinsicWidth: true)
                statusMenu(for: venue)
            }

            VStack(alignment: .leading, spacing: 8) {
                venueTitle(venue: venue, prefersIntrinsicWidth: false)
                statusMenu(for: venue)
            }
        }
    }

    private func venueTitle(venue: MVPVenue, prefersIntrinsicWidth: Bool) -> some View {
        inlineTextField(
            .name,
            venue: venue,
            placeholder: "Venue name",
            font: VowbaseType.screenDisplay,
            autocapitalization: .words
        )
        .fixedSize(horizontal: prefersIntrinsicWidth, vertical: true)
    }

    private func statusMenu(for venue: MVPVenue) -> some View {
        Menu {
            ForEach([
                VenueStatus.considering, .contacted, .toured,
                .shortlisted, .negotiating, .booked, .passed,
            ], id: \.self) { status in
                Button(status.title) { commitStatus(status) }
            }
        } label: {
            StatusCapsule(status: optimisticStatus ?? venue.status)
                .fixedSize()
        }
    }

    @ViewBuilder
    private func inlineTextField(
        _ field: VenueEditableField,
        venue: MVPVenue,
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
            let value = displayValue(for: field, venue: venue)
            Button {
                beginEditingSimple(field)
            } label: {
                Text(value.isEmpty ? placeholder : value)
                    .font(font)
                    .foregroundStyle(
                        flashingFields.contains(field) ? VowbaseTheme.rose :
                            value.isEmpty ? VowbaseTheme.mutedInk : VowbaseTheme.ink
                    )
                    .lineLimit(field == .name ? nil : 1)
                    .multilineTextAlignment(.leading)
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
    private func detailsSection(venue: MVPVenue) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.title2.weight(.semibold))

            if isDetailsEditing {
                detailsEditor
            } else {
                detailsReadOnly(venue: venue)
            }
        }
        .padding()
        .background(VowbaseTheme.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VowbaseTheme.border, lineWidth: 1)
        }
    }

    private func detailsReadOnly(venue: MVPVenue) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            detailReadOnlyRow(
                title: "Website",
                value: venue.website,
                placeholder: "Not added",
                icon: "link",
                destination: websiteURL(from: venue.website)
            )
            detailReadOnlyRow(
                title: "Contact",
                value: venue.contactName,
                placeholder: "Not added",
                icon: "person",
                destination: nil
            )
            detailReadOnlyRow(
                title: "Email",
                value: venue.contactEmail,
                placeholder: "Not added",
                icon: "envelope",
                destination: emailURL(from: venue.contactEmail)
            )
            detailReadOnlyRow(
                title: "Phone",
                value: venue.contactPhone,
                placeholder: "Not added",
                icon: "phone",
                destination: phoneURL(from: venue.contactPhone)
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

    private func notesSection(venue: MVPVenue) -> some View {
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
                noteDisplay(displayValue(for: .notes, venue: venue))
                    .textSelection(.enabled)
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
        .contextMenu {
            if let value = value?.nilIfBlank {
                Button {
                    UIPasteboard.general.string = value
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        }
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
    private func documentsSection(venue: MVPVenue) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Documents")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    isImportingDocument = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .background(VowbaseTheme.blush, in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(VowbaseTheme.rose)
                .disabled(isUploadingDocument)
                .accessibilityLabel("Upload venue document")
            }

            let documents = venue.documents
            if store.isLoadingVenueDocuments(for: venue.id), documents.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading documents…")
                }
                .font(.subheadline)
                .foregroundStyle(VowbaseTheme.mutedInk)
            } else if documents.isEmpty {
                Label("No documents yet", systemImage: "doc")
                    .font(.subheadline)
                    .foregroundStyle(VowbaseTheme.mutedInk)
                    .padding(.vertical, 4)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(documents) { document in
                        documentRow(document)
                            .padding(.vertical, 8)
                            .frame(height: 64)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    pendingDocumentDeletion = document
                                }
                            }
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    pendingDocumentDeletion = document
                                }
                            }
                            .accessibilityAction(named: "Delete") {
                                pendingDocumentDeletion = document
                            }
                        if document.id != documents.last?.id {
                            Divider()
                        }
                    }
                }
            }

            if isUploadingDocument {
                Label("Uploading document…", systemImage: "arrow.up.circle")
                    .font(.caption)
                    .foregroundStyle(VowbaseTheme.mutedInk)
            }

            if let error = store.venueDocumentError(for: venue.id) ?? documentDownloadError {
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

    private func documentRow(_ document: VenueDocument) -> some View {
        Button {
            downloadAndPreview(document)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: documentIcon(for: document))
                    .font(.title3)
                    .foregroundStyle(VowbaseTheme.rose)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(document.fileName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(VowbaseTheme.ink)
                        .lineLimit(1)
                    Text(documentSubtitle(for: document))
                        .font(.caption)
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }
                Spacer(minLength: 0)
                if downloadingDocumentID == document.id || deletingDocumentID == document.id {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(downloadingDocumentID != nil || deletingDocumentID != nil)
    }

    @ViewBuilder
    private func factCell(
        venue: MVPVenue,
        icon: String,
        field: VenueEditableField,
        placeholder: String,
        caption: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label {
                inlineTextField(field, venue: venue, placeholder: placeholder, font: .system(size: 16, weight: .semibold))
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
    private func capacityCell(venue: MVPVenue) -> some View {
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
                        Text(capacityDisplayValue(for: venue))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(
                                flashingFields.contains(.capacityMin) ? VowbaseTheme.rose :
                                    isCapacityUnset(for: venue) ? VowbaseTheme.mutedInk : VowbaseTheme.ink
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

    private func isCapacityUnset(for venue: MVPVenue) -> Bool {
        venue.capacityMin == nil && venue.capacityMax == nil && venue.capacityTextOverride == nil
    }

    private func capacityDisplayValue(for venue: MVPVenue) -> String {
        if let override = optimisticValues[.capacityMin] { return override }
        return isCapacityUnset(for: venue) ? "Add capacity" : venue.capacity
    }

    @ViewBuilder
    private func locationRow(venue: MVPVenue) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if editingField == .location {
                AppleMapsAddressField(
                    text: $locationDraft,
                    selection: $locationSelection,
                    placeholder: "Address or location",
                    onSubmit: {
                        editingField = nil
                        commitLocation()
                    }
                )
                    .font(.subheadline)
                    .foregroundStyle(VowbaseTheme.ink)
                    .onChange(of: locationSelection) { _, selection in
                        guard let selection else { return }
                        editingField = nil
                        commitLocation(selected: selection)
                    }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Button {
                        beginEditingLocation()
                    } label: {
                        Label(displayValue(for: .location, venue: venue), systemImage: "mappin.and.ellipse")
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
            if venue.coordinate == nil {
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

    private func displayValue(for field: VenueEditableField, venue: MVPVenue) -> String {
        optimisticValues[field] ?? rawStringValue(for: field, venue: venue)
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

    private func documentIcon(for document: VenueDocument) -> String {
        let isPDF = document.mimeType?.lowercased() == "application/pdf"
            || document.fileName.lowercased().hasSuffix(".pdf")
        return isPDF ? "doc.richtext" : "doc"
    }

    private func documentSubtitle(for document: VenueDocument) -> String {
        let type = document.mimeType?.nilIfBlank ?? "Document"
        guard let sizeBytes = document.sizeBytes else { return type }
        return "\(type) · \(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file))"
    }

    private func downloadAndPreview(_ document: VenueDocument) {
        guard document.venueID == currentVenue.id else { return }
        downloadingDocumentID = document.id
        documentDownloadError = nil
        Task { @MainActor in
            do {
                let data = try await store.downloadVenueDocument(document)
                let fileName = URL(fileURLWithPath: document.fileName).lastPathComponent
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(document.id.uuidString)-\(fileName)")
                try data.write(to: destination, options: .atomic)
                documentPreviewTemporaryURL = destination
                documentPreview = VenueDocumentPreview(id: document.id, url: destination)
            } catch {
                documentDownloadError = "Couldn’t download \(document.fileName). Try again."
            }
            downloadingDocumentID = nil
        }
    }

    private func importDocument(_ result: Result<[URL], any Error>) {
        guard !isUploadingDocument else { return }
        switch result {
        case let .failure(error):
            if (error as? CocoaError)?.code != .userCancelled {
                documentDownloadError = "Couldn’t open that file. Try again."
            }
        case let .success(urls):
            guard let url = urls.first else { return }
            isUploadingDocument = true
            documentDownloadError = nil
            Task { @MainActor in
                defer { isUploadingDocument = false }
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess { url.stopAccessingSecurityScopedResource() }
                }
                do {
                    let values = try url.resourceValues(forKeys: [.contentTypeKey])
                    let mimeType = values.contentType?.preferredMIMEType ?? "application/octet-stream"
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    guard await store.uploadVenueDocument(
                        data: data,
                        fileName: url.lastPathComponent,
                        mimeType: mimeType,
                        venueID: currentVenue.id
                    ) else {
                        return
                    }
                } catch is CancellationError {
                    return
                } catch {
                    documentDownloadError = "Couldn’t upload that file. Try again."
                }
            }
        }
    }

    private func deleteDocument(_ document: VenueDocument) {
        guard deletingDocumentID == nil else { return }
        deletingDocumentID = document.id
        documentDownloadError = nil
        Task { @MainActor in
            _ = await store.deleteVenueDocument(document)
            deletingDocumentID = nil
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
        rawStringValue(for: field, venue: currentVenue)
    }

    private func rawStringValue(for field: VenueEditableField, venue: MVPVenue) -> String {
        switch field {
        case .name: venue.name
        case .estimate: venue.venueEstimateTextRaw ?? ""
        case .allInEstimate: venue.allInEstimate == "Not added" ? "" : venue.allInEstimate
        case .availableDates: venue.availableDates == "Not added" ? "" : venue.availableDates
        case .notes: venue.ourNotes ?? ""
        case .website: venue.website ?? ""
        case .contactName: venue.contactName ?? ""
        case .contactEmail: venue.contactEmail ?? ""
        case .contactPhone: venue.contactPhone ?? ""
        case .location: venue.location == "Location not added" ? "" : venue.location
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
        locationSelection = nil
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

    /// Committing a typed string with no selection stores the literal text and clears
    /// coordinates; committing a selected suggestion stores its normalized label and
    /// coordinates. Spec §4.6 — this is what keeps the map tab from silently drifting.
    private func commitLocation(selected: AppleMapsAddressSelection? = nil) {
        let venueID = currentVenue.id
        let patch: VenuePatch
        let display: String

        if let selected {
            patch = VenuePatch(
                address: .value(selected.address),
                city: selected.city.map(NullablePatch.value) ?? .null,
                state: selected.state.map(NullablePatch.value) ?? .null,
                country: selected.country.map(NullablePatch.value) ?? .null,
                latitude: .value(selected.latitude),
                longitude: .value(selected.longitude)
            )
            display = selected.address
        } else {
            let trimmed = locationDraft.trimmed
            let current = rawStringValue(for: .location)
            guard trimmed != current else { return }
            if trimmed.isEmpty {
                patch = VenuePatch(address: .null, city: .null, state: .null, country: .null, latitude: .null, longitude: .null)
                display = "Location not added"
            } else {
                patch = VenuePatch(address: .value(trimmed), city: .null, state: .null, country: .null, latitude: .null, longitude: .null)
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

private struct VenuePhotoItem: Identifiable {
    let id: String
    let url: URL
    let deletionTarget: VenuePhotoDeletionTarget
}

private enum VenuePhotoDeletionTarget: Identifiable {
    case cover(venueID: UUID)
    case gallery(VenuePhoto)

    var id: String {
        switch self {
        case let .cover(venueID): "cover-\(venueID.uuidString)"
        case let .gallery(photo): "gallery-\(photo.id.uuidString)"
        }
    }
}

private enum VenueDetailImportError: Error {
    case invalidPhoto
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

private struct VenueDocumentPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let url: URL

    var body: some View {
        NavigationStack {
            VenueDocumentQuickLookPreview(url: url)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Close document preview")
                    }
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

private struct VenueCustomFieldDetailRow: View {
    let column: VenueCustomColumn
    let stored: JSONValue?
    let state: VenueCustomFieldSaveState?
    let commit: (JSONValue?) -> Void
    @State private var draftText: String?

    var body: some View {
        if VenueCustomFields.isUnsupported(stored, kind: column.kind) {
            LabeledContent(column.label) { Button("Clear") { commit(nil) }.tint(VowbaseTheme.rose) }
        } else {
            switch column.kind {
            case .checkbox:
                Toggle(column.label, isOn: Binding(get: { stored == .bool(true) }, set: { commit($0 ? .bool(true) : .bool(false)) }))
                    .tint(VowbaseTheme.rose)
            case .select:
                LabeledContent(column.label) {
                    Menu {
                        ForEach(VenueCustomFields.options(in: column), id: \.self) { option in
                            Button(option) { commit(.string(option)) }
                        }
                        if stored != nil { Divider(); Button("Clear", role: .destructive) { commit(nil) } }
                    } label: { Text(VenueCustomFields.displayText(stored, kind: .select) ?? "Not set") }
                }
            case .text, .number:
                LabeledContent(column.label) {
                    HStack(spacing: 8) {
                        TextField(
                            "Not set",
                            text: Binding(
                                get: {
                                    draftText
                                        ?? VenueCustomFields.displayText(stored, kind: column.kind)
                                        ?? ""
                                },
                                set: { draftText = $0 }
                            )
                        )
                        .multilineTextAlignment(.trailing)
                        .keyboardType(column.kind == .number ? .decimalPad : .default)
                        .onSubmit {
                            commit(VenueCustomFields.encode(draftText ?? "", kind: column.kind))
                            draftText = nil
                        }
                        if stored != nil {
                            Button("Clear") {
                                draftText = nil
                                commit(nil)
                            }
                            .font(.caption)
                        }
                    }
                }
            case .rank:
                LabeledContent(column.label) {
                    HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { score in
                            Button("\(score)") { commit(.number(Double(score))) }
                                .buttonStyle(.bordered)
                                .tint(rank == score ? VowbaseTheme.rose : VowbaseTheme.mutedInk)
                                .accessibilityLabel("\(column.label), \(score) of 5")
                        }
                        if rank != nil { Button("Clear") { commit(nil) }.font(.caption) }
                    }
                }
            }
        }
        if case .saving? = state { ProgressView().controlSize(.mini) }
        if case .failed? = state { Text("Couldn’t save. Try again.").font(.caption).foregroundStyle(VowbaseTheme.rose) }
    }

    private var rank: Int? {
        guard case let .number(value)? = stored, value.rounded() == value, (1...5).contains(Int(value)) else { return nil }
        return Int(value)
    }
}
