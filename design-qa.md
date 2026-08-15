# Venues List Design QA

- Source visual truth: `/Users/calvin/.codex/generated_images/01a0074b-b05b-7ab1-8018-5fe6ae1ca15b/exec-3e23a407-a35a-4486-b0c5-2823ab91c235.png`
- Source pixels: 852 x 1846
- Intended app viewport: iPhone portrait, medium and full console detents
- Implementation screenshot: unavailable
- Implementation pixels, CSS size, and density normalization: not applicable; this is a native SwiftUI app and no accepted Simulator screenshot was captured
- State: DEBUG testing workspace, Venues lens, medium and full detents

## Full-view comparison evidence

Blocked. The source visual was opened and inspected. The app built and its complete test suite passed on iOS 26.5, but multiple concurrently open Simulator windows caused UI control to switch away from the leased device. A direct `simctl` capture of the leased device then timed out waiting for screen surfaces, so there is no valid implementation image to compare.

## Focused-region comparison evidence

Blocked for the same reason. The venue rows, filter/action controls, and preserved console header could not be inspected from an accepted implementation screenshot.

## Findings

- [P1] Native visual fidelity remains unverified.
  - Location: Venues lens, medium and full console detents.
  - Evidence: source image is available; implementation screenshot is not.
  - Impact: row density, truncation, persistent rail clearance, and title preservation cannot be confirmed visually.
  - Fix: capture the DEBUG testing workspace on a Simulator window that can be exclusively targeted, then compare both detents against the source.

## Required fidelity surfaces

- Fonts and typography: blocked pending implementation capture.
- Spacing and layout rhythm: blocked pending implementation capture.
- Colors and visual tokens: source uses existing Vowbase tokens in code; rendered result remains unverified.
- Image quality and asset fidelity: existing `VowbaseVenueImage` is reused; rendered crop remains unverified.
- Copy and content: the shortlist remains the primary list, while the source mock's Compare action is intentionally omitted per the corrected product direction; rendered truncation remains unverified.

## Comparison history

- Initial pass: blocked because no accepted implementation screenshot could be captured. No visual fixes were made from screenshot evidence.

## Implementation checklist

- Capture medium-detent Venues list in the DEBUG fixture.
- Capture full-detent Venues list in the same fixture and viewport.
- Check title treatment, row truncation, filter interaction, row navigation, FAB/rail clearance, and dark-mode contrast.

final result: blocked
