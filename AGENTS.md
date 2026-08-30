# Vowbase Native iOS Repository Instructions

## Repository Scope

This checkout owns the native SwiftUI Vowbase application.

- The web application, server/API, MCP server, Supabase migrations, and Lovable metadata live in `/Users/calvin/Projects - Local/Wedding/Vowbase`.
- Confirm the requested surface from the user’s wording and attachments. Do not patch the web checkout for an iOS request or native screenshot.
- For cross-platform work, inspect both repositories and define the shared behavior and data contract before editing either one.
- Do not modify the sibling web/server repository unless the request explicitly includes it.
- Preserve all unrelated tracked and untracked work. Never broad-stage a shared worktree.

## Planning and Product Design

- “Plan first,” “don’t code yet,” “explore,” and Product Design requests are read-only until the user explicitly approves implementation.
- Preserve approved copy, behavior, option selection, ordering, non-goals, schema boundaries, and visual scope exactly.
- Ground visual work in the current app and the latest approved evidence. `design-qa.md` includes historical and sometimes superseded comparisons; trace later product revisions before treating an older screenshot as authoritative.
- When Product Design generates visual options, provide a numbered list mapping every option to a clickable absolute local artifact path so mobile clients can open them.

## Architecture and Ownership

- `Vowbase/VowbaseApp.swift` and `Vowbase/ContentView.swift` own application entry, authentication restoration, incoming URLs, workspace loading, and the transition into the signed-in shell.
- `Vowbase/AppShell/WeddingAppShell.swift` owns the persistent shell, selected lens, modal routing, detents, navigation reset behavior, and lens-specific refresh/action routing.
- `Vowbase/AppShell/ContextBar.swift` is persistent workspace chrome. It is not the same surface as a modal title or header.
- `Vowbase/AppShell/Console.swift` owns console detents and shared modal controls such as `ConsoleHeader` and `CompactConsoleSearchField`.
- `Vowbase/AppShell/WorkspaceStore.swift` owns the loaded wedding, memberships, venues, guests, workspace mutations, and derived MVP models.
- Tasks and Timeline retain their dedicated stores and repositories. Do not silently move their loading or error semantics into `WorkspaceStore`.
- Repositories and models under `Vowbase/Features/` own transport contracts. Views should not construct one-off Supabase requests.
- Reuse `Vowbase/DesignSystem/`, `VowbaseTheme`, typography, status capsules, image components, and shared controls before creating local substitutes.
- When behavior should apply across lenses, fix the shared shell or shared control first, then add only the necessary per-lens wiring.

## Navigation, Modals, and Map Behavior

- Keep authentication and incoming-link state at the app boundary; let the existing lens/navigation system consume resolved destinations.
- Use one authoritative modal-routing state for mutually exclusive sheets. Multiple competing `.sheet` hosts for the same interaction are a regression risk.
- Re-tapping an active app-navigation lens should return that lens to its root when this behavior is part of the established shell contract.
- Treat allowed detents, current detent, modal content, and default detent as separate decisions. Removing an intermediate detent means removing it from the allowed set, not only changing the default.
- A request for the app’s “top bar” or workspace-name bar means `ContextBar`; a modal title/header means `ConsoleHeader` or the feature’s navigation bar.
- Preserve intentional nested horizontal surfaces such as photo rails when constraining an outer vertical console.
- Map focus must account for the unobscured viewport above the current console. Include detent/console height in camera refresh inputs and center the selected venue or guest cluster in the viewable map area.
- Keep map selection, detail navigation, and compact-card highlighting distinct unless the requested interaction explicitly joins them.

## Data Contracts, Authorization, and Privacy

- Scope repository reads and writes to the requested wedding/workspace. Do not assume the first active membership is the intended workspace when handling explicit destinations or shared links.
- Shared record links must carry both wedding ID and record ID, select an authorized workspace, and reuse the existing venue/guest detail navigation.
- Use a generic unavailable state for missing, deleted, unauthorized, or workspace-mismatched records. Do not reveal record existence across authorization boundaries.
- Supabase payloads are commonly snake case. Add explicit `CodingKeys` or deliberately tested dual-format decoding; do not assume automatic snake-case conversion.
- When a schema field changes, search models, repository select columns, create/update payloads, patches, derived MVP models, views, fixtures, and tests. Editing one layer is incomplete.
- Distinguish omitted, `null`, blank, and unchanged patch states. Clearing an existing value must encode the intended `null` rather than silently omit the field.
- Guest household addresses and precise coordinates are private. Guest map origins remain coarse city-level data and retain origin-specific semantics; never treat them as venue-like exact coordinates.
- Names, addresses, and contact data must not leak into anonymous link metadata, logs, Timeline entries, screenshots, or error copy.
- Preserve local state only after the authoritative write succeeds, or make optimistic/retry behavior explicit and reversible.

## Configuration and Secrets

- Follow `README.md` and the current files under `Configuration/`; current source is authoritative over historical Xcode Cloud instructions.
- Debug local values belong in ignored `Configuration/Local.xcconfig`.
- Release may contain only client-visible endpoints and the Supabase publishable key.
- Never add a Supabase service-role key, OAuth client secret, provider secret, or other server-only credential to source, configuration, tests, logs, screenshots, or memory.
- The custom `vowbase://` scheme is reserved for authentication callbacks. Canonical guest and venue sharing uses supported HTTPS Universal Links.

## SwiftUI and Performance

- Prefer native SwiftUI presentation, toolbar, navigation, share, preview, and Liquid Glass patterns when available, with an appropriate fallback for supported older iOS versions.
- Preserve the surrounding layout boundary when a request targets one visual element. For example, changing an icon size does not imply changing its tile or hit target.
- Avoid nested `List`/scroll containers and repeated expensive derived-model work in scrolling detail surfaces.
- Use stable identity for collection and section diffing. Progressive rendering should reset when the active wedding changes.
- A structural optimization is not measured performance proof. For claims about lag, scrolling, launch, or transition performance, use a production-scale fixture and ETTrace/Instruments when available.
- Maintain accessibility labels, Dynamic Type behavior, focus dismissal, keyboard save paths, destructive confirmations, and non-touch alternatives when replacing controls.

## Build and Validation

Use the existing `xcode-simulator`, `validate-ux`, SwiftUI, and performance skills when their triggers match the request.

Before any Simulator validation, confirm:

- Exact checkout: `/Users/calvin/Projects - Local/iOS Apps/Vowbase` or the explicitly selected worktree.
- Project: `Vowbase.xcodeproj`.
- Scheme: `Vowbase`.
- Bundle ID: `Mooma.Vowbase`.
- A concrete Simulator UDID rather than an ambiguous device name.
- An isolated DerivedData path for worktrees or after build-database/cache collisions.
- Xcode is displaying the same checkout being validated, not another project or worktree.

Validation rules:

- After code changes, at minimum build the affected app target.
- Run focused tests for changed behavior. Run broader suites when shared repositories, models, navigation, or shell behavior changes.
- `build-for-testing`, successful compilation, launched XCTest, and completed passing tests are different evidence; report them separately.
- If a full suite contains a reproducible unrelated failure, report it and use focused suites as the change-specific gate. Do not call the full suite green.
- For user-visible changes, exercise the exact state on an iPhone Simulator and inspect a screenshot when authentication and fixtures allow it.
- A successful build does not prove taps, detents, keyboard behavior, map focus, authenticated media, or populated states.
- If fixture/authentication or Simulator instability blocks the requested state, make at most one focused retry after correcting checkout/device configuration, then report the limit instead of churning.
- Performance changes require a representative large-data fixture or trace before claiming smoother frame rates.
- Simulator evidence does not prove physical-device behavior, Universal Link association propagation, Xcode Cloud distribution, TestFlight upload, or App Store release.
- Stop the app and release any leased Simulator/queue state after validation.

## Cross-Platform Changes

When a request includes both web/server and iOS:

1. Write the shared behavior, timestamp/field precedence, authorization, privacy, and failure semantics first.
2. Trace the current schema and both client projections before choosing a migration.
3. Keep schema changes minimal when the same behavior can be derived safely from existing data.
4. Add matching focused tests in both repositories.
5. Validate each repository independently, then compare the observable behavior.
6. Do not apply a destructive Lovable migration until compatible clients are deployed and validated, unless the user explicitly accepts a coordinated cutover.

## Git and Publication

- Inspect status before editing and before staging. Preserve unrelated files and hunks.
- Commit or push only when the user asks.
- For cross-platform publication, make separate scoped commits in the iOS and web/server repositories and verify both remotes.
- Stage explicit paths or hunks. Before committing, inspect cached names, `git diff --cached --check`, and the full cached diff. After committing, inspect `git show` to prove the result.
- Fetch before pushing. If the remote advanced, inspect and rebase the scoped work; never force-push shared `main`.
- Use plain engineering commit messages with no model, agent, or tool attribution.

## Final Reporting

Always state:

- Which repository or repositories changed.
- The user-visible behavior and important non-goals.
- Whether schema, generated artifacts, live data, Lovable, configuration, entitlements, or external infrastructure changed.
- Build, test, Simulator, screenshot, performance, device, cloud, and release evidence actually obtained.
- Any blocked or unexercised state.
- Whether changes are uncommitted, committed, pushed, deployed, migrated, uploaded, or released.
