# Vowbase iOS — Venues tab UX design

Companion to `vowbase-ios-mvp-ux-spec.md`. That document defined the read-only Venues
shortlist and a form-sheet editor. This document designs the parts that were deferred:
in-place editing, notes, the photo carousel and upload, documents, and a real comparison
view — plus the scroll-clearance bug.

Where this document contradicts the MVP spec, this document wins. The one deliberate
reversal: the MVP spec said *"Edit opens a form sheet rather than making every label
inline-editable."* We are reversing that. Rationale is in §2.

**Resolved, 2026-07-30:**

| Question | Answer |
|---|---|
| Which column are "notes"? | `our_notes` — it's what the screen shows today whenever it has content. `notes` becomes read-only research. §4.5 |
| Can inline editing clear a field? | Yes. `VenuePatch` adopts `NullablePatch`. §10.1 |
| Does the name row get an edit glyph? | No glyph on any row. §4.2 |

---

## 1. Principles for this pass

1. **The detail screen is the editor.** There is no separate edit surface. Everything you
   can read, you can change where you read it.
2. **One interaction rule, everywhere: tap the row to edit it; tap an explicit glyph to
   act on it.** Calling, mailing, opening a website, and viewing on the map are all
   trailing glyphs with their own tap target. The row body is always "edit."
3. **Empty is a state, not an absence.** An unset field renders as a muted `Add capacity`
   row, not as nothing. The detail screen doubles as a checklist of what you still need to
   find out about a venue.
4. **Save is invisible.** No Save button, no dirty state, no confirmation. Commit on blur,
   patch a single field, revert visibly if the server rejects it.
5. **Comparison is the point of the tab.** Everything else exists to make the compare view
   trustworthy.

---

## 2. Why inline instead of a form sheet

The MVP spec chose a form sheet to avoid the web editor's density. In practice the sheet
has three problems, all visible in `EditVenueSheet` today:

- It only edits three of ~14 fields, so there is no route in the app to set capacity,
  price, website, or contact — the fields the compare view depends on.
- Growing it to 14 fields makes it exactly the dense web editor the spec was avoiding.
- Venue edits are overwhelmingly *single-field corrections* made while looking at the
  venue ("capacity is 220, not 200"). A modal round-trip for a two-character change is
  the wrong shape.

Inline editing solves all three: the field list can grow without ever getting denser than
the read view, and a correction costs one tap.

The density risk is real, and we manage it with §3's section model — not by hiding fields
behind a modal.

---

## 3. Venue Detail — structure

Single `ScrollView`, sections in this order. Section headers use `VowbaseType.headline`;
section bodies are `vowbaseCard()` surfaces except the hero.

```
┌────────────────────────────────────┐
│  ◀︎  Riverside Pavilion      •••    │  nav bar, title = venue name, inline
├────────────────────────────────────┤
│                                    │
│         PHOTO CAROUSEL             │  §5 — 3:2, paged, dots + counter
│                                    │
├────────────────────────────────────┤
│  Riverside Pavilion                │  name — tap to edit inline, no glyph
│  ( Toured ▾ )                      │  status — tap = menu
│  📍 Example City              🗺   │  location — tap = edit, glyph = View on map
├────────────────────────────────────┤
│  DECISION FACTS                    │  2×2 grid, each cell tappable
│  👥 150–350       💲 $53.7K        │
│  💲 Add all-in    📅 Add dates     │  unset = muted "Add …"
├────────────────────────────────────┤
│  NOTES                             │  §4
│  Tap to add your notes…            │
├────────────────────────────────────┤
│  DETAILS                           │  website, contact, email, phone, address
│  Website   vowbase.example    ↗︎   │
│  Contact   Add contact             │
├────────────────────────────────────┤
│  PHOTOS (6)              Manage    │  grid, §5/§6
├────────────────────────────────────┤
│  DOCUMENTS (2)              Add    │  §7
├────────────────────────────────────┤
│  FROM RESEARCH                     │  read-only, collapsed by default, §10.2
└────────────────────────────────────┘
                                        ← bottom clearance, §8
```

The overflow menu (`•••`) keeps only: `Share venue`, `Duplicate`, `Delete venue`. Edit is
gone from the menu — there is nothing left for it to open.

---

## 4. Inline editing — interaction spec

### 4.1 The field row

Every editable value is one of four row kinds:

| Kind | Fields | Read state | Edit state |
|---|---|---|---|
| **Text** | name, location, website, contact name/email/phone, capacity text, estimates, available dates | value, or muted `Add …` | in-place `TextField`, keyboard type per field, single line |
| **Long text** | notes | first 6 lines + `More` | expanding `TextEditor`, §4.4 |
| **Enum** | status | `StatusCapsule` | `Menu` anchored to the capsule — no row transition |
| **Numeric pair** | capacity min/max | `150–350` / `Add capacity` | two `TextField`s side by side with an en-dash between |

### 4.2 Entering and leaving edit

**No edit glyph on any row.** No pencil, no chevron, no "tap to edit" hint. A per-row glyph
would imply that rows without one aren't editable, which inverts the rule in §1 — and once
you learn the rule, the glyph is permanent noise on a screen you open weekly.

Discoverability rests on three things instead: the muted `Add …` rows, which are
self-evidently actionable and appear in every section; a highlight-on-touch-down on every
editable row, so the first stray tap teaches the rule; and VoiceOver's `.isButton` trait
plus a `Double tap to edit capacity` hint (§11), which never depended on the glyph. If
first-run testing shows people don't find it, the fix is a one-time coach mark on first
venue open, not permanent chrome on every row.

- **Enter:** tap anywhere in the row body. The row's text is replaced in place by a field
  with the same font, baseline, and leading. No layout jump — the field's frame matches
  the label's. Focus and keyboard are immediate; selection is "all" so overtyping replaces.
- **Row chrome while editing:** 1 pt `VowbaseTheme.rose` underline on the field, and the
  rest of the screen does not dim. Editing is not modal.
- **Commit:** Return key, tap outside the row, scroll, or navigating away. All four are
  equivalent.
- **Cancel:** there is no cancel. Undo is `⌘Z`/shake and the standard text-editing undo
  stack, which survives the commit for the duration of the screen.
- **Keyboard accessory:** a single `Done` button, plus `˄ ˅` to move between fields in the
  section. Field-to-field traversal commits the field you leave.

### 4.3 Persistence

- On commit, if the trimmed value differs from the stored value, issue a **single-field
  `VenuePatch`**. Do not patch the whole record.
- **Optimistic:** the new value is displayed immediately.
- **In flight:** no spinner in the row. A 2 pt rose progress hairline under the nav bar,
  same treatment for every field.
- **Failure:** the row reverts to the previous value with a brief rose flash, and an
  inline `Couldn't save — Retry` caption appears beneath that row only. Errors are never a
  full-screen state and never a toast that steals the correction.
- **Clearing:** emptying a field sets the column to `NULL`. This requires a data-layer
  change — see §10.1.
- **Debounce:** none. Commit is an explicit user act; patch immediately.

### 4.4 Notes specifically

Notes is the one field where commit-on-blur is not enough — people type a paragraph, get
interrupted, and background the app.

- Tapping the Notes card expands it to a `TextEditor` that grows with content, minimum
  6 lines, no internal scroll until ~20 lines.
- **Autosave on a 2 s idle timer**, plus on blur, plus on `scenePhase != .active`.
- A muted caption under the card shows `Saved · 2 min ago` (relative, updates on appear).
  While a save is pending it reads `Saving…`. This is the only place we show save state,
  because it is the only place where losing input would hurt.
- Formatting is plain text. No rich text, no markdown rendering in this pass.
- The card in read state shows 6 lines and a `More` affordance; expanded read state has no
  cap. Tapping the collapsed body enters edit at the tapped character offset.

### 4.5 Which field is "notes" — decided

Today `MVPVenue.notes` resolves `our_notes ?? notes` (`ContentView.swift:2043`), but
`VenuePatch` can only write `notes`. On a venue with research-populated `our_notes`,
everything the user types goes to `notes` and is never displayed again. **This is a live
data-loss bug**, not just a gap.

The displayed field today is a fallback chain, not one column, so "keep what's shown"
resolves to: **`our_notes` is the field, because it wins the coalesce whenever it has
content.** Settled as:

- `our_notes` is the couple's notes. It is what the Notes section reads and writes.
- `notes` is research-sourced prose. It becomes read-only, rendered in the **From
  Research** section (§3), and is never written from iOS.
- `VenuePatch` gains `ourNotes`. See §10.1.

**One behavior change to expect.** On a venue where `our_notes` is empty and `notes` has
research prose, that prose is displayed in the Notes area *today*. After this change it
moves down to From Research and the Notes card starts empty. That is the intended outcome —
you should not be typing on top of text you didn't write — but it will look like content
moved on venues that came from research.

The rejected alternative was seeding: pre-fill the editor with the research prose on first
edit. It reads better in the moment and costs provenance — you end up with two near-identical
copies and no way to tell which sentence was the couple's. Not worth it.

### 4.6 Location is special

Editing location must keep coordinates in sync or the map tab silently drifts. Tapping the
location row opens an inline autocomplete: the field becomes editable and a result list
drops below it (reusing `MapWorkflowRepository.geocode`, throttled ~1 s as the web client
does). Committing a *typed* string with no selection stores the literal text and **clears**
`latitude`/`longitude`/`city`/`state`/`country`; committing a *selected* result stores the
normalized label and its coordinates. The row shows a muted `Not on map` caption whenever
coordinates are absent, so the tradeoff is visible at the moment it's made.

---

## 5. Photo carousel

Replaces today's hero image + thumbnail strip.

### 5.1 The carousel

- `TabView` with `.tabViewStyle(.page(indexDisplayMode: .never))`, 3:2, full-bleed to the
  screen edges, `VowbaseRadius.large` corners, height ≈ 270 pt as today.
- **Page dots** are custom, not the system set: 6 pt rose dot for current, 5 pt
  `mutedInk.opacity(0.35)` otherwise, centred, overlaid on the image bottom with a
  20 pt gradient scrim so they stay legible on any photo. Above 8 photos, dots collapse to
  a `3 / 12` counter pill instead.
- Swipe left/right pages. Paging is the only gesture; pinch is reserved for the full-screen
  viewer.
- **One photo:** no dots, no counter, no paging — identical to today's hero.
- **Zero photos:** blush placeholder with `mappin.and.ellipse` and an `Add photos` button
  centred in it. The placeholder is the primary upload entry point for an empty venue.
- Loading uses a blush shimmer at the correct aspect ratio so the page never reflows.
  Signed URLs expire (1 h) — a failed load shows a retry glyph, not a broken frame.

### 5.2 Full-screen viewer

Tapping the carousel opens a full-screen cover:

- Black background, matched-geometry zoom transition from the tapped page.
- Horizontal paging preserves the carousel's index; double-tap and pinch zoom to 3×;
  drag-down dismisses with the image tracking the finger.
- Top bar: `Done`, page counter, `•••` menu → `Set as cover`, `Share`, `Save to Photos`,
  `Delete photo` (destructive, confirms).
- Bottom: caption, editable inline with the same rules as §4 (`VenuePhotoPatch.caption`),
  and `source` shown as a muted attribution line when the photo came from research
  (`gplaces:`), since those aren't ours to re-share.

### 5.3 Manage photos

`Manage` in the Photos section header opens a sheet with a 3-column grid:

- Drag to reorder → writes `sortOrder` for the affected range in one batched pass.
- The first photo is the cover, marked with a rose `Cover` pill. `Set as cover` in the
  viewer moves that photo to index 0 rather than writing `venues.photo_url`, so there is
  exactly one ordering source of truth.
- Multi-select → `Delete`.
- Research photos and uploaded photos are visually distinguished by a small corner glyph
  (`sparkle` vs `photo.on.rectangle`) so the couple knows which ones they own.

---

## 6. Photo upload

### 6.1 Entry points

Three, all landing in the same pipeline:

1. `Add photos` in the Photos section header → `PhotosPicker`, `selectionLimit: 10`,
   `.images` filter.
2. `Take photo` → camera. Same sheet, second menu item.
3. Empty-carousel placeholder button → the picker.

### 6.2 Pipeline

```
PhotosPickerItem
  → loadTransferable(Data)
  → downsample to 2048 pt long edge, JPEG q0.8      (client-side, off main actor)
  → upload to storage bucket "venue-photos"
        path: {weddingID}/{venueID}/{uuid}.jpg
  → createVenuePhoto(VenuePhotoDraft(
        url: <that storage path>,                    ← path, not URL, see below
        source: "upload",
        caption: nil,
        sortOrder: max(existing) + 1))
  → resolve signed URL, insert into the carousel
```

`VenuePhotoURLResolver` already accepts a bare storage path and signs it via
`signStoragePhoto`, so storing the path (not a URL) in `venue_photos.url` is the existing
contract and requires no resolver change. What's missing is the **upload** half — see
§10.3.

### 6.3 Progress and failure

- Each queued photo appears immediately as a grid tile from local `Data` with a
  determinate rose ring. The carousel does not change until upload succeeds, so a failed
  upload never becomes a phantom cover photo.
- Uploads run at concurrency 2, continue across navigation away from the detail screen,
  and are cancelled only by the user.
- Failure leaves the tile in place with a `Retry` overlay and a one-line reason. `Retry`
  re-runs from the downsampled data — no re-picking.
- HEIC, Live Photos (still frame only), and screenshots all normalize to JPEG. Anything
  over 25 MB after downsampling is rejected up front with a clear message.

---

## 7. Documents

Nothing in the app uses `AttachmentRepository` today even though it is fully implemented
and wired into `RepositoryContainer`, with `AttachmentParent.venue` already defined. This
section is mostly UI over an existing capability.

### 7.1 The section

```
DOCUMENTS (3)                                    Add ⌄
─────────────────────────────────────────────────────
📄  Riverside — 2027 Pricing.pdf
    PDF · 1.2 MB · Added by Calvin · Mar 4
📄  Catering menu.pdf
    PDF · 480 KB · Added by Priya · Feb 28
🖼  Floorplan.png
    PNG · 2.1 MB · Added by Calvin · Feb 12
```

- Rows are ordered newest first. Icon is type-derived: `doc.richtext` for PDF,
  `photo` for images, `doc` otherwise — tinted rose for PDF since that's the optimized case.
- Swipe-to-delete with a confirmation naming the file. Deletion removes both the storage
  object and the metadata row (`AttachmentRepository.delete` already does both).
- Rename is out of scope for this pass — `Attachment` has no patch path.
- Section is hidden entirely when empty *except* for the `Add` button, which stays. An
  empty-state line reads `Contracts, quotes, and floorplans live here.`

### 7.2 Viewer — optimized for PDF

Tapping a row opens a full-screen cover:

- **PDF:** `PDFKit.PDFView` in a `UIViewRepresentable`. Continuous vertical scroll,
  `autoScales`, page-fit on open. Nav bar shows the filename; a `Page 3 of 18` pill sits
  bottom-centre and taps into a page-thumbnail sidebar (`PDFThumbnailView`). Text is
  selectable and searchable via a `Find` action. `Share` uses `ShareLink`.
- **Images:** the §5.2 viewer, minus the photo-specific menu items.
- **Anything else:** `QLPreviewController`. This is the fallback, not the default, because
  QuickLook gives up the page counter and thumbnail rail that make a 40-page venue contract
  navigable.
- Download-to-view: show a determinate progress view over a blurred first-page placeholder.
  Cache the downloaded `Data` in `URL.cachesDirectory/attachments/{id}` and serve from
  cache on subsequent opens; evict on delete and under memory pressure.

### 7.3 Adding

`Add ⌄` is a menu with three items:

1. **Choose file** → `.fileImporter`, `allowedContentTypes: [.pdf, .image, .plainText, .commaSeparatedText]`, multiple selection on. Remember to bracket reads with `startAccessingSecurityScopedResource()`.
2. **Scan document** → `VisionKit.VNDocumentCameraViewController`, pages composited into a
   single PDF named `Scan — {venue name} — {date}.pdf`. This is the highest-value entry
   point: venue contracts arrive on paper at site visits.
3. **From Files app** is the same as (1) — do not duplicate it.

Upload uses `AttachmentRepository.upload(data:fileName:mimeType:weddingID:parent:.venue:parentID:)`
verbatim. Progress, concurrency, and retry follow §6.3 exactly — one shared upload-queue
model serves both photos and documents.

---

## 8. The scroll-clearance bug

### 8.1 What's wrong

`WeddingAppShell` installs the tab bar with `.safeAreaInset(edge: .bottom)`, which is
correct, but three things undo it:

- `VenuesView` compensates *again* with a hard-coded `.padding(.bottom, 96)`
  (`ContentView.swift:588`), so the list is double-inset while the detail screen is not
  inset at all.
- `VenueDetailView` has only `.padding(16)` (`ContentView.swift:818`) — the last content in
  the venue detail sits under the tab bar. This is the bug as reported.
- The Quick Add FAB floats 90 pt above the bottom edge and is **outside** the safe-area
  inset, so it covers the trailing edge of the last card on every list screen regardless of
  the tab bar inset.

### 8.2 The fix

One token, one modifier, applied to every scroll container in the app — no per-screen
padding constants.

```swift
extension VowbaseControlMetric {
    /// Clearance for the floating tab bar. The bar is already a safe-area inset;
    /// this covers the Quick Add FAB, which floats outside it.
    static let quickAddClearance: CGFloat = fabDiameter + VowbaseSpace.large   // 88
}

extension View {
    /// Bottom breathing room for scrollable screens under the floating chrome.
    /// `includesQuickAdd` is false on pushed detail screens, which have no FAB.
    func vowbaseScrollClearance(includesQuickAdd: Bool = true) -> some View {
        contentMargins(
            .bottom,
            includesQuickAdd ? VowbaseControlMetric.quickAddClearance : VowbaseSpace.large,
            for: .scrollContent
        )
    }
}
```

Then:

- `VenuesView`: delete `.padding(.bottom, 96)`, add `.vowbaseScrollClearance()`.
- `VenueDetailView`: add `.vowbaseScrollClearance(includesQuickAdd: false)`.
- `GuestsView` and the map shortlist: same treatment, since they have the identical
  double-inset/FAB-overlap pair.

`contentMargins(_:for: .scrollContent)` rather than padding, because it insets the content
without pushing the scroll indicators off the track — padding leaves the scrollbar
floating 96 pt short of the bottom, which is the visual tell that something is wrong today.

### 8.3 Also fix while in here

- Add `.refreshable { await store.load() }` to Venues and Guests. The MVP spec calls for
  pull-to-refresh on both; neither has it.
- The venue detail's `navigationTitle("Venue")` should be the venue's name — the current
  static title wastes the one piece of orientation a pushed screen gets.

---

## 9. Compare venues

Today `VenueComparisonSheet` is a `List` that stacks venues vertically with three facts
each. You cannot see two venues' capacity at the same time, which is the entire job.

### 9.1 Entry

Keep the `Shortlist / Compare` segmented control. In Compare mode:

- Cards get a rose selection ring and a filled checkmark (as today).
- A **floating bar** replaces today's inline button: pinned above the tab bar, reading
  `2 selected` with `Clear` and a primary `Compare` button. It appears on first selection
  and slides away on clear. This keeps the action reachable without scrolling back up.
- The cap stays at 3. Attempting a 4th shows a soft haptic *and* a one-line caption in the
  floating bar (`Compare up to 3 venues`) — the haptic alone, as today, is invisible to
  anyone who can't feel it.

### 9.2 The comparison view

Full-screen cover, not a sheet — this is a destination, not an adjustment.

**Layout: pinned attribute column + horizontally scrolling venue columns.**

```
┌──────────┬─────────────────┬─────────────────┐
│          │  [photo]        │  [photo]        │  ← sticky header, 16:9 thumb
│          │  Riverside      │  Harbor Gallery │     name + status capsule
│          │  ( Toured )     │  ( Shortlisted )│
├──────────┼─────────────────┼─────────────────┤
│ Location │ Example City    │ Harbor District │
│ Capacity │ 150–350      ●  │ 80–200          │  ● = best in row
│ Venue est│ $53.7K          │ $41.2K       ●  │
│ All-in   │ Not added       │ $68.0K          │
│ Travel   │ 1 hr 19 min     │ 48 min       ●  │
│ Dates    │ Not added       │ Jun–Sep 2027    │
│ Docs     │ 3               │ 1               │
│ Notes    │ Loved the light │ Parking is …    │
└──────────┴─────────────────┴─────────────────┘
   96 pt        flexible, snaps per column
```

- The attribute column is pinned left at 96 pt. Venue columns scroll horizontally with
  paging snap, so a column is never half-visible. Two venues fit on an iPhone 16 Pro at
  standard Dynamic Type; three always require a scroll, which is fine and expected.
- **Row height is uniform across columns** — the tallest cell sets it. This is what makes
  the grid scannable and is precisely what the current stacked list can't do.
- **`●` marks best-in-row** for the three attributes where "better" is unambiguous: lowest
  venue estimate, largest capacity ceiling, shortest guest travel. Nothing else gets a
  marker — we are not scoring subjective attributes. A footnote explains the dot.
- **`Differences only` toggle** in the nav bar hides rows where all venues match. On a
  3-venue compare this typically halves the grid.
- Tapping any cell pushes that venue's detail, scrolled to the corresponding section.
- Nav bar: `Done`, the toggle, and `•••` → `Share comparison` (renders the grid as a PNG —
  couples send these to parents).

### 9.3 Falling back at large Dynamic Type

Above `.accessibilityMedium`, the grid stops being readable at any column width. At that
threshold, switch to **attribute-major stacking**: one card per attribute, with all venues
listed inside it in consistent order. This preserves the comparison (you still see all
venues' capacity together) where the current design's venue-major stacking does not. The
MVP spec anticipated exactly this fallback; this is the concrete trigger for it.

---

## 10. Data-layer work this design requires

These are the blockers. Everything above is UI except the following.

### 10.1 `VenuePatch` cannot clear fields, and lacks `ourNotes` — decided

`VenuePatch`'s optional properties encode via synthesized `encodeIfPresent`, so `nil` means
"don't touch" — there is no way to express "set this column to NULL." Inline editing needs
both meanings. `GuestPatch` already solves this with `NullablePatch`; `VenuePatch` should
adopt the same type:

```swift
struct VenuePatch {
    let name: String?                        // required-ish, never nullable
    let status: VenueStatus?
    let website: NullablePatch<String>?      // .value("…") | .null | nil
    let contactName: NullablePatch<String>?
    let capacityMin: NullablePatch<Int>?
    let ourNotes: NullablePatch<String>?     // new — see §4.5
    …
}
```

Add `our_notes`, `capacity_text`, `venue_est_text`, `all_in_est_text`, and
`available_dates_text` to the patch — the detail screen displays all five and currently
cannot write any of them.

### 10.2 `MVPVenue` is lossy

It flattens `VenuePhoto` records to `[URL]`, so the UI has no photo IDs and cannot delete,
caption, reorder, or set a cover. It also collapses research fields into display strings,
so editing capacity means round-tripping `"150–350"` through a parser.

`MVPVenue` needs to carry:

- `photos: [VenuePhoto]` alongside the resolved `[URL]` (pair them, keyed by photo ID).
- `capacityMin`/`capacityMax` as `Int?`, with the formatted string derived at render time.
- `researchNotes: String?` (the `notes` column) as a distinct read-only field, for §10.2's
  From Research section, separate from `ourNotes`.

### 10.3 No upload path for venue photos

`RepositoryContainer` wires `signStoragePhoto` for **reads** from the `venue-photos` bucket,
but nothing writes to it. Add the mirror:

```swift
venuePhotoUploads = SupabaseStorageUploader(provider: supabase, bucket: "venue-photos")
```

exposing `upload(path:data:mimeType:)` — the same shape as `AttachmentStorageAdapter`, which
already exists and should be reused rather than reimplemented. Confirm the bucket's RLS
policy permits INSERT for wedding members, not just SELECT.

### 10.4 Guest travel is hardcoded

`MVPVenue.travel` is the literal string `"Unavailable"` (`ContentView.swift:2028`). The
compare view's travel row and best-in-row dot are dead until median guest travel is wired
from `MapWorkflowRepository`. Until then, the row renders `Not available` and is excluded
from the best-in-row logic — it should not silently show a dash that reads as "zero."

### 10.5 Smaller gaps

- **No empty state.** `VenuesView` renders a blank scroll view with zero venues. The MVP
  spec's `Start your venue shortlist.` state is unimplemented. `GuestsView` has a
  `ContentUnavailableView` to copy from (`ContentView.swift:949`).
- **`VenueResearchRepository` is constructed and never called.** Either the research entry
  point ships or the dependency should come out; a wired-but-dead repository will rot.
- **`AttachmentRepository` likewise** — §7 is what puts it to work.

---

## 11. Accessibility

- Every editable row exposes an `.isButton` trait and a hint of the form
  `Double tap to edit capacity`. The trailing action glyph is a **separate** element with
  its own label (`Call Riverside Pavilion`), never merged into the row.
- Notes exposes an `.accessibilityValue` of the full text and announces `Saved` via
  `.accessibilityAnnouncement` on each autosave — this is the only announcement in the
  screen, because it's the only state change the user can't see.
- The carousel is a single element with `.accessibilityAdjustableAction` to page, labeled
  `Photo 3 of 12` plus the caption when present. Individual page images are hidden from
  VoiceOver, per the MVP spec's rule on decorative venue photography.
- The comparison grid uses `.accessibilityElement(children: .contain)` per column and
  labels each cell `Capacity, Riverside Pavilion, 150 to 350` so column context survives
  linear traversal. The best-in-row dot is announced as `best value`.
- Every tap target in the carousel overlay, the manage-photos grid, and the compare header
  meets `VowbaseControlMetric.minimumTapTarget`.
- Reduce Motion: the full-screen photo transition becomes a cross-fade; carousel paging
  drops its spring; the floating compare bar appears without a slide.

---

## 12. Suggested sequencing

Ordered so each step ships something usable on its own.

| Step | Scope | Unblocks |
|---|---|---|
| **1** | §8 scroll clearance + `.refreshable` + venue-name title + §10.5 empty state | Nothing — pure fix, land it first |
| **2** | §10.1 `VenuePatch` (`NullablePatch`, `ourNotes`, text fields) and §10.2 `MVPVenue` | All editing |
| **3** | §4 inline editing for name, status, location, facts, details; retire `EditVenueSheet` | The compare view having data to compare |
| **4** | §4.4 Notes with autosave; §4.5 `our_notes` / research split | — |
| **5** | §5 carousel + full-screen viewer (read-only) | — |
| **6** | §10.3 upload path, then §6 photo upload and §5.3 manage | — |
| **7** | §7 documents (viewer first, then add) | — |
| **8** | §9 comparison view | Best after 3, so the grid has real fields |

Steps 1 and 2 are prerequisites for everything; 5–8 are independent of each other and can
be parallelized or reordered by whichever matters more to the couples testing it.
