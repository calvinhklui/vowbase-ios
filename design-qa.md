# Travel Coverage Map — Design QA

- Source visual truth: `/Users/calvin/Projects - Local/iOS Apps/Vowbase/design-evidence/approved-reference.png`
- Implementation screenshot: `/Users/calvin/Projects - Local/iOS Apps/Vowbase/design-evidence/implementation-nested-modal.png`
- Venue insight screenshot: `/Users/calvin/Projects - Local/iOS Apps/Vowbase/design-evidence/implementation-venue-reach-modal.jpg`
- Original combined comparison: `/Users/calvin/Projects - Local/iOS Apps/Vowbase/design-evidence/comparison-pass-2.png` (superseded by the product revision below)
- Viewport: iPhone 17 Simulator, iOS 26.5, 402 × 874 points at 3×
- Source pixels: 853 × 1844
- Implementation pixels: 1206 × 2622
- Density normalization: each artifact was proportionally scaled and centered into a 426 × 922 panel; the combined comparison is 852 × 922
- State: Guests tab console → selected `Duluth, MN` guest-origin cluster → nested Travel Coverage modal, travel comparison ready

## Full-view comparison evidence

The revised implementation preserves the source hierarchy: persistent context bar, three-way map layer picker, emphasized guest cluster, two color-coded dashed venue relationships with duration badges, a roughly half-height white console, RSVP summary, guest strip, strategic readout, two read-only travel rows, privacy note, and four-item bottom rail. There are no contextual CTA buttons or disclosure chevrons.

Native product constraints account for the remaining acceptable differences: the established context bar keeps its refresh action instead of introducing an unimplemented search affordance; the console uses guest initials because the current guest model has no profile-photo field; and Apple Maps supplies the live basemap and labels.

## Focused-region evidence

No additional crop was needed. At the normalized comparison size, the map relationships, console typography, venue rows, privacy note, and rail labels are all readable. The native-resolution implementation was also inspected independently to verify icon sharpness, material edges, line dashes, and small copy.

## Required fidelity surfaces

- Fonts and typography: existing Vowbase serif display and system UI typography preserve the source hierarchy and remain legible without truncation.
- Spacing and layout rhythm: the dedicated 52% travel detent matches the source console proportion; all approved content fits above the persistent rail without scrolling.
- Colors and visual tokens: Vowbase rose, blush, guest blue, ink, and border tokens are used consistently for selection, routes, rows, and annotations.
- Image quality and asset fidelity: the implementation uses native MapKit rendering and SF Symbols; no placeholder drawings, emoji, or rasterized UI substitutions were introduced.
- Copy and content: cluster name, RSVP breakdown, guest count, strategic venue readout, venue names, travel times, and city-level privacy language are present. Requested CTA and chevron removal is preserved.

## Comparison history

### Pass 1 — blocked

- P1: the persistent rail omitted Overview, conflicting with the selected Overview state in the source.
- P2: the generic 60% half detent made the console too tall and obscured too much route context.
- P2: the privacy line fell below the visible region.
- Fixes: restored Overview to the visible rail, added a cluster-specific 52% travel detent, tightened console rhythm and venue-row height, and gave the selected-cluster console an opaque Vowbase background.

### Pass 2 — passed

The revised capture shows the complete four-item rail, both route durations, the full venue comparison, and the privacy note at the approved console proportion. No actionable P0, P1, or P2 differences remain.

## Interactions verified

- Selecting the 14-person Duluth cluster opens the travel console and loads two venue comparisons.
- Guest origins hides venue pins while preserving selected-cluster travel context.
- Venues hides guest clusters and clears the cluster drill-in.
- All restores both map layers.
- Venue comparison rows remain read-only with no buttons or chevrons.

## Follow-up polish

- P3: real guest photography can replace initials if a profile-photo field is added to the guest domain later.
- P3: a dedicated search experience could replace the existing refresh action only as a separately scoped product decision.

## Product revision after Pass 2

The user intentionally superseded the original navigation composition after visual QA:

- Removed Overview from the user-facing tab rail; the persistent rail is Venues, Guests, and Tasks.
- Removed the All / Venues / Guest origins layer selector; venues and city-level guest clusters remain visible together.
- Moved Travel Coverage into an item-driven sheet presented from inside the persistent console, so it stacks above the currently selected tab modal.
- Venue pins now use the same map-insight sheet route, presenting venue status and facts, a guest-weighted reach summary, and city-level origin rows without CTA buttons or chevrons.
- Verified on iOS 26.5 that selecting Duluth from Guests presents the nested sheet and dragging it down returns to the unchanged Guests console and three-tab rail.
- Verified on iOS 26.5 that the Venue Reach sheet renders above Venues with the shared 18 pt top content inset and production-equivalent fixture travel data.

The approved Travel Coverage content, route styling, read-only venue rows, and privacy treatment remain unchanged. The differences from the original visual are explicit user-directed product changes rather than fidelity defects.

final result: passed
