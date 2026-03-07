# Review Progress Tracking Behavior Contract (v1)

## Objective

Define exact behavior for file-level review progress before implementation.

This contract covers:
- Local file reviewed/unreviewed tracking
- Active commands (`mark-reviewed`, `next-unreviewed`, `progress`)
- Quickfix status rendering (`[x]` / `[ ]`)
- Lifecycle rules (`start`, `refresh`, `stop`)
- Optional GitHub viewed/unviewed sync boundaries

## Approved Scope (v1)

- Granularity: **file-only** (not per-hunk)
- Commands:
  - `:GitReview mark-reviewed` (toggle)
  - `:GitReview next-unreviewed`
  - `:GitReview progress`
- UX:
  - On `next-unreviewed` completion: **stop and notify** (no wrap)
  - Status shown in **quickfix** and **notifications**
- Sync:
  - Local-first behavior always
  - Optional GitHub sync for viewed/unviewed on toggle when possible

## Non-Goals (v1)

- Persistent progress across Neovim restarts
- Hunk-level progress
- New keymaps (command-first delivery)
- Panel UI changes for progress

## Core Data Model

Session owns progress state:
- `reviewed_files` (set/map keyed by normalized absolute file path)
- `review_files_order` (deterministic ordered list derived from review file quickfix items)

Definitions:
- **Review file universe**: unique file list from parsed review hunks.
- A file is **reviewed** iff `reviewed_files[path] == true`.

## Current File Resolution Order

For `mark-reviewed` target resolution:
1. selected entry from the active review quickfix list (if available)
2. current buffer path

If resolved path is not in review file universe, return:
- `{ state = "context_error", message = "Current file is not part of the active review." }`

## Command Contracts

### 1) `:GitReview mark-reviewed`

Semantics:
- Toggle reviewed state for resolved current file.
- If unreviewed -> reviewed.
- If reviewed -> unreviewed.

Session API return contract:
- success:
  - `{ state = "ok", path = <abs_path>, reviewed = <boolean>, synced = <boolean|nil> }`
- no active session:
  - `{ state = "context_error", message = "No active review session. Run :GitReview start first." }`
- no valid current file context:
  - `{ state = "context_error", message = "Current file is not part of the active review." }`

Side effects:
- Re-render review quickfix entries with updated `[x]/[ ]` marker.
- Emit user notification from dispatcher/session message layer.

### 2) `:GitReview next-unreviewed`

Semantics:
- Move to next unreviewed file in `review_files_order`, starting after current file index.
- Opens target file and synchronizes hunk loclist using existing session flow.
- No wrap.

Completion behavior:
- If no remaining unreviewed files:
  - returns `{ state = "ok", done = true }`
  - notify user: "GitReview: all files reviewed"

Success behavior:
- `{ state = "ok", done = false, path = <abs_path> }`

Errors:
- no active session -> existing context_error contract
- no review files available -> context_error with explicit message

### 3) `:GitReview progress`

Semantics:
- Compute and report file progress summary.

Return shape:
- `{ state = "ok", reviewed = <n>, total = <n>, remaining = <n> }`

Notification format:
- `GitReview: Reviewed <reviewed>/<total> files (<remaining> remaining)`

## Quickfix Rendering Contract

Review quickfix entries should render with deterministic status prefix:
- reviewed: `[x] `
- unreviewed: `[ ] `

Rules:
- Prefix is applied only to git-review managed review quickfix entries.
- Preserve navigation semantics and item ordering.
- Preserve filename/lnum identity used by existing loclist sync.

## Lifecycle Contract

### `start`
- Initialize empty `reviewed_files`.
- Build `review_files_order` from current review hunks.
- Initial quickfix status should be `[ ]` for all files once files quickfix is populated.

### `refresh`
- Preserve `reviewed_files` for files that still exist in refreshed review universe.
- Drop reviewed entries for files no longer present.
- Recompute `review_files_order` from refreshed hunks.
- Re-render quickfix markers for current review list if present.

### `stop`
- Clear all progress state with session teardown.

## Read-only Modes Contract

`range` / `local` / `branch` modes:
- Progress commands are **allowed** (local state only).
- Optional GitHub sync is **disabled/skipped** in these modes.

Rationale:
- Progress tracking is local navigation aid, not a PR mutation requirement.

## Optional GitHub Sync Contract

Feature flag (default false):
- `progress.github_sync = false`

When enabled and PR context is resolvable:
- On toggle to reviewed -> call GitHub "mark file viewed"
- On toggle to unreviewed -> call GitHub "unmark file viewed"

If sync cannot run (missing PR node id/path/capability) or fails:
- Local toggle still succeeds
- Return success with sync metadata (or warning path) and notify non-fatal sync failure
- Must not roll back local reviewed state

## Dispatcher / Completion Contract

Active subcommands gain:
- `mark-reviewed`
- `next-unreviewed`
- `progress`

Inactive subcommands remain unchanged.
Completion must reflect this active/inactive split.

## Acceptance Checklist for This Contract

- [x] Toggle semantics are explicit
- [x] Current-file resolution precedence is explicit
- [x] Non-wrapping next-unreviewed behavior is explicit
- [x] Progress summary schema/message is explicit
- [x] Quickfix marker behavior is explicit
- [x] Lifecycle behavior is explicit
- [x] Optional sync behavior + failure semantics are explicit
