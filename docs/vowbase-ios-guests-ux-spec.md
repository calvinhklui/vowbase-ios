# Vowbase iOS Guests Tab UX Specification

Status: Proposed
Date: July 30, 2026
Platform: Native SwiftUI, iOS 18+
Supersedes: the Guests sections of `vowbase-ios-mvp-ux-spec.md`, and lifts three of its explicit MVP exclusions (custom-column administration, richer guest editing, bulk-adjacent filtering)

## Why this exists

The MVP shipped Guests as a read-mostly list. Four capabilities were deferred and are now the tab's binding constraints:

1. Guest Detail shows three of eleven-plus fields and cannot edit any of them in place.
2. Add Guest captures four fields; email, phone, and every custom field are unreachable at creation.
3. `GuestCustomColumn` CRUD exists end to end in the repository layer and has no UI at all. The list view instead hard-codes a lookup for a `group` key that no screen can create.
4. Filtering is one single-select RSVP dimension plus one boolean toggle. There is no way to combine conditions, filter on a custom field, or sort.

The through-line: **a guest list is maintained, not authored.** A couple touches the same record dozens of times across a year — correcting a surname, chasing an RSVP, marking a meal choice. The design goal is to make the twentieth small correction cost almost nothing.

## Principles specific to this tab

- **The record is the editor.** There is no separate view mode and edit mode for a guest. Retiring `EditGuestSheet` is an explicit goal, not a side effect.
- **Every field is equal in mechanism, not in prominence.** A custom `select` column edits with the same gesture as the built-in RSVP field. Hierarchy comes from ordering and grouping, never from which fields happen to be editable.
- **Structured filters, not a query builder.** Conditions AND across fields and OR within a field. This covers the real questions ("pending guests in Cedar Circle who have an email") without shipping a boolean expression editor onto a phone.
- **Never a dead end.** The filter sheet always shows the live result count before it is applied. Empty results are reachable but never a surprise.
- **Schema changes are consequential and are treated as such.** Deleting a column destroys data across the whole guest list. Every such action names the field and states the blast radius in guests affected.
- **Coarse geography stays coarse.** Nothing in this document changes the privacy contract. Exact address remains detail-only; the map continues to receive city-precision origins only.

## Field taxonomy

Everything the UI must account for, and where each field surfaces.

| Field | Kind | Detail | Add | Filter | Notes |
| --- | --- | --- | --- | --- | --- |
| `firstName` | text, required | inline | essentials | search | Cannot be emptied |
| `lastName` | text | inline | essentials | search | |
| `rsvpStatus` | enum | inline menu | essentials | multi-select | Defaults `notInvited` |
| `rsvpDate` | date | read-only | — | — | Server-set on status transition |
| `email` | text | inline | more details | has/hasn't, search | Keyboard `.emailAddress` |
| `phone` | text | inline | more details | has/hasn't, search | Keyboard `.phonePad` |
| `address` | text | inline + geocode | essentials | has/hasn't | Private; detail-only |
| `originLabel` | derived | read-only chip | — | multi-select | Coarse city, map-safe |
| `originPrecision` | derived | precision chip | — | mappable toggle | Only `city` reaches the map |
| `geocodeStatus` | derived | inline status | — | — | Drives the "Locating…" affordance |
| `customFields[key]` | per column kind | inline | more details | per kind | Rendered from column definitions |
| `createdAt` | date | footer metadata | — | sort | |

Derived location fields are never directly editable. They are outputs of committing `address`, and the UI must say so rather than presenting them as blanks the user failed to fill.

### Custom field kinds

`GuestCustomColumnKind` is already `text | number | select | checkbox`. Each kind gets one editing control and one filter control, and they are the only four that exist:

| Kind | Detail control | Add control | Filter control |
| --- | --- | --- | --- |
| `text` | inline text field | text field | Any / Contains… / Is empty / Is not empty |
| `number` | inline decimal field | decimal field | Any / range min–max / Is empty |
| `select` | menu of `options` + Clear | menu | multi-select of options + Empty |
| `checkbox` | toggle | toggle | Any / Checked / Unchecked |

A value whose stored JSON does not match its column's declared kind renders read-only with a quiet "Unsupported value" and an option to clear it. This will happen — the web app and imports write the same column — and it must never crash a row or block the rest of the screen.

## Guest Detail: inline editing with autosave

### Layout

A `List` in `.insetGrouped`, sections top to bottom:

1. **Header** — 76 pt initials avatar, full name, RSVP capsule. Name is editable here, not in a separate field row: tapping it reveals two side-by-side text fields for first and last.
2. **RSVP** — status row (menu), and `rsvpDate` as read-only metadata when present.
3. **Contact** — email, phone. Each row carries a trailing quick action (mail, call) when populated.
4. **Location** — address field, then a derived read-only row showing the coarse origin label, a precision chip, and `View on map` when precision is `city`.
5. **Custom fields** — one row per non-hidden column in `position` order. Section footer: `Add a field`, routing to the field editor with a return path back to this guest.
6. **Metadata** — added date. Overflow menu retains Delete.

Section 5 is omitted entirely when no columns are defined, replaced by a single quiet `Add a field` row. An empty section header reading "Custom fields" above nothing is worse than no section.

### Row anatomy and edit affordance

Each editable row is a label/value pair where the value is a live control styled to read as static text until focused. There is no mode switch, no pencil icon, and no edit button.

- Label: `VowbaseTheme.mutedInk`, fixed leading column at standard sizes.
- Value: `VowbaseTheme.ink` when populated; `Not added` in muted ink when empty. `Not added` is placeholder text, not a stored value.
- Tap target spans the full row and is at minimum 44 pt.
- Focus draws a hairline focus ring in `VowbaseTheme.rose` and reveals a Clear control for optional populated fields.
- At accessibility Dynamic Type sizes, the label/value pair reflows from horizontal to vertical. Values never truncate to preserve the label column.

### Commit model

Commit on **focus loss, return key, or control selection** — never per keystroke.

- Menu and toggle controls commit immediately on selection.
- Text and number fields commit on blur or return.
- Committing a value identical to the stored one is a no-op with no network call and no state flash.

### Per-row save state

Save state is per row, never global. A single failed email write must not imply the RSVP change failed.

| State | Treatment |
| --- | --- |
| Idle | No indicator |
| Saving | Trailing 12 pt indeterminate spinner; row stays interactive |
| Saved | Trailing checkmark for 1.2 s, then fades. Suppressed under Reduce Motion in favor of an immediate, non-animated dismissal |
| Failed | Row tinted with a warning hairline, inline message, and a `Retry` button. **The user's typed value stays in the field.** |

On success, the row adopts the server-confirmed value from the returned `Guest`, which may differ from what was typed — trimmed whitespace, a normalized address. On failure nothing is reverted and nothing is discarded; the pending value persists until retried, edited again, or the screen is left. Leaving with unsaved failures raises a confirmation naming the affected fields.

This maps to `GuestPatch` cleanly: one row commit produces one patch with exactly one field set, and clearing an optional field sends `.null` rather than `.value("")`.

### Field-specific behavior

**First name** — cannot be committed empty. On blur with empty content, restore the previous value and show a transient inline message. Save is not attempted.

**Address** — the only field with a two-stage commit. On commit, the address string is saved immediately and the row shows `Locating…` in the derived location row beneath. Geocoding resolves to a coarse label, or fails silently into `Location not mapped` with a `Try again` affordance. **Geocode failure never blocks or reverts the address write.** Clearing the address clears all derived origin fields in the same patch.

**RSVP** — a menu, not a segmented control: five values do not fit legibly, and the current value should be visible without scanning. Changing to `accepted` or `declined` surfaces the server-set `rsvpDate` in the row beneath.

**Select custom field** — the menu lists the column's `options` plus a `Clear` item when a value is set. If the stored value is not in `options` (renamed upstream), it appears as a checked, italicized extra item labeled with a "no longer an option" hint, so the user can see what is there before replacing it.

### Undo

Changing RSVP or clearing any populated field posts a toast with `Undo` for 5 seconds. Undo issues the inverse patch. Undo is not offered for ordinary text edits, where the field itself is the undo mechanism.

### Accessibility

- In read state each row is one VoiceOver element: "Email, avery@example.com. Text field. Double tap to edit."
- Empty rows announce "Email, not added."
- Save states are `accessibilityValue` updates; failures post an `.announcement` since they are off-screen for a focused user mid-list.
- Custom actions per row: `Clear Email`, and `Copy Email` where the value is contact data.
- The derived location row is a single element reading label, precision, and map availability — never a bare coordinate.

## Add Guest: progressive disclosure to full coverage

The one-tap creation path must not regress. A user adding forty guests from a paper list cares about exactly first name, last name, and RSVP.

### Structure

A sheet with `.medium` and `.large` detents, opening at `.medium`, focused on First name.

**Essentials** (visible at `.medium`, unchanged from today):
- First name (required)
- Last name
- RSVP (defaults Not invited)
- Address

**More details** — a disclosure row at the bottom of the essentials section reading `More details`. Expanding it grows the sheet to `.large` in place. It does **not** navigate, because a user who expands it to set one custom field must still see the name they typed.

Revealed:
- Email, Phone
- Custom fields, one control per non-hidden column in `position` order, using the Add controls from the taxonomy table
- Section footer `Add a field` when the wedding has no columns yet, so the very first custom field can be born here

State of the disclosure persists for the session. A user who adds one guest with a meal choice is adding forty.

### Save

- `Save guest` is enabled on a non-empty trimmed first name, and stays enabled regardless of geocode progress.
- In-flight saves disable the button and show inline progress. Duplicate submission is impossible.
- Failure keeps the sheet open with every entered value intact and offers Retry. This is the failure the current implementation handles worst, and it is the one most likely to occur — a couple entering guests on hotel Wi-Fi.
- Success posts a light haptic and a toast offering `Add another` and `Open guest`. `Add another` resets the fields but preserves RSVP, the disclosure state, and any custom-field value the user just set, since consecutive entries cluster.

Creation remains an atomic commit with an explicit Save. Inline autosave is correct for a record that exists and wrong for one that does not.

## Manage custom fields

### Entry points

- Primary: Guests header overflow menu → `Manage fields`. A pushed screen, not a sheet — reordering and multi-row editing want full height and a stable back path.
- Secondary: `Add a field` from the Guest Detail custom fields footer and from Add Guest, both returning to the originating context after creation.

Placing the primary entry in the Guests header, rather than app settings, is deliberate: fields are a property of the guest list, and the need is discovered while looking at guests.

### Field list

Rows in `position` order, each showing:
- Kind icon (text `textformat`, number `number`, select `list.bullet`, checkbox `checkmark.square`)
- Label, with the generated `key` as muted subtext
- Usage: `Used by 34 guests`, computed locally from loaded records
- Hidden fields render at reduced opacity with a `Hidden` capsule, sorted in place rather than banished to a separate section

Interactions:
- Drag to reorder, writing `position` on drop. Order here is the order everywhere: detail, add, and filters all read it.
- Swipe leading: Hide / Show
- Swipe trailing: Delete (destructive, confirmed)
- Tap: field editor

Empty state: `No custom fields yet.` with supporting text naming realistic examples — Group, Meal choice, Plus one, Table — and a primary `Add a field`.

### Field editor

Create and edit share one form.

- **Label** — free text, required.
- **Key** — auto-derived on create by slugifying the label, suffixed on collision. Shown read-only with an explanation that it is shared with the web workspace. **Immutable after creation**; renaming a key orphans every stored value. The label is fully renameable and is what the UI displays everywhere.
- **Kind** — picker. Changing the kind of a field that holds data requires confirmation stating the coercion:
  - text → number: non-numeric values are cleared
  - number → text: values preserved as strings
  - anything → select: existing distinct values are offered as the initial option list, pre-checked
  - anything → checkbox: non-empty becomes checked
  The dialog states how many guests are affected before proceeding.
- **Options** (select only) — add, rename, reorder, delete. Each option shows its usage count. Renaming an in-use option asks whether to rewrite existing guest values or add a new option and leave them alone. Deleting an in-use option warns and clears those values.
- **Hidden** — toggle, with a footer clarifying that hidden fields retain their data and remain visible to the web workspace.

Soft guidance past twelve visible fields: a non-blocking note that long field lists make guest rows harder to scan, suggesting Hidden for seasonal fields. Advisory only, never enforced.

### Deletion

Deleting a field with stored values shows a confirmation naming the field and the count: `Delete "Meal choice"? This permanently removes the value stored for 61 guests.` Confirmation requires the destructive button, not a swipe alone. Deleting an unused field confirms with a single lighter prompt.

## Filtering, sorting, and the display resolver

### Quick chips stay

The horizontal RSVP chip row is the fast path and is unchanged in placement, with two corrections:

- Chips become **multi-select**. Tapping Pending then Accepted shows both. `All` clears the RSVP dimension.
- `Declined` appears when its count is non-zero or when it is active, per the original spec — currently it never renders at all.

### Filters sheet

A structured builder at `.large`, with a fixed footer. Sections in order:

1. **RSVP** — multi-select rows with counts.
2. **Location** — multi-select of distinct coarse origin labels with counts, plus a `No location` bucket and an `Only mappable guests` toggle, which is the current `onlyLocated` behavior given a precise name.
3. **Details** — has email, has phone, has address. Three-state where useful: Any / Has / Doesn't have.
4. **Custom fields** — one disclosure row per non-hidden column, showing the field label and its current condition summary as trailing text (`Any`, `Vegetarian, Vegan`, `2–4`). Disclosing reveals the kind-appropriate control from the taxonomy table.

Above section 1, a persistent explanatory line: **Guests match all of the conditions below.** This single sentence is what lets the sheet omit an AND/OR control entirely.

### The footer is the most important element

A pinned footer showing a live count that recomputes on every toggle:

- `Show 23 guests` — primary rose button, dismisses and applies
- `Clear all` — secondary, enabled only when conditions exist
- When the count reaches zero, the button becomes a disabled `No guests match` and the most recently added condition is marked with a quiet hint, so the dead end is diagnosable rather than mysterious

Filtering is local over already-loaded records, consistent with search. No round trip, so the count is free.

### Active filter tokens

Below the chip row, when any non-RSVP condition is active, a horizontally scrolling row of removable tokens: `Cedar Circle ×`, `Has email ×`, `Meal: Vegetarian ×`, terminated by `Clear all`. The Filters button carries a numeric badge of active conditions.

This row is what makes a filtered list honest. Today a user who leaves `onlyLocated` on sees an incomplete list with no visible reason.

### Sorting

Currently absent. A sort control sits beside Filters:

- Name A–Z (default), Name Z–A
- Recently added
- RSVP status, grouped in lifecycle order
- Any `select` or `number` custom field

Sort is independent of filters and persists per session alongside them.

### Display resolver

The list row's group line currently comes from a hard-coded `customFields.stringValue(for: "group")` with a `group_name` fallback. Replace it with the resolver the MVP spec asked for and never got:

- The wedding designates one column as the row subtitle field. Default: the first `select` column by position, else the first `text` column, else none.
- The resolver reads column definitions, not literal keys, so a wedding whose grouping column is named `side` or `table` works without a code change.
- Absent value renders as nothing rather than `No group`. A literal "No group" on every row in a wedding that never defined groups is noise presented as data.

## States

| State | Treatment |
| --- | --- |
| First load | Shape-matched skeleton rows, not a spinner |
| Refresh | Pull to refresh; loaded content stays visible throughout |
| Empty list | `Start your guest list.` with Add guest primary and Import mention deferred |
| Filtered empty | Names the active conditions and offers `Clear filters`, distinct from the empty list |
| Search empty | `No guests match "kowalski"` with the query quoted |
| Partial data | Guests render; a quiet banner notes custom fields failed to load, and custom rows are suppressed rather than shown broken |
| Load error | Retry banner; navigation and any loaded guests preserved |
| Field admin unavailable | If column CRUD 403s, the Manage fields entry stays visible but explains the permission rather than vanishing |

## Data mapping

| UI concept | Source |
| --- | --- |
| Guest records | `GuestRepository.guests(weddingID:)` |
| Inline row commit | `GuestRepository.updateGuest(id:patch:)` with a single-field `GuestPatch` |
| Clearing an optional field | `NullablePatch.null` |
| Custom field write | `GuestPatch.customFields` with the full merged object |
| Column definitions | `GuestRepository.customColumns(weddingID:)` |
| Column CRUD | `createCustomColumn` / `updateCustomColumn` / `deleteCustomColumn` |
| Reordering | `GuestCustomColumnPatch.position` |
| Address geocoding | `MapWorkflowRepository.geocode` |
| Map origin | `originLabel` / `originLatitude` / `originLongitude` / `originPrecision` |

Two gaps in the current layer worth naming:

- **`customFields` is patched wholesale.** `GuestPatch.customFields` takes a complete `JSONValue`, so a single custom-field row commit must read-modify-write the entire object. With per-row autosave, two rapid edits to different custom fields can lose the earlier one. Serialize custom-field commits per guest, and merge against the latest server-confirmed object rather than the value captured at row-focus time.
- **Column definitions are never loaded.** `VowbaseWorkspaceStore.load()` fetches venues and guests only. Add a third concurrent fetch, and tolerate its failure independently — a column fetch failure must degrade custom fields, not the guest list.

The per-event `RSVP` model and `upsertRSVP` remain unused by any screen. Out of scope here, but it is the natural home for meal choice once multi-event weddings are supported, and meal choice should not be quietly cemented as a custom column in the meantime.

## Deliberately out of scope

- Multi-select and bulk edit. Real need, but it wants its own selection mode and conflicts with inline autosave semantics.
- CSV import. Still web-first.
- Saved filter views as named chips. Designed for after the structured builder proves out.
- Per-event RSVP UI.
- Free-form boolean query building.

## Acceptance criteria

**Maintain a record.** Open a guest, change RSVP, correct a surname, set a custom select value, and clear a phone number — with no sheet, no Save button, and one network write per change. A failure on any one of those leaves the other three saved and the failed value still on screen.

**Create completely.** Add a guest with an email and two custom field values in one sheet without navigating away, and land on that guest's detail with every value present.

**Own the schema.** Create a select field with three options, reorder it above an existing field, see that order reflected in guest detail, add guest, and the filter sheet, then delete it with a confirmation that states how many guests lose data.

**Ask a real question.** Filter to pending guests in two named cities who have an email address, see the count before applying, see all three conditions as removable tokens afterward, and clear them in one tap.
