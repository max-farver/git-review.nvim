# Commit Range Review Design

## Goal

Add a range-review workflow that lets users inspect a chosen commit range with accurate hunks and file mapping, without changing their active checkout. The range end commit is the source of truth.

## Scope

In scope:

- New `:GitReview range` entrypoint.
- Commit picker UI when invoked without explicit refs.
- Read-only range sessions (navigation, files, hunks, panel viewing).
- Diff/hunk parsing rooted at range end commit via ephemeral worktree.

Out of scope for this iteration:

- Creating comments/replies/submitting reviews in range mode.
- Cross-repo or cross-remote range selection UX.

## User Experience

### Commands

- `:GitReview range` opens a two-step picker to select commits.
- `:GitReview range <start> <end>` starts range review directly.

### Commit Selection UI

Default commit universe: current branch ancestry (reachable from `HEAD`).

Two-step flow:

1. Select `range_end` first from recent branch commits.
2. Select `range_start` from valid commits not newer than `range_end`.

Picker labels should include short SHA and subject (optionally relative time).

Defaults:

- `range_end`: `HEAD`.
- `range_start`: parent of selected end when available.

### Session Mode Behavior

Range mode is read-only by default:

- Enabled: `start/range`, picker, files quickfix, hunk loclist, highlights, panel viewing.
- Disabled: `comment`, `reply`, `submit` with explicit user-facing error message.

UI should make mode obvious (for example quickfix/loclist title containing `Range Review`).

## Technical Design

## 1) Session Context

Extend session state with a review context:

- `mode`: `"pr"` or `"range"`
- `range_start`: commit-ish for range start
- `range_end`: commit-ish for range end
- `review_commit_id`: canonical commit for mapping (`range_end` in range mode)
- `source_repo_root`: user working tree root
- `review_repo_root`: root used for diff/path mapping (worktree root in range mode)
- `worktree_path`: temp worktree path when applicable
- `worktree_owned`: boolean controlling cleanup

Existing non-range behavior remains unchanged and continues to use the current flow.

## 2) Range Diff Source of Truth

For range mode:

- Validate refs with `git rev-parse --verify`.
- Create an ephemeral worktree at `range_end`.
- Run `git diff --no-color <start>...<end>` from the worktree context.
- Parse hunks exactly as current code does, but with `review_repo_root` from worktree.
- Set `review_commit_id = range_end`.

This ensures diff text, line mapping, and commit identity all align to the same snapshot.

## 3) Worktree Lifecycle

Start path:

1. Resolve and validate commits.
2. Create temp worktree directory.
3. Add worktree at `range_end` (detached).
4. Generate diff and initialize session.

Stop/error cleanup:

- On `:GitReview stop`, remove owned worktree.
- On start failure after worktree creation, remove it before returning error.
- If cleanup fails, warn and continue shutdown without crashing.

Safety requirement: never switch branches in the user's active checkout.

## 4) Command and Dispatcher Changes

Add `range` as a dispatcher subcommand while preserving existing active/inactive command gating.

Behavior:

- `:GitReview start` -> existing PR/upstream flow.
- `:GitReview range` -> picker-driven range flow.
- `:GitReview range <start> <end>` -> explicit range flow.

Range mode should be detectable by command handlers so unsupported mutating actions can fail fast with clear messages.

## 5) Action Gating in Range Mode

When `mode == "range"`:

- `create_comment` returns `unsupported_in_range_mode`.
- `reply_to_selected_thread` returns `unsupported_in_range_mode`.
- `submit_review` returns `unsupported_in_range_mode`.

Error messages should explain this is read-only range review.

## 6) Validation Rules

- Both refs must resolve.
- Selected ordering must be valid (`range_start` not newer than `range_end`).
- Support single-commit convenience by translating to parent/start semantics if needed during planning (for example `end^..end`).

## Error Handling

- Invalid ref: include the bad ref in the message.
- Empty diff: allow session start with no hunks, consistent with existing empty-state UX.
- Worktree create/remove failures: actionable messages, no hard crash.
- Picker cancel: return gracefully without activating session.

## Test Plan

Add/extend tests around session and dispatcher behavior:

- Range start sets `mode = "range"` and `review_commit_id = range_end`.
- Range diff command executes from worktree path.
- Stop removes `worktree_owned` path.
- Mutating actions in range mode return deterministic unsupported state.
- Picker-based `:GitReview range` selects commits and initializes session.
- Existing `:GitReview start` tests remain unchanged and passing.

## Rollout Notes

- This is additive and backward compatible.
- Default behavior remains PR review via `:GitReview start`.
- Range mode intentionally prioritizes diff accuracy and workspace safety over full PR mutation actions.
