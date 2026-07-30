# Vowbase iOS Tasks Tab Implementation Plan

Status: Ready for implementation
Date: July 30, 2026
Platform: Native SwiftUI, iOS 18+
Base commit: `c4d7e88` (`main`)

## Outcome

Add Tasks as the fourth authenticated tab in the order Map, Venues, Guests, Tasks. The tab reads and mutates the existing Supabase `tasks` rows through the native repository layer and supports two presentations of the same task collection:

- **List** for fast, date-oriented execution and one-tap completion.
- **Board** for status-oriented planning across Backlog, To Do, In Progress, Blocked, and Done.

The feature includes create, read, update, delete, assignment, search, filters, pull to refresh, role-aware permissions, deterministic DEBUG fixtures, and live cross-platform verification. It does not require a database migration.

## Scope change from the current MVP specification

This feature deliberately expands the approved three-tab MVP in `docs/vowbase-ios-mvp-ux-spec.md`:

- The authenticated shell grows from three tabs to four.
- Quick Add grows from Venue and Guest to Task, Venue, and Guest.
- Map remains the default tab and the app remains map-first.
- Venue and Guest behavior, order, filters, and navigation remain unchanged.

Treat this document as the controlling scope for Tasks only. Do not opportunistically add Vendors, Schedule, Budget, subtasks, tags, task notifications, or a dashboard.

## Locked product decisions

### Tab and view defaults

- Append Tasks after Guests and use the SF Symbol `checklist`.
- Default to List on compact-width iPhone and Board on regular-width iPad when no preference exists.
- Persist an explicit user choice locally with `@AppStorage`; do not sync it to Supabase.
- Preserve the selected mode, query, filters, and scroll position while switching tabs during the current session.

### Status mapping

| Server value | UI label | Completion behavior |
| --- | --- | --- |
| `backlog` | Backlog | Open |
| `todo` | To Do | Open; default for new tasks |
| `in_progress` | In Progress | Open |
| `blocked` | Blocked | Open |
| `done` | Done | Completed |

Legacy rows with a null status render as To Do. New and edited tasks always save a non-null status. Uncompleting a Done task sets it to To Do because the server does not retain a previous status.

### Priority mapping

Support Low, Medium, High, and Urgent. Legacy null priorities render without a priority badge; new tasks default to Medium. Priority must never be communicated by color alone.

### Ordering

- List sections sort by due date, then priority, then localized title.
- Board cards use the same deterministic ordering within each lane.
- Do not implement manual ordering within a lane. The server has no position field, so such ordering would be lost after refresh.

### Completion and deletion

- List rows expose a Reminders-style completion circle that updates status to Done.
- Completed tasks are hidden by default in List and visible by default in Board.
- Deletion is permanent because the server has no soft-delete or recently-deleted model. Require confirmation and never imply recovery is available.

### First-pass field scope

The editor owns the fields already exposed by the web task experience:

- Title
- Description
- Status
- Priority
- Owner member and owner label
- Due date

Preserve `related_vendor_id` and `related_event_id` on updates but do not expose pickers until native Vendors and Schedule surfaces exist.

## Experience specification

### Tasks root

Use the existing authenticated visual language and identity bar.

1. Identity bar.
2. Eyebrow `WEDDING PLAN`.
3. Display title `Tasks`.
4. Summary such as `12 open · 3 due this week`.
5. Full-width `List / Board` segmented control.
6. Search and Filters controls.
7. Active view content, padded clear of the floating tab bar and FAB.

Search is local after tasks load and matches title, description, owner label, and resolved member name. Filters support owner, priority, due state, and—only in List—status. Active filters display a count. Clearing filters must not clear the search query.

### List view

Use a SwiftUI `List` with stable task IDs, plain styling, themed background, native swipe actions, and these sections:

1. Overdue
2. Today
3. Next 7 Days
4. Later
5. No Date
6. Completed, only when Show Completed is enabled

Each row contains:

- A minimum 44 pt completion target.
- Task title, up to two lines.
- Due date with an overdue treatment when applicable.
- Resolved owner name or owner label.
- Compact priority and non-default status metadata.
- A full-width tap target that opens the editor without competing with the completion control.

Actions:

- Tap completion circle: mark Done or return to To Do.
- Tap row: edit task, or open read-only detail for a non-writing role.
- Leading swipe: Complete/Uncomplete and Move.
- Trailing swipe: Delete with confirmation.
- Context menu: Edit, Move to Status, Duplicate, Delete.
- Pull to refresh: reload task and assignee data while preserving already-loaded content.

### Board view

Use a horizontal `ScrollView` with a lazy horizontal stack of five stable lanes. Each lane has its own vertically scrolling lazy stack so horizontal lane navigation and vertical card navigation remain distinct gestures.

- On iPhone, a lane fills most of the viewport and leaves a visible peek of the next lane.
- On iPad, use fixed readable lane widths so multiple lanes can appear together.
- Lane headers show label and count.
- Empty lanes remain valid drop destinations and show a quiet instruction.
- Cards show title, owner, due date, and priority only.
- Tapping a card opens the same editor used by List.

Moving a card:

- Use system drag and drop with the task UUID as the transferable payload.
- Highlight the targeted lane and provide a selection haptic on a successful move.
- Apply the status change optimistically, disable a second mutation for the same task, and roll back on failure.
- Always expose Move to Status as a context-menu and accessibility action; drag must not be the only path.
- Dropping into the existing lane is a no-op.

### Task editor

Present one item-driven sheet for both add and edit. Wrap the sheet in its own `NavigationStack`; the sheet owns Save, Cancel, Delete, error state, and dismissal.

Form order:

1. Title, required and initially focused for a new task.
2. Description.
3. Due date with an explicit No Due Date state.
4. Owner picker with active wedding members plus a free-text owner-label fallback.
5. Priority.
6. Status.
7. Delete Task destructive section for an existing writable task.

Behavior:

- Trim the title and disable Save while it is empty.
- Disable repeated submission while saving.
- Keep the draft and sheet open after a recoverable failure.
- Dismiss only after the server returns the created or updated row.
- Use the returned row to insert or replace local state; do not refetch solely to learn the saved value.
- Selecting a member writes both `owner_user_id` and the current display label.
- Entering a free-text owner clears `owner_user_id` and writes `owner_label`.
- Clearing an owner, description, or due date sends an explicit JSON null.

### Quick Add

Add Task as the first Quick Add action, followed by the existing Venue and Guest actions. Update all accessibility labels and hints from “venue and guest” to “task, venue, or guest.” Selecting Add Task presents the same editor in create mode.

### Permissions

The server permits task writes for owner, partner, and planner roles. Parent and viewer roles may read tasks but must not receive controls that predictably fail.

| Role | Read | Create/edit/move/complete/delete |
| --- | --- | --- |
| Owner | Yes | Yes |
| Partner | Yes | Yes |
| Planner | Yes | Yes |
| Parent | Yes | No |
| Viewer | Yes | No |

Retain the active `WeddingMembership` in workspace state and derive `canManageTasks` from its role. The repository remains the security boundary; the UI gate is a usability layer.

## Data and repository work

### 1. Make nullable task patches correct

`TaskPatch` currently uses ordinary optionals, which cannot distinguish “leave unchanged” from “clear this nullable column.” Before building the editor:

- Move the existing generic `NullablePatch` declaration from `Features/Guests/GuestModels.swift` to `Models/NullablePatch.swift` without changing Guest or Schedule behavior.
- Change nullable `TaskPatch` fields to tri-state values with `.unchanged`, `.value`, and `.null`.
- Keep `title` as a normal optional because it cannot be cleared.
- Ensure `isEmpty` treats only `.unchanged` as absent.
- Add encoding tests proving explicit nulls for description, owner IDs/labels, due date, priority, and relationships.

### 2. Add assignable wedding members

Introduce a small workspace-member repository rather than querying Supabase from a view:

- `WorkspaceMember`: user ID, role, display name, first name, and email.
- `WorkspaceMemberRepository.activeMembers(weddingID:)`.
- `SupabaseWorkspaceMemberRepository` queries active `wedding_memberships`, then the matching `profiles`, and returns a stable localized-name order.
- Add the repository to `RepositoryContainer` so production and tests share the same injection path.
- Normalize authentication, cancellation, network, decoding, and forbidden errors through the existing backend error policy.

### 3. Strengthen task repository coverage

The existing `TaskRepository` already exposes fetch/create/update/delete. Add focused coverage for:

- Wedding scoping and due-date ordering.
- Full row decoding, including null legacy values.
- Create payload defaults.
- Update payload explicit-null behavior.
- Delete receipt decoding.
- Empty-patch rejection.
- Authentication and backend-error normalization.

Do not add a server migration or bypass the repository with direct client calls from UI code.

## SwiftUI architecture

### Task state ownership

Create a feature-local `@MainActor @Observable TaskStore`. Do not add task arrays and mutation logic to the private, already-large `VowbaseWorkspaceStore`.

`TaskStore` owns:

- Server-confirmed `[WeddingTask]`.
- Active `[WorkspaceMember]` assignees.
- Initial load, refresh, and non-blocking refresh state.
- Per-task mutation IDs so unrelated rows remain interactive.
- Presentation error/banner state.
- Create, update, delete, complete, duplicate, and move operations.
- Pure derived functions for search, filters, date buckets, status lanes, counts, and display labels.

Views own transient presentation state:

- Selected List/Board mode.
- Search query.
- Filter selection.
- Selected editor destination.
- Delete confirmation destination.
- Board drop-target highlight.

Initialize the production store from injected repository protocols in `VowbaseAuthenticatedContent`. The Tasks view starts loading with `.task(id: weddingID)` only after a workspace exists. Cancellation is not surfaced as an error.

### Navigation and sheets

- Add `tasksPath` to `AppNavigationModel` and reset it in `resetNavigation(for:)`.
- Keep one `NavigationStack` for the Tasks tab.
- Define one `TaskEditorDestination` with `.add` and `.edit(UUID)` cases. `WeddingAppShell` owns it and presents it through `.sheet(item:)` so the editor is reachable from every tab.
- Pass the destination binding or narrowly scoped presentation closures into `TasksView`; both task rows and global Quick Add set the same destination instead of maintaining parallel forms.
- Keep task filters and delete confirmation local to the task feature because they are not cross-tab presentations.
- Do not add parallel booleans for add, edit, filters, and delete.

### Loading and errors

- First load: 4–6 shape-matched redacted rows/cards.
- Empty workspace: `No tasks yet` with an Add Task action for writable roles.
- Filtered/search empty: explain which query or filters produced no results and offer Clear Filters.
- Refresh failure: retain existing tasks and show a retry banner.
- Initial failure: use a task-scoped `ContentUnavailableView` with Retry; do not replace the entire app shell.
- Mutation failure: restore optimistic state and announce the failure to VoiceOver.

## File-level implementation map

### Modify

- `Vowbase/AppShell/AppTab.swift`
  - Add `.tasks`, label, and symbol.
- `Vowbase/AppShell/AppNavigationModel.swift`
  - Add task path. Keep the shared task editor destination in the shell unless an existing shared sheet route is fully adopted for all Quick Add cases.
- `Vowbase/ContentView.swift`
  - Own/inject `TaskStore`, retain active membership, render `TasksView`, and route global Add Task.
  - Do not place task rows, board lanes, editor fields, or task mutation logic in this file.
- `Vowbase/DesignSystem/Components/QuickAddFAB.swift`
  - Add the Task action and update accessibility copy.
- `Vowbase/Backend/RepositoryContainer.swift`
  - Inject the workspace-member repository.
- `Vowbase/Features/Tasks/TaskModels.swift`
  - Add display helpers where domain-safe and correct tri-state patch encoding.
- `Vowbase/Features/Tasks/SupabaseTaskRepository.swift`
  - Keep CRUD behavior; adjust only for corrected patch encoding and test seams.
- `Vowbase/Features/Workspace/WorkspaceModels.swift`
  - Add role capability helper or member model if it belongs at the workspace boundary.
- `Vowbase/Features/Guests/GuestModels.swift`
  - Remove the relocated `NullablePatch` declaration only; retain behavior.
- `VowbaseTests/ScheduleTaskRepositoryTests.swift`
  - Expand task contract and nullable encoding coverage, or split task coverage into a focused file.

### Add

- `Vowbase/Models/NullablePatch.swift`
- `Vowbase/Features/Workspace/WorkspaceMemberRepository.swift`
- `Vowbase/Features/Workspace/SupabaseWorkspaceMemberRepository.swift`
- `Vowbase/Features/Tasks/TaskStore.swift`
- `Vowbase/Features/Tasks/TaskViewState.swift`
- `Vowbase/Features/Tasks/TasksView.swift`
- `Vowbase/Features/Tasks/TaskListView.swift`
- `Vowbase/Features/Tasks/TaskBoardView.swift`
- `Vowbase/Features/Tasks/TaskEditorSheet.swift`
- `Vowbase/Features/Tasks/TaskComponents.swift`
- `VowbaseTests/TaskStoreTests.swift`
- `VowbaseTests/TaskRepositoryTests.swift`
- `VowbaseTests/WorkspaceMemberRepositoryTests.swift`

If one of the proposed view files remains very small, combine it with its nearest feature peer. Do not create a single monolithic Tasks file merely to reduce file count.

## Ordered implementation slices

### Slice 1: Contracts and test seams

1. Establish a clean baseline build and test result.
2. Relocate `NullablePatch` and prove Guest/Schedule encodings are unchanged.
3. Correct `TaskPatch` tri-state semantics.
4. Add the workspace-member repository and container injection.
5. Add task and member repository tests.

Exit condition: repository contracts can fetch, create, clear nullable fields, update status, and delete without UI code.

### Slice 2: Store and deterministic fixtures

1. Implement `TaskStore` with load/refresh and returned-row replacement.
2. Add pure date bucket, search, filter, sort, count, and status-lane derivation.
3. Add optimistic complete/move with rollback.
4. Add deterministic tasks and members to the existing DEBUG testing workspace through an in-memory repository.
5. Add store tests for success, cancellation, errors, permissions, and rollback.

Exit condition: store tests exercise the complete CRUD lifecycle and every visible collection state.

### Slice 3: App shell and List mode

1. Add the fourth tab and independent task navigation state.
2. Build the Tasks header, summary, mode control, search, and filters.
3. Build List sections, rows, completion, swipe/context actions, empty/loading/error states, and refresh.
4. Add read-only presentation for Parent/Viewer roles.
5. Add previews for loaded, empty, filtered-empty, loading, error, and read-only states.

Exit condition: every server task is readable and manageable without Board mode.

### Slice 4: Editor and global Quick Add

1. Build the shared add/edit sheet and owner picker.
2. Wire create, update, clear nullable fields, duplicate, and confirmed delete.
3. Add Task to Quick Add and route it to the same editor.
4. Verify keyboard focus, draft retention, duplicate-submit prevention, and all detents.

Exit condition: create/edit/delete works from both the Tasks tab and global Quick Add.

### Slice 5: Board mode

1. Build adaptive lanes and task cards.
2. Add system drag/drop between lanes.
3. Add context-menu and accessibility Move actions.
4. Add target highlighting, haptics, mutation disabling, rollback, and error announcement.
5. Verify Done visibility and deterministic within-lane ordering.

Exit condition: status changes are fast, persistent, recoverable on failure, and fully usable without dragging.

### Slice 6: Validation and polish

1. Run focused tests, then the full native test suite.
2. Build with isolated DerivedData.
3. Exercise DEBUG fixtures on iPhone and iPad.
4. Validate light/dark mode, Dynamic Type through accessibility sizes, VoiceOver, Reduce Motion, Increase Contrast, and Differentiate Without Color.
5. Exercise a live authenticated member workspace and confirm changes appear in the web Tasks section.

Exit condition: automated checks pass and the affected UI has been exercised on-device or in Simulator against both deterministic fixtures and live server data.

## Verification commands

Use a unique DerivedData path to avoid build-database collisions:

```sh
xcodebuild \
  -project Vowbase.xcodeproj \
  -scheme Vowbase \
  -configuration Debug \
  -sdk iphonesimulator \
  -derivedDataPath /tmp/vowbase-tasks-derived-data \
  CODE_SIGNING_ALLOWED=NO \
  build
```

```sh
xcodebuild \
  -project Vowbase.xcodeproj \
  -scheme Vowbase \
  -configuration Debug \
  -sdk iphonesimulator \
  -derivedDataPath /tmp/vowbase-tasks-tests-derived-data \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Also run `git diff --check` and inspect the final diff for unrelated app-shell changes.

## Manual acceptance matrix

### Core CRUD

- Existing server tasks appear in both views with the same field values.
- Creating a title-only task saves To Do and Medium defaults.
- Creating with every exposed field preserves the owner ID/label and date-only due value.
- Editing each field updates only that task.
- Clearing description, owner, priority, and due date persists after refresh.
- Delete requires confirmation and persists after refresh.

### List

- Overdue, Today, Next 7 Days, Later, No Date, and Completed buckets are correct at local-day boundaries.
- Completion hides a row when completed tasks are hidden.
- Show Completed reveals it and uncomplete returns it to To Do.
- Search and filter combinations produce correct results and a recoverable empty state.

### Board

- Every task appears in exactly one lane; null status appears in To Do.
- Empty lanes accept drops.
- Cross-lane moves persist after refresh and appear in the web app.
- Failed moves restore the original lane.
- Move to Status works with VoiceOver and without drag.
- Same-lane drops do not issue a request.

### Roles and failure states

- Owner, Partner, and Planner can perform all mutations.
- Parent and Viewer can browse but see no mutation controls.
- Initial load, refresh, and mutation failures show distinct states.
- Refresh failure retains server-confirmed content.
- Cancellation during tab switching does not show an error.

### Adaptive and accessible UI

- Four tab items remain legible and have 44 pt targets on the narrowest supported iPhone.
- Board lanes peek on iPhone and show multiple readable columns on iPad.
- Editor remains usable with keyboard, large text, and landscape orientation.
- Status and priority remain understandable without color.
- Reduced Motion removes nonessential spring, scale, and rotation effects.

## Live round-trip checklist

Use an authenticated disposable or test member workspace:

1. Create a task in iOS and confirm it appears on the web Tasks board.
2. Edit title, description, due date, owner, and priority in iOS; refresh web and compare values.
3. Move the task across two Board lanes in iOS; confirm each status on web.
4. Mark it Done in List, show completed tasks, and uncomplete it.
5. Clear every nullable editor field and confirm null values survive a fresh iOS load.
6. Delete the test task in iOS and confirm it disappears on web.
7. Repeat a read-only check with a Parent or Viewer membership.

Do not claim production rendering or server behavior is verified until this live round trip is completed.

## Explicit non-goals

- Database or RLS changes.
- Manual card ordering or a task position field.
- Realtime subscriptions, offline persistence, or conflict resolution.
- Local notifications, reminders, recurrence, subtasks, dependencies, tags, or attachments.
- Vendor/event relationship pickers.
- Bulk selection or bulk task edits.
- Widgets, App Intents, Siri, or Calendar integration.
- Changes to the Vowbase web task UI.

## Definition of done

The feature is complete only when:

- The fourth tab, List mode, Board mode, editor, Quick Add, and role-aware behavior are implemented.
- Full CRUD and status movement use the existing native repository layer.
- Nullable clears persist correctly.
- Focused and full tests pass.
- Simulator UI validation covers iPhone and iPad plus accessibility states.
- A live authenticated round trip proves iOS and web operate on the same task rows.
- The final diff contains no unrelated changes and the original checkout's untracked UX files remain untouched.
