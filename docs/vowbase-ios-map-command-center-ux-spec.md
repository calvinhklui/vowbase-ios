# Vowbase iOS — Map as planning command center

Status: Proposed
Date: July 30, 2026
Revised: July 30, 2026 — see §0
Companion to `vowbase-ios-mvp-ux-spec.md`, `vowbase-ios-venues-ux-spec.md`,
`vowbase-ios-guests-ux-spec.md`, and `vowbase-ios-tasks-implementation-plan.md`.

The MVP spec made the map the home screen and gave it two layer toggles and a shortlist
drawer. That skeleton is built (`MapWorkspaceView` in `ContentView.swift`). This document
rethinks that screen as the app's single operating surface — the place a couple opens to
know where their wedding stands — and defines the structural framework that lets vendors,
day-of events, lodging, and budget land in it later without a second redesign.

Where this document contradicts the MVP spec, this document wins. The deliberate
reversals are named in §15.

---

## 0. Revision — what shipped while this was in draft

Between the first draft and now, three things landed on `main` that this document was
written without. None of them invalidate the proposal; two of them strengthen it and one
forces a decision that was parked as an open question.

| What shipped | Where | Effect here |
| --- | --- | --- |
| **Tasks tab** — a fourth tab, no map presence | `Features/Tasks/`, `AppTab.tasks` | Proves the canvas-optional lens. Closes open question 3. Forces a reckoning with the Overview "Needs you" module — §11.3 |
| **Guests rewrite** — inline detail editing, filter tokens, custom fields, display resolver | `Features/Guests/`, `docs/vowbase-ios-guests-ux-spec.md` | The console's guest rows must consume the display resolver, not `customFields["group"]` — §7.4 |
| **Venues inline editing** — in flight on `feat/venues-scroll-clearance` | `docs/vowbase-ios-venues-ux-spec.md` §8, §10 | Introduces `vowbaseScrollClearance`, which the console must adopt rather than invent — §7.5. Its §8 FAB-overlap fix and this document's §6.5 FAB move are the same bug; coordinate them |

Four consequences, each folded into the relevant section below:

1. **Four tabs, not three.** The lens rail's five-slot budget is now nearly spent before
   any new domain arrives. §9 restated with real numbers.
2. **Tasks is a real domain that owns "what's next."** The Overview module can no longer
   invent its own nudge list in isolation. §11.3 rewritten.
3. **Roles exist.** `VowbaseWorkspaceStore.canManageTasks` derives write permission from
   `WeddingMembership.role`. Nothing in this document acknowledged read-only roles. §10.1
   is new.
4. **`ContentView.swift` is now 4,140 lines**, up from 2,108. Phase 0 costs more and
   matters more — but the split precedent is set, because Tasks shipped entirely outside
   it. §16 revised.

---

## 1. What is wrong with the screen today

Read against the current build, not against the mockups:

1. **The map decorates; it does not answer.** It is zoomed to the Northeast with two
   overlapping pins and one guest bubble. Nothing on screen states the one thing only a
   map can tell you: *what this venue choice costs the people you are inviting.* The
   `travel` field is literally hardcoded to `"Unavailable"` (`ContentView.swift:4026`)
   while `MapWorkflowRepository.travelTimes` sits unused.
2. **The IA duplicates itself.** The tab bar offers Map / Venues / Guests / Tasks. The map
   offers Venues / Guests layer chips. Two controls, one taxonomy. Adding vendors means
   adding them in both places — and Tasks has already had to pick a side, appearing in the
   bar but not on the map, with nothing in the design saying why.
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

### 2.1 Canvas-optional lenses

Not every planning object has a place. Tasks shipped with no map presence at all, and
budget never will have one. The lens model must therefore allow a lens that contributes
**nothing** to the canvas — and it does, cleanly:

- A canvas-optional lens contributes no annotations. Every other layer keeps rendering at
  its context weight, so the map does not go blank; it simply has no focus layer.
- Its console opens at the **half** detent rather than peek, because there is no map
  selection for a peek rail to caption.
- Its console header has no impact readout — that line falls back to the lens's own
  summary (`12 open · 3 due this week`).
- The camera does not move when you switch to it, and the map you left is still there when
  you switch back. That continuity is the whole argument for one canvas.

Tasks is the proof this works rather than a special case to code around: it is a full
first-class lens that happens to draw nothing. Budget, when it arrives, is the same shape.

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
│  ⬤A&C   Andey & Calvin · Sep 18, 2027  ⌕     │  Context bar — §5
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

Vertical budget on a 6.7" device, peek detent: context bar 52, canvas ≈ 388, console 256,
lens rail 82. The canvas never drops below ~35% of the screen at any detent short of full.

---

## 5. Context bar

Replaces `IdentityBar`. One row, 52 pt, floating material capsule, 16 pt insets.

```
⬤ A&C    Andey & Calvin · Sep 18, 2027                          ⌕
```

- **Monogram**, 36 pt (down from 58). Tap → account sheet (sign out, settings, workspace
  switcher). Unchanged behavior, smaller footprint.
- **Title line**, one line, truncating tail. `coupleNames`, then a middot, then the
  countdown derived from `WeddingSummary.weddingDate`.
  - `> 365 days`: `Sep 18, 2027` — a day count that large is noise, not motivation
  - `≤ 365 days`: `86 days` → `12 days` → `Tomorrow` → `Today`
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
| **Peek** | 256 pt fixed | Header + impact readout + one horizontal card rail |
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

Two things the console must inherit rather than reinvent, both landed or landing since
this was drafted:

- **The Guests display resolver.** The guest row's subtitle comes from the wedding's
  designated subtitle column, resolved from column *definitions*, not from a literal
  `customFields["group"]` lookup — see `vowbase-ios-guests-ux-spec.md` §"Display resolver".
  An absent value renders as nothing, not `No group`. The peek rail card (§7.3) uses the
  same resolver, so a wedding that groups by `side` or `table` reads correctly in both.
- **Active filter tokens** carry over from the Guests spec as-is. They sit between the
  chips and the list, and clearing them does not clear search.

### 7.5 Clearance

Do not invent bottom padding. `feat/venues-scroll-clearance` introduces
`VowbaseControlMetric.quickAddClearance` and a `vowbaseScrollClearance(includesQuickAdd:)`
modifier precisely so no screen carries its own constant, and the console's list is one
more scroll container that must adopt it.

Note the overlap: that branch's §8 fix and this document's §6.5 FAB relocation address the
**same bug** from opposite ends. Its fix insets content beneath a FAB that floats over
content; §6.5 moves the FAB so it never floats over content at all. Both are worth having
— pushed detail screens keep the inset even once the map's FAB has moved — but land the
branch first and treat §6.5 as removing the reason the clearance has to include the FAB on
console-bearing screens. Two people fixing this independently will produce a double inset,
which is the bug the branch is fixing.

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
│   ◉        📍        👥        ☑︎          │
│ Overview  Venues   Guests    Tasks         │
└────────────────────────────────────────────┘
```

- Active slot: filled glyph, white label, `.white.opacity(0.16)` capsule — as built today.
- Selection is conveyed by capsule, glyph fill, and `.isSelected` trait, never by color
  alone.
- Switching lenses: 0.22 s crossfade on markers, console keeps its detent, camera holds.
  A canvas-optional lens (§2.1) crossfades to no focus layer and moves no camera.

### 9.1 The slot budget is nearly spent

Tasks made this urgent. Four lenses exist **today** — Overview, Venues, Guests, Tasks —
against a five-slot rail. Vendors takes the fifth exactly; Lodging is the first one that
overflows.

- **At five or fewer:** all lenses get a fixed, equal-width slot. `Overview` always leads.
- **At six or more:** the fifth slot becomes `More`, opening a grid sheet of the
  remainder. The lens chosen from that sheet occupies the fourth slot for the session, so
  the thing you are actually working on is never two taps away twice.
- No horizontal scrolling. A rail that scrolls is a rail whose targets move.

Slot width, at a 393 pt screen with the rail's 14 pt insets, 6 pt padding and 4 pt gaps:
**four slots = 85 pt, five = 67 pt.** `Overview` is the longest label and the one that
governs. The prototype renders three slots at 111 pt, so neither of these has been
measured on a device — do that before Vendors lands. If `Overview` will not hold at
11 pt semibold in 67 pt, the rail drops to **glyph-only with labels kept for VoiceOver**
rather than shrinking type below legibility or truncating a navigation target.

---

## 10. Quick add

The FAB is lens-aware, which is what keeps it one tap forever.

- **Tap** → the active lens's create sheet directly. On Venues, tap = Add venue; on
  Guests, Add guest; on Tasks, Add task. On Overview, tap opens the panel.
- **Long press** → the full panel of every lens's create action, as `QuickAddPanel` does
  today. It now carries three rows (Task, Venue, Guest), which is exactly the growth that
  motivates making tap lens-aware: the panel gets longer with every domain, the tap never
  does.
- The FAB's glyph carries the lens tint ring so the primary action is legible before you
  press it.
- Creating from the canvas: long-pressing empty map opens `Add venue here` with the
  coordinate pre-filled and reverse-geocoded. Same path as a Places search result.

`QuickAddPanel` needs no structural change — it becomes a list driven by the lens registry
rather than the three hardcoded rows it has today.

### 10.1 Roles

The Tasks work introduced write permissions the rest of the app does not yet honour:
`VowbaseWorkspaceStore.canManageTasks` derives from `WeddingMembership.role`, and parent
and viewer roles are read-only. The command center inherits this, and the rule from the
Tasks plan holds everywhere — *never render a control that predictably fails*:

- A read-only role gets **no FAB at all**, not a disabled one. There is nothing it could
  usefully do.
- Long-press quick add is likewise absent, as is long-press-to-add on the canvas.
- Every lens still appears in the rail, and the console still lists everything. Reading the
  plan is the whole point of these roles.
- The Overview "Needs you" module still renders, but its rows route to the object rather
  than to an edit affordance, and nudges cannot be promoted into tasks (§11.3).

Per-domain write permission is a later problem. Today the role gate is uniform, so derive
one `canEdit` on the store and let every lens read it rather than growing a matrix before
there is anything to put in it.

---

## 11. Overview lens — the command center proper

Overview is what earns the phrase "one-stop shop." Canvas: every layer at equal weight,
camera fit to everything, nothing selected. Console: a vertical stack of **modules**.

```
┌────────────────────────────────────────┐
│                 ▬▬▬                    │
│  Sep 18, 2027                415 days  │
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

### 11.3 "Needs you" — reconciling with the Tasks domain

This module was drafted when nothing in the app tracked what to do next. Tasks now does,
with real due dates, priorities, owners, and a five-lane board. Two competing answers to
"what needs me?" is precisely the duplication this whole document exists to remove — the
tab bar and the layer chips all over again. So resolve it rather than shipping both.

**They are different kinds of thing, and the module must keep them visibly different.**

| | Task | Nudge |
| --- | --- | --- |
| Origin | A person wrote it down | The app noticed a data condition |
| Has | Due date, owner, priority, status | None of these |
| Ends when | Someone marks it Done | The condition stops being true |
| Can be assigned | Yes | No |
| Lives in | `wedding_tasks` | Nowhere — recomputed every render |

A nudge is not a lesser task; it is an observation. "18 guests have no location" is not
work someone agreed to do, and rendering it as a task with no owner and no due date would
make the task list dishonest.

**The module's composition, in order:**

1. **Overdue tasks**, then **tasks due within 7 days** — real commitments, up to three.
   Same ordering as the Tasks list: due date, then priority, then title.
2. **At most two nudges**, from the rules below, only if space remains.
3. If neither produces a row, the module hides. An empty "Needs you" is worse than none.

**Suppression.** A nudge is dropped when an open task plausibly covers it. Do this with an
explicit `coversNudge: NudgeID?` written when a task is created *from* a nudge — not by
matching title text, which will produce false positives on any wedding whose planner
happens to name a task "Guest locations."

**Promotion is the bridge.** Every nudge row carries a trailing `＋` that creates a real
task from it: title pre-filled, `coversNudge` set, editor open on the due-date field. This
is what makes Tasks and the map one product rather than two — the app notices something,
and one tap turns the observation into work someone owns. Hidden for read-only roles
(§10.1).

**Nudge rules,** unchanged in substance from the first draft, now capped at two shown:

1. `venues.isEmpty` → *Add your first venue*
2. `toured ≥ 2 && booked == 0` → *Pick a venue — N toured, none held* → Venues, compare
3. `guests.withoutCoordinate > 0` → *N guests have no location* → Guests, filtered
4. `daysUntilWedding ≤ 120 && rsvpPending > 0` → *N RSVPs outstanding* → Guests, filtered
5. `booked == 1` → drops rules 1–2 and demotes the module to `.ambient`

Later domains append rules — vendor payment due inside 14 days, an event without a
location, a lodging block under-filled — without touching the module's rendering. Each new
rule needs a stable `NudgeID` so promotion and suppression keep working.

### 11.4 Does Overview still earn a rail slot?

Fair challenge now that Tasks exists, and worth stating rather than assuming. Overview
keeps three things Tasks cannot hold: the countdown, the reach readout, and cross-domain
observations that nobody wrote down. Those have no other home. But if `Needs you` is the
only module anyone reads, Overview is a worse Tasks tab and should be deleted, with the
countdown moving to the context bar (where it already is) and reach moving to the Venues
console header (where it already is).

Decide this from usage after Phase 5, not from argument. The instrumentation is one event:
which module a session taps first.

---

## 12. States

| State | Canvas | Console |
| --- | --- | --- |
| Loading | Map renders; markers fade in as data lands | Header shows skeleton rows; no spinner over the map |
| No workspace | Map at world zoom, no markers | Full-detent explainer + "Create a wedding" |
| Lens empty | No focus markers; context layers remain | Empty card with the lens's create action |
| Offline | Cached tiles; markers still render from cached data | Muted banner in the header; impact readout shows `Retry` |
| Read failed | Unchanged | Inline in the header, not a full-screen takeover |
| Write failed | Unchanged | The shipped `SaveFailure` alert — see below |

The current build's centered `ProgressView("Loading your wedding")` over the whole screen
goes away. The map is instantly useful; the data can arrive underneath it.

**Reads and writes fail differently, and the first draft conflated them.** `WeddingAppShell`
now presents a `SaveFailure` alert with *Try again* / *Discard changes* (`ContentView.swift:156`),
which arrived with the Guests inline editor. That is the right shape for a failed write:
the user typed something, it is at risk, and a banner they can scroll past would lose it.
Keep it, app-wide, and do not build a second inline pattern that competes.

Inline-in-the-header is for **reads** — a travel request that timed out, a stale list, an
offline map. Nothing is at risk, so nothing should be modal. §8.1's four unavailable
states are all read failures and all stay inline.

The console must also carry `.refreshable` at the half and full detents, matching the pull
to refresh both lists gained in `857e064`. Peek has no scroll of its own to pull.

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

- Guest positions come only from `originPrecision == "city"` (`ContentView.swift:3366`).
  No household pins, ever.
- The impact readout is computed against **clusters**, never individuals, and reports
  aggregates only.
- Any future person-shaped layer (wedding party, lodging occupancy) inherits the same
  city-coarse rule before it may render on the canvas.

---

## 15. What this replaces

| Today | Becomes | Why |
| --- | --- | --- |
| `AppTab` (Map/Venues/Guests/Tasks) | `PlanLens` (Overview/Venues/Guests/Tasks/…) | One taxonomy, extensible |
| `VowbaseTabBar` | Lens rail | Same component, new source of truth |
| `LayerChip` × 2 | *Deleted* | The rail already does this |
| `IdentityBar` | Context bar | 80 pt of names → 52 pt of names, date, and search |
| `ShortlistPanel` | Console, peek detent | Gains detents and selection-aware header |
| `VenuesView` / `GuestsView` bodies | Console, half/full detent | Same lists, no separate screen |
| `TasksView` body | Console, half/full detent | Canvas-optional lens, §2.1 — the view itself is unchanged |
| `MapVenueCard` (4 facts, truncating) | Rail card (2 facts) | Location is redundant beside a pin |
| `travel = "Unavailable"` | Impact readout | Wires up `travelTimes`, already in the API |
| Bottom-right floating FAB | FAB riding the console's top edge | Stops overlapping cards |

What this explicitly does **not** replace, now that it exists: the Tasks list and board,
the task editor, the Guests inline detail editor, the custom-field manager, or the
`SaveFailure` alert. Those are content inside the console, not structure around it. This
document changes how you get to a list, never what the list is.

Deliberate reversals of the MVP spec:

1. **"Exactly three top-level destinations."** Already reversed by the Tasks plan, which
   took it to four. Now: exactly one surface, N lenses.
2. **"An all-off layer state is allowed."** Now: unreachable, and no loss.
3. **"The FAB sits inside the bottom-right of the Shortlist surface."** Now: above it.

And one reversal of this document's own first draft: it claimed every lens contributes to
the canvas. Tasks does not, and §2.1 now says so.

---

## 16. Build order

A precondition first: `ContentView.swift` is **4,140 lines**, up from 2,108 when this was
drafted. None of this is testable or reviewable in place. Split before building.

The good news is that the split no longer needs arguing for — it is already happening.
Tasks shipped **entirely outside** `ContentView.swift` (`Features/Tasks/TasksView.swift`,
`TaskStore.swift`, `TaskEditorSheet.swift`, `TaskModels.swift`), Guests moved
`GuestFiltering`, `GuestFieldEditing` and `GuestModels` out, and `MVPVenue`, `MVPGuest`,
`GuestCluster` and `VowbaseWorkspaceStore` are now internal rather than `private`. The
pattern and the precedent both exist. What is left in the blob is the Map, Venues and
Guests *views*, plus the store.

**Phase 0 — Split.** Finish what Tasks started. `AppShell/`, `Features/Map/`,
`Features/Venues/Views/`, `Features/Guests/Views/`. Move `VowbaseWorkspaceStore` to
`AppShell/WorkspaceStore.swift`. Behavior-neutral; existing tests must pass untouched.

> **Sequencing against work in flight.** `feat/venues-scroll-clearance` is rewriting
> `VenuePatch`, `MVPVenue` and the venue detail inside `ContentView.swift` right now. A
> file-splitting commit and an inline-editing rewrite in the same 4,000-line file will
> conflict badly. Land that branch first, then split. Do not run these in parallel.

**Phase 1 — Lens model.** `PlanLens` enum + registry, including the canvas-optional case
(§2.1) — Tasks needs it on day one, so it is no longer a hypothetical to design around.
Replace `AppTab` and delete `LayerChip`. The rail renders from the registry. Venues,
Guests and Tasks conform. The screen looks nearly identical; the structure is now
additive. *This is the skeleton the rest hangs on — ship it alone if nothing else ships.*

**Phase 2 — Console.** Three detents, selection-aware header, redesigned rail card,
list bodies moved in, camera insets wired to sheet height. FAB relocated.

**Phase 3 — Context bar.** Countdown from `weddingDate`, monogram down to 36 pt, search
glyph (field can land inert and gain results in 3b).

**Phase 4 — Impact readout.** Wire `travelTimes`, cluster badges, the four unavailable
states, and replace the hardcoded `travel` string. Highest user-visible payoff; depends
on nothing above except the console header.

**Phase 5 — Overview lens.** Module contract, the four MVP modules, and the task/nudge
reconciliation in §11.3 — including `NudgeID`, the `coversNudge` field on tasks, and
promotion. Depends on Tasks, which now exists, so this is unblocked.

**Phase 6+ — New domains.** Each is: one `PlanLens` conformance, one rail card, one list
row, one create sheet, one overview module — and, for a canvas-optional domain, no map
work at all. Vendors first (`VendorRepository` exists), then day-of events
(`ScheduleRepository` exists), then lodging. Vendors takes the fifth rail slot; Lodging is
the one that triggers §9.1's overflow rule, so settle that before Lodging, not before
Vendors.

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
   Worth a decision before Phase 5. Sharper now that Tasks exists — see §11.4 for the
   stronger version of this question, which is whether Overview should exist at all.
2. **Travel request cost.** `travelTimes` per venue selection across N clusters could be
   chatty. Needs a per-venue cache keyed on `(venueID, clusterSignature)`; the API already
   reports `.cache` as a source, so confirm the server caches before we build a client one.
3. ~~**Budget as a lens with no canvas presence.**~~ **Answered by Tasks**, which shipped
   as exactly that. The lens model must support it, and §2.1 now specifies the behavior.
4. **Does the console's half detent leave enough room for the Tasks board?** Tasks Board
   mode is a horizontal lane scroller that wants height, and the plan gives iPhone a lane
   filling most of the viewport. Half detent may force Board to open at full, which is
   defensible but should be a stated rule rather than an accident. Decide in Phase 2.
5. **Does `@AppStorage` list/board preference survive becoming a lens?** The Tasks plan
   persists presentation mode locally and preserves it across tab switches. Console detent
   is also per-lens session state. Confirm these two do not fight when Tasks becomes a
   lens whose console has its own detent memory.
