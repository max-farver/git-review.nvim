# README Consistency and Inactive-Only Range Keymap Design

## Objective

Perform a correctness pass over user-facing documentation and keymap/config behavior, and add a default keybind for range review with strict inactive-state gating.

Approved behavior:

- `<leader>gro` remains the start/stop toggle for both normal and range review sessions.
- `<leader>grO` starts range review using the two-picker flow only when review is inactive.
- `<leader>grO` is removed while review is active (not remapped to stop).

## Scope

1. Align README with actual command and keymap behavior.
2. Align help doc (`doc/git-review.txt`) with README and implementation.
3. Extend config keymap struct for the new range mapping.
4. Wire inactive-only range mapping lifecycle in setup/teardown logic.
5. Update tests for config defaults, keymap lifecycle, and command routing.

## Design

### 1) Config Model

Add a dedicated configurable mapping:

- `keymaps.normal.range` (default: `"O"`)

Adjust default stop behavior:

- `keymaps.normal.stop` default changes from `"O"` to `false`.

Rationale:

- Prevent conflict with the inactive-only range starter.
- Preserve explicit stop support for users who opt in by setting `keymaps.normal.stop` manually.
- Keep built-in defaults consistent with approved behavior (`o` as the only built-in stop path).

Validation:

- Add `keymaps_normal_range` to `vim.validate` using existing `is_keymap_action` predicate.
- Keep `keymaps_normal_stop` validated with same rules to preserve override support.

### 2) Keymap Lifecycle

Inactive registration (`register_default_keymaps`):

- Keep existing `start` map (`<leader>gro`) as always-on toggle.
- Add always-on `range` map (`<leader>grO`) that:
  - checks session state,
  - runs `:GitReview range` only when inactive,
  - no-ops when active (because active lifecycle should remove it).

Active registration (`register_active_keymaps`):

- Call `unregister_default_keymaps()` up front so inactive mappings do not remain in active mode.
- Register active-only mappings from `keymaps.normal` and `keymaps.visual`.
- With default `stop = false`, no active `O` mapping is created by default.

Stop/deactivation:

- `unregister_active_keymaps()` runs on successful stop.
- Then `register_default_keymaps()` restores inactive mappings, including range.

Reconciliation path:

- If session is externally observed inactive via `reconcile_active_keymaps`, active maps are removed and inactive maps are re-registered.

### 3) Commands and Gating

- Dispatcher command gating remains unchanged:
  - inactive: valid subcommands are `start|range`
  - active: valid subcommands exclude `range`
- Range mode remains read-only for comment/reply/submit.

This design only changes keymap exposure and docs; command semantics stay stable.

### 4) Documentation Consistency

Update both:

- `README.md`
- `doc/git-review.txt`

to match implementation exactly for:

- command list and range behavior,
- default keymap table/list,
- config struct defaults including `keymaps.normal.range` and `keymaps.normal.stop = false`,
- active/inactive keymap gating language.

### 5) Test Plan

Update `tests/git_review/setup_spec.lua` to cover:

1. Config defaults
   - `normal.range == "O"`
   - `normal.stop == false`

2. Active-only lifecycle
   - before start: `\gro` and `\grO` exist
   - after start: `\grO` absent (inactive range map removed)
   - after stop: `\grO` restored

3. Routing behavior
   - inactive `\grO` routes to range picker path
   - active `\gro` stops session
   - no active `\grO` mapping by default

4. Validation
   - `keymaps.normal.range` accepts string/false and rejects invalid types/empty string.

## Error Handling

- Keep current actionable notifications for dispatcher/session failures.
- Keymap callbacks should avoid throwing when session module is unavailable.

## Verification

Run:

```bash
lua tests/run.lua
```

Success criteria:

- No regressions in existing start/range lifecycle tests.
- Updated defaults and keymap lifecycle expectations pass.
- README/help/config behavior remains consistent.
