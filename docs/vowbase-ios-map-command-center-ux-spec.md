# Vowbase iOS — Map as planning command center

Status: Proposed
Date: July 30, 2026
Companion to `vowbase-ios-mvp-ux-spec.md` and `vowbase-ios-venues-ux-spec.md`.

The MVP spec made the map the home screen and gave it two layer toggles and a shortlist
drawer. That skeleton is built (`MapWorkspaceView` in `ContentView.swift`). This document
rethinks that screen as the app's single operating surface — the place a couple opens to
know where their wedding stands — and defines the structural framework that lets vendors,
day-of events, lodging, and budget land in it later without a second redesign.

Where this document contradicts the MVP spec, this document wins. The deliberate
reversals are named in §14.

---

## 1. What is wrong with the screen today

Read against the current build, not against the mockups:

1. **The map decorates; it does not answer.** It is zoomed to the Northeast with two
   overlapping pins and one guest bubble. Nothing on screen states the one thing only a
   map can tell you: *what this venue choice costs the people you are inviting.* The
   `travel` field is literally hardcoded to `"Unavailable"` (`ContentView.swift:2028`)
   while `MapWorkflowRepository.travelTimes` sits unused.
2. **The IA duplicates itself.** The tab bar offers Map / Venues / Guests. The map offers
   Venues / Guests layer chips. Two controls, one taxonomy. Adding vendors means adding
   them in both places.
3. **The layer chips are settings, not a point of view.** Two booleans with checkmarks
   consume the most valuable strip on the screen and do not scale past four objects.
4. **The identity bar spends 80 pt telling the couple their own names.** No date, no
   countdown, no state.
5. **Everything in the shortlist card truncates.** "Celebrate at…", "1000, Richmon…",
   "Unavailable m…". Four facts crammed into 165 pt.
6. **The shortlist is a list beside a map, not a list of the map.** Selection sync exists;
   consequence does not.
7. **The FAB sits on top of the content it is meant to add to.**

The screen has the right instinct — map first — and the wrong information model.

---

## 2. The idea: one canvas, many lenses

> **The map is not a tab. It is the substrate the whole app runs on.**
> A *lens* selects what you are working on. It aims the map and fills the console.
> Everything else stays visible, dimmed, as context.

This collapses the duplicated taxonomy into one control, gives every future object type a
home with zero new navigation, and keeps geographic context continuous — you never lose
your place by switching "screens," because there is only one screen.

Three named parts, used consistently for the rest of this document:

| Part | What it is |
| --- | --- |
| **Canvas** | The map. Always present, always the background. |
| **Console** | The bottom sheet. Three detents. Always shows the active lens. |
| **Lens rail** | The bottom bar. Replaces both the tab bar and the layer chips. |

---

## 3. Principles

1. **A lens is a focus, not a filter.** Choosing Venues does not hide guests; it makes
   venues large and interactive and guests small and quiet. You always need to see the
   people when you are choosing the place.
2. **The map's job is consequence.** Every selection answers "so what?" — for a venue,
   that answer is guest travel. A map that only plots points is a worse list.
3. **One taxonomy, one control.** If a thing is a planning object, it is a lens. There is
   no second place to turn it on.
4. **The console is the app.** At full detent it is the Venues tab. At peek it is a
   caption for the map. There is no third pattern to learn.
5. **Dead ends become tasks.** "Guest travel unavailable" is not an answer; it is a row
   that routes to the 18 guests missing a location.
6. **Additive by construction.** Adding Vendors means writing one lens conformance and one
   overview module. It means editing no navigation code.
7. **Private by construction, unchanged.** Guest geography stays city-coarse. This rule
   extends to every future person-shaped layer.

---

## 4. Screen anatomy

```
┌──────────────────────────────────────────────┐
│  ⬤A&C   Andey & Calvin · 412 days      ⌕     │  Context bar — §5
├──────────────────────────────────────────────┤
│                                              │
│              ·  ·  ·                         │
│                   ◆ vendor (context, dim)    │  Canvas — §6
│         ▮ 12                                 │    focus layer: full size, tappable
│              📍 Riverside Pavilion           │    context layers: 70% size, 55% alpha
│                  ●  ← selected               │
│         ▮ 4                        ⊕ ⤢       │    map controls, ride the console
│                                        ⊕     │    lens-aware FAB, rides the console
├──────────────────────────────────────────────┤
│                    ▬▬▬                       │  Console — §7
│  Riverside Pavilion                 Toured   │    header is selection-aware
│  62% of guests within 2h · 14 fly · 1h50m ›  │    impact readout — §8
│  ┌──────────┐┌──────────┐┌──────────┐        │
│  │ card     ││ card     ││ card     │        │    peek: horizontal rail
│  └──────────┘└──────────┘└──────────┘        │
├──────────────────────────────────────────────┤
│   ◉ Overview   📍 Venues   👥 Guests         │  Lens rail — §9
└──────────────────────────────────────────────┘
```

Vertical budget on a 6.7" device, peek detent: context bar 52, canvas ≈ 430, console 210,
lens rail 82. The canvas never drops below ~35% of the screen at any detent short of full.

---

## 5. Context bar

Replaces `IdentityBar`. One row, 52 pt, floating material capsule, 16 pt insets.

```
⬤ A&C    Andey & Calvin · 412 days                              ⌕
```

- **Monogram**, 36 pt (down from 58). Tap → account sheet (sign out, settings, workspace
  switcher). Unchanged behavior, smaller footprint.
- **Title line**, one line, truncating tail. `coupleNames`, then a middot, then the
  countdown derived from `WeddingSummary.weddingDate`.
  - `> 1 year`: `Sep 18, 2027`
  - `≤ 365 days`: `412 days` → `86 days` → `12 days` → `Tomorrow` → `Today`
  - No date set: `Add your date` in rose — a tap target, not a placeholder.
- **Search glyph**, trailing, 44 pt target. Expands in place to a full-width field over
  the canvas.

### 5.1 Search is the command line

One field, results grouped by lens, keyboard-first. This is what makes the screen a
command center rather than a map with a drawer.

```
⌕ riverside                                    ✕
─────────────────────────────────────────────
VENUES
  📍 Riverside Pavilion            Toured
GUESTS
  👤 Avery Rowan          Riverside, CA
PLACES
  ⌖ Riverside Pavilion, Wilmington DE
    ＋ Add as venue
```

- Venue and guest results select the object, switch to its lens, and frame the canvas.
- **Places** come from `MapWorkflowRepository.geocode`. A place result carries an inline
  `Add as venue` action that opens Quick Add pre-filled with the resolved coordinate. This
  is the map-native creation path and it is the reason search lives here and not in a tab.
- Empty query shows the four most recently touched objects across all lenses.

---

## 6. Canvas

### 6.1 Style

- `.mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))`. Business POIs
  are pure noise against branded pins; place and road labels stay for orientation.
- A `Color(uiColor: .systemBackground).opacity(0.10)` overlay in light mode and `0.18` in
  dark sits between map and annotations to lower map saturation so brand tints read as the
  only saturated things on screen. The current build's teal water competing with a rose
  pin is the problem this solves.
- `.mapControlVisibility(.hidden)`; we supply our own — see §6.5.

### 6.2 Focus and context rendering

Every lens contributes annotations in exactly two renderings:

| | Focus (active lens) | Context (all other lenses) |
| --- | --- | --- |
| Scale | 1.0 | 0.70 |
| Opacity | 1.0 | 0.55 |
| Label | on selection | never |
| Hit testing | yes | **no** |
| VoiceOver | in tree | hidden (console is the route) |

Switching lenses animates scale and opacity over 0.22 s. It never removes anything from
the map. The "all layers off" empty state in the MVP spec is retired — there is no way to
reach it, and nothing was gained by it.

### 6.3 Marker vocabulary

Color never carries meaning alone; each lens owns a distinct silhouette.

| Lens | Silhouette | Tint |
| --- | --- | --- |
| Venues | teardrop pin | rose |
| Guests | numeric circle | guest blue |
| Vendors *(later)* | diamond | amber |
| Lodging *(later)* | rounded square, bed glyph | teal |
| Day-of events *(later)* | circle, time glyph | violet |

Selected state: 1.15× scale, white 3 pt ring, drop shadow, and a trailing label capsule
with the object's name. Only one object across all lenses can be selected at a time.

### 6.4 Camera

- Insets are computed, not guessed: top = context bar bottom + 16, bottom = current
  console height + 24. A selected object is always framed in the visible band, never
  behind the console.
- **Selecting** an object eases the camera 0.45 s to center it with those insets, keeping
  the current zoom unless the object is off-screen.
- **Switching lenses** does *not* move the camera if the user has panned manually since
  the last selection. Manual camera always wins — carried forward from the MVP spec.
- **Fit** (§6.5) frames the active lens's objects plus, for Venues, the guest clusters
  that the impact readout is measuring.

### 6.5 Map controls and the FAB

A vertical stack pinned to the trailing edge, bottom-anchored **12 pt above the console's
top edge**, riding the sheet as it moves and fading out at the full detent:

```
⊕   Fit — frame the active lens (44 pt)
⤢   Recenter on user location (44 pt, hidden without permission)
━━
⊕   Quick add — 64 pt, lens-aware (§10)
```

This fixes the current collision: nothing floats over a venue card any more, and the FAB
stays in the same thumb arc at every detent.

---

## 7. Console

Replaces `ShortlistPanel` and absorbs the body of `VenuesView` / `GuestsView`.

### 7.1 Detents

| Detent | Height | Contains |
| --- | --- | --- |
| **Peek** | 210 pt fixed | Header + impact readout + one horizontal card rail |
| **Half** | 0.5 | Header + filter/sort chips + vertical list |
| **Full** | 0.94 | Adds in-list search and section grouping; canvas dims to 0.4 |

Rules:

- Dragging between detents **never** changes selection or camera; it only re-insets the
  camera so the selected object stays visible as the sheet moves.
- Selecting a marker raises the console to peek if it was lower, and scrolls the rail to
  that card.
- Tapping a list row at half/full **drops the console to peek** and centers the map on it.
  This reciprocal move is the core interaction of the screen: the list explains the map,
  the map explains the list.
- Detent, scroll offset, and filters persist per lens for the session.

### 7.2 Header

Selection-aware, two lines, 16 pt insets.

**No selection** — the lens's state at a glance:

```
Venues                                    10 venues
3 toured · 1 negotiating · 6 to review
```

**With a selection** — the object, then its consequence:

```
Riverside Pavilion                          Toured
62% of guests within 2h · 14 fly · 1h 50m        ›
```

The second line is the impact readout (§8) when the active lens has one, and the object's
secondary line otherwise (for Guests: `Cedar Circle · Northvale · Pending`).

### 7.3 Peek — the card rail

The current rail card fails because it carries four facts in 165 pt. The redesigned card
carries **two**, and drops location entirely: the card is anchored to a pin you are
already looking at, so restating the address is redundant.

```
┌──────────────────────────────────────┐
│ ┌────────┐  Riverside                │  268 × 132
│ │        │  Pavilion                 │  image 104 wide, leading
│ │  img   │                           │  name: serif 17, 2 lines
│ │        │  ( Toured )               │  status capsule
│ └────────┘  ✈ 1h 50m median          │  ONE fact: the impact metric
└──────────────────────────────────────┘
```

- Selected card: 1.5 pt rose border. Unselected: hairline separator border.
- The rail is `ScrollView(.horizontal)` with `.scrollTargetBehavior(.viewAligned)`; paging
  the rail selects the centered card and moves the camera with it.
- At Accessibility Dynamic Type sizes the rail becomes a single full-width vertical card
  and the peek detent grows to fit it.

Each lens supplies its own card. Guests: avatar + name + RSVP capsule + group. Vendors
later: category glyph + name + status + next payment due.

### 7.4 Half and full — the list

This is the existing `VenuesView` / `GuestsView` body, moved. Same rows, same filters,
same compare mode, same navigation destinations. Nothing about venue or guest detail
changes in this document — see `vowbase-ios-venues-ux-spec.md`.

What changes: it is reached by dragging up rather than by a tab, the map stays behind it,
and the filter chips sit directly under the header instead of under a screen title. The
screen title is gone — the lens rail already says where you are.

---

## 8. The impact readout

The single most valuable thing on the screen and currently absent.

When a venue is selected, `travelTimes(weddingID:origin:destinations:)` runs with the
venue as origin and each city-coarse guest cluster as a destination. The result renders
as the console's second header line and as a badge on each cluster on the canvas.

```
62% of guests within 2h · 14 fly · 1h 50m median            ›
```

- **Within 2h** — share of guests, not clusters, weighted by cluster count.
- **Fly** — count of guests whose cluster resolved with `travelMode == .flight`.
- **Median** — median guest travel, matching the `travel` field the venue card promises.
- If any contributing `TravelTime.estimated == true`, append a muted `Estimated` badge.
  The MVP spec's rule holds: never fabricate a number without labeling it.
- Tapping the row switches to the **Guests** lens with the same venue still selected and
  every cluster badged with its duration — the "who does this hurt" view.

### 8.1 When it cannot be computed

Never show "Unavailable" as a terminal state. Show the reason and the fix:

| Condition | Row | Tap |
| --- | --- | --- |
| Venue has no coordinate | `Add this venue's location to see guest travel` | Opens venue location edit |
| No guest has a coordinate | `No guest locations yet — add some to see travel` | Guests lens, add flow |
| Some guests unlocated | `62% within 2h · 18 guests not counted` | Guests lens, filtered to unlocated |
| Request failed | `Guest travel unavailable · Retry` | Re-requests |

Cluster badges show on the canvas only when the readout is showing a real number.

---

## 9. Lens rail

Replaces `VowbaseTabBar` **and** `LayerChip`. Keeps the existing glass capsule treatment,
sizing, and haptics — the visual work already done carries over unchanged.

```
┌────────────────────────────────────────────┐
│   ◉         📍          👥                 │
│ Overview  Venues     Guests                │
└────────────────────────────────────────────┘
```

- Active slot: filled glyph, white label, `.white.opacity(0.16)` capsule — as built today.
- Selection is conveyed by capsule, glyph fill, and `.isSelected` trait, never by color
  alone.
- **Overflow rule:** at most five slots. `Overview` is always leading. When more than five
  lenses exist, the fifth slot becomes `More`, opening a grid sheet of the remainder; the
  chosen lens takes the fourth slot for the session. No horizontal scrolling — a rail that
  scrolls is a rail whose targets move.
- Switching lenses: 0.22 s crossfade on markers, console keeps its detent, camera holds.

---

## 10. Quick add

The FAB is lens-aware, which is what keeps it one tap forever.

- **Tap** → the active lens's create sheet directly. On Venues, tap = Add venue. On
  Guests, tap = Add guest. On Overview, tap = the current expanded panel.
- **Long press** → the full panel of every lens's create action, as `QuickAddPanel` does
  today.
- The FAB's glyph carries the lens tint ring so the primary action is legible before you
  press it.
- Creating from the canvas: long-pressing empty map opens `Add venue here` with the
  coordinate pre-filled and reverse-geocoded. Same path as a Places search result.

`QuickAddPanel` needs no structural change — it becomes a list driven by the lens registry
rather than two hardcoded rows.

---

## 11. Overview lens — the command center proper

Overview is what earns the phrase "one-stop shop." Canvas: every layer at equal weight,
camera fit to everything, nothing selected. Console: a vertical stack of **modules**.

```
┌────────────────────────────────────────┐
│                 ▬▬▬                    │
│  Sep 18, 2027                412 days  │
├────────────────────────────────────────┤
│  NEEDS YOU                             │
│  ● Pick a venue — 3 toured, none held  │
│  ● 18 guests have no location          │
│  ○ 24 RSVPs outstanding                │
├────────────────────────────────────────┤
│  REACH                                 │
│  Riverside Pavilion                    │
│  62% within 2h · 14 fly                │
├────────────────────────────────────────┤
│  GUESTS                                │
│  86 invited · 41 accepted · 24 pending │
└────────────────────────────────────────┘
```

### 11.1 The module contract

This is the extension point. A module declares:

| Field | Meaning |
| --- | --- |
| `id` | Stable, for ordering and dismissal |
| `title` | Section eyebrow |
| `urgency` | `.blocking` / `.soon` / `.ambient` — drives sort order and dot color |
| `size` | `.compact` 88 pt / `.standard` 132 pt / `.tall` 200 pt |
| `destination` | Lens, plus an optional object to select on arrival |
| `emptyState` | What renders before the domain has data |

Modules sort by urgency, then by a fixed per-domain order. A module with no data renders
its empty state once and then hides for the session.

### 11.2 MVP modules

All four are derivable from data already loaded — no backend work.

| Module | Source | Blocking when |
| --- | --- | --- |
| **Countdown** | `wedding.weddingDate` | Date unset |
| **Needs you** | Derived rules, §11.3 | Any blocking rule fires |
| **Reach** | `travelTimes` for the leading venue | — |
| **Guests** | RSVP tallies | — |

### 11.3 "Needs you" rules

Ordered; the first three that fire are shown.

1. `venues.isEmpty` → *Add your first venue*
2. `toured ≥ 2 && booked == 0` → *Pick a venue — N toured, none held* → Venues, compare
3. `guests.withoutCoordinate > 0` → *N guests have no location* → Guests, filtered
4. `daysUntilWedding ≤ 120 && rsvpPending > 0` → *N RSVPs outstanding* → Guests, filtered
5. `booked == 1` → collapses the module to one confirmation row and demotes it to
   `.ambient`

Later domains append rules — vendor payment due inside 14 days, an event without a
location, a lodging block under-filled — without touching the module's rendering.

---

## 12. States

| State | Canvas | Console |
| --- | --- | --- |
| Loading | Map renders; markers fade in as data lands | Header shows skeleton rows; no spinner over the map |
| No workspace | Map at world zoom, no markers | Full-detent explainer + "Create a wedding" |
| Lens empty | No focus markers; context layers remain | Empty card with the lens's create action |
| Offline | Cached tiles; markers still render from cached data | Muted banner in the header; impact readout shows `Retry` |
| Error | Unchanged | Inline in the header, not a full-screen takeover |

The current build's centered `ProgressView("Loading your wedding")` over the whole screen
goes away. The map is instantly useful; the data can arrive underneath it.

---

## 13. Accessibility

- **Focus-layer markers only** are in the accessibility tree, labeled
  `"{name}, {status}, {selected}"`. Context-layer markers are `accessibilityHidden`.
- **The console is the complete non-visual route.** Every object reachable on the canvas
  is reachable in the console list at half or full detent. This is a hard requirement, not
  a nicety — carried forward from the MVP spec.
- **Guest clusters** expose city and count. Never names, never addresses.
- **Dynamic Type** to AX5: the rail becomes single-column, the peek detent grows, the
  context bar wraps to two lines and grows to 72 pt, the lens rail keeps glyphs and
  truncates labels rather than shrinking targets.
- **Reduce Motion:** no camera animation (jump cut with insets applied), marker transitions
  crossfade with no scale, detent changes use the system's reduced animation.
- **Reduce Transparency:** materials fall back to `VowbaseDesign.surface` with a hairline
  border. The lens rail must remain legible over a photographic map — it already gets a
  0.54 black tint under `glassEffect`; the fallback needs the same contrast floor.
- **Increased Contrast:** context-layer opacity floors at 0.75, marker borders go to 2 pt.
- Targets never below 44 pt. The 36 pt monogram sits in a 44 pt tap region.

---

## 14. Privacy

Unchanged from the MVP spec and extended:

- Guest positions come only from `originPrecision == "city"` (`ContentView.swift:1729`).
  No household pins, ever.
- The impact readout is computed against **clusters**, never individuals, and reports
  aggregates only.
- Any future person-shaped layer (wedding party, lodging occupancy) inherits the same
  city-coarse rule before it may render on the canvas.

---

## 15. What this replaces

| Today | Becomes | Why |
| --- | --- | --- |
| `AppTab` (Map/Venues/Guests) | `PlanLens` (Overview/Venues/Guests/…) | One taxonomy, extensible |
| `VowbaseTabBar` | Lens rail | Same component, new source of truth |
| `LayerChip` × 2 | *Deleted* | The rail already does this |
| `IdentityBar` | Context bar | 80 pt of names → 52 pt of names, date, and search |
| `ShortlistPanel` | Console, peek detent | Gains detents and selection-aware header |
| `VenuesView` / `GuestsView` bodies | Console, half/full detent | Same lists, no separate screen |
| `MapVenueCard` (4 facts, truncating) | Rail card (2 facts) | Location is redundant beside a pin |
| `travel = "Unavailable"` | Impact readout | Wires up `travelTimes`, already in the API |
| Bottom-right floating FAB | FAB riding the console's top edge | Stops overlapping cards |

Deliberate reversals of the MVP spec:

1. **"Exactly three top-level destinations."** Now: exactly one surface, N lenses.
2. **"An all-off layer state is allowed."** Now: unreachable, and no loss.
3. **"The FAB sits inside the bottom-right of the Shortlist surface."** Now: above it.

---

## 16. Build order

A precondition first: `ContentView.swift` is 2,108 lines with every type `private` in one
file. None of this is testable or reviewable in place. Split before building.

**Phase 0 — Split.** `AppShell/`, `Features/Map/`, `Features/Venues/Views/`,
`Features/Guests/Views/`, `DesignSystem/Components/`. Move `VowbaseWorkspaceStore` to
`AppShell/WorkspaceStore.swift` and make it internal. Behavior-neutral; existing tests
must pass untouched.

**Phase 1 — Lens model.** `PlanLens` enum + registry. Replace `AppTab` and delete
`LayerChip`. The rail renders from the registry. Venues and Guests conform. The screen
looks nearly identical; the structure is now additive. *This is the skeleton the rest
hangs on — ship it alone if nothing else ships.*

**Phase 2 — Console.** Three detents, selection-aware header, redesigned rail card,
list bodies moved in, camera insets wired to sheet height. FAB relocated.

**Phase 3 — Context bar.** Countdown from `weddingDate`, monogram down to 36 pt, search
glyph (field can land inert and gain results in 3b).

**Phase 4 — Impact readout.** Wire `travelTimes`, cluster badges, the four unavailable
states, and replace the hardcoded `travel` string. Highest user-visible payoff; depends
on nothing above except the console header.

**Phase 5 — Overview lens.** Module contract, the four MVP modules, the "Needs you"
rules.

**Phase 6+ — New domains.** Each is: one `PlanLens` conformance, one rail card, one list
row, one create sheet, one overview module. Vendors first (`VendorRepository` exists),
then day-of events (`ScheduleRepository` exists), then lodging.

---

## 17. Deliberately out of scope

- Venue and guest **detail** screens — owned by `vowbase-ios-venues-ux-spec.md`.
- Isochrone shading / drive-time polygons. Expensive, and cluster badges deliver most of
  the insight. Revisit after Phase 4 ships and we can see whether people ask for it.
- Multi-select and on-map comparison. Compare stays in the console list.
- Collaborator presence on the canvas. Real, but not before two lenses are stable.
- Offline tile pre-caching for the venue-tour trip. Good idea; not MVP.

---

## 18. Open questions

1. **Does Overview earn the leading slot, or is it the wrong default landing?** My read:
   land on Overview when a blocking rule fires, otherwise land on the last-used lens.
   Worth a decision before Phase 5.
2. **Travel request cost.** `travelTimes` per venue selection across N clusters could be
   chatty. Needs a per-venue cache keyed on `(venueID, clusterSignature)`; the API already
   reports `.cache` as a source, so confirm the server caches before we build a client one.
3. **Budget as a lens with no canvas presence.** The lens model must allow a console-only
   lens. Cheap to allow now, awkward to retrofit — decide in Phase 1.
