# README and Inactive-Only Range Keymap Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make docs accurate for commands/keymaps/config, and add `<leader>grO` as an inactive-only range review keybind while keeping `<leader>gro` as the only built-in stop toggle.

**Architecture:** Extend keymap config with a dedicated `normal.range` suffix and make the inactive keymap lifecycle explicit: default mappings exist only when no review is active, active mappings replace them during sessions, and inactive mappings are restored when sessions end. Keep dispatcher command behavior unchanged and update docs/tests to match runtime behavior exactly.

**Tech Stack:** Lua (Neovim plugin), Neovim keymap APIs (`vim.keymap.set`, `vim.keymap.del`, `vim.fn.maparg`), MiniTest test suite (`tests/git_review/*.lua`).

---

### Task 1: Add config support for `keymaps.normal.range` and new defaults

**Files:**
- Modify: `lua/git-review/config.lua`
- Test: `tests/git_review/setup_spec.lua`

**Step 1: Write the failing test**

In `tests/git_review/setup_spec.lua`, extend default config assertions to require:

```lua
assert(cfg.keymaps.normal.range == "O", "Expected default normal mode range key")
assert(cfg.keymaps.normal.stop == false, "Expected default normal mode stop key to be disabled")
```

Add validation tests for `keymaps.normal.range`:

```lua
local ok, err = pcall(require("git-review").setup, { keymaps = { normal = { range = "" } } })
assert(ok == false)
assert(string.find(err, "keymaps_normal_range", 1, true))
```

**Step 2: Run test to verify it fails**

Run: `nvim --headless -u tests/minimal_init.lua -c "lua require('tests.run').run({ 'tests/git_review/setup_spec.lua' })" -c qa`
Expected: FAIL due to missing `normal.range` default/validation and old `normal.stop` default.

**Step 3: Write minimal implementation**

In `lua/git-review/config.lua`:

- Add default `keymaps.normal.range = "O"`
- Change default `keymaps.normal.stop = false`
- Add `keymaps_normal_range` validation using `is_keymap_action`

Example shape:

```lua
normal = {
  start = "o",
  stop = false,
  range = "O",
  ...
}
```

**Step 4: Run test to verify it passes**

Run: `nvim --headless -u tests/minimal_init.lua -c "lua require('tests.run').run({ 'tests/git_review/setup_spec.lua' })" -c qa`
Expected: PASS for updated config defaults and validation.

**Step 5: Commit**

```bash
git add lua/git-review/config.lua tests/git_review/setup_spec.lua
git commit -m "feat: add inactive-only range keymap config defaults"
```

### Task 2: Implement inactive-only `range` keymap lifecycle

**Files:**
- Modify: `lua/git-review/init.lua`
- Test: `tests/git_review/setup_spec.lua`

**Step 1: Write the failing test**

In lifecycle tests, assert:

- before start: `\\gro` exists and `\\grO` exists
- after start: `\\grO` is absent
- after stop: `\\grO` exists again

Add explicit routing expectations:

```lua
-- inactive: press \grO -> session.start_range_picker called
-- active:   press \gro -> session.stop called
-- active:   \grO mapcheck/maparg empty
```

**Step 2: Run test to verify it fails**

Run: `nvim --headless -u tests/minimal_init.lua -c "lua require('tests.run').run({ 'tests/git_review/setup_spec.lua' })" -c qa`
Expected: FAIL because `\grO` is currently active stop mapping.

**Step 3: Write minimal implementation**

In `lua/git-review/init.lua`:

- Add inactive default mapping for `normal.range` in `register_default_keymaps`
- Ensure inactive mappings are removed when active mappings register
- Ensure inactive mappings are restored after stop/reconcile
- Keep `<leader>gro` start/stop toggle behavior unchanged
- Keep active mapping registration for `normal.stop` optional (default false means no active `O`)

**Step 4: Run test to verify it passes**

Run: `nvim --headless -u tests/minimal_init.lua -c "lua require('tests.run').run({ 'tests/git_review/setup_spec.lua' })" -c qa`
Expected: PASS for lifecycle/routing changes.

**Step 5: Commit**

```bash
git add lua/git-review/init.lua tests/git_review/setup_spec.lua
git commit -m "feat: make range keymap inactive-only and keep o as stop toggle"
```

### Task 3: Update README and help docs to match behavior

**Files:**
- Modify: `README.md`
- Modify: `doc/git-review.txt`

**Step 1: Write failing doc checklist**

Define expected documentation state:

- Keymaps section documents:
  - `o` start/stop toggle
  - `O` range start when inactive only
- Config section includes:
  - `keymaps.normal.range = "O"`
  - `keymaps.normal.stop = false`
- Command docs keep `range` inactive-only command semantics.

**Step 2: Run baseline tests before docs edits**

Run: `nvim --headless -u tests/minimal_init.lua -c "lua require('tests.run').run({ 'tests/git_review/setup_spec.lua' })" -c qa`
Expected: PASS baseline from Task 2.

**Step 3: Write minimal documentation updates**

Edit both docs to remove stale stop-on-`O` default language and add inactive-only range key language.

**Step 4: Run tests to ensure no regressions**

Run: `nvim --headless -u tests/minimal_init.lua -c "lua require('tests.run').run({ 'tests/git_review/setup_spec.lua', 'tests/git_review/start_spec.lua' })" -c qa`
Expected: PASS.

**Step 5: Commit**

```bash
git add README.md doc/git-review.txt
git commit -m "docs: align keymap and config docs with inactive-only range binding"
```

### Task 4: Full regression and final integration check

**Files:**
- Modify: `tests/git_review/setup_spec.lua` (only if failures reveal missing coverage)
- Modify: `lua/git-review/init.lua` (only if integration fixes needed)

**Step 1: Add one final failing integration assertion (if needed)**

If gaps remain, add one test that runs this sequence:

1. inactive `\grO` starts range picker path
2. active state reached
3. `\grO` absent
4. `\gro` stops
5. `\grO` restored

**Step 2: Run full suite**

Run: `nvim --headless -u tests/minimal_init.lua -c "lua require('tests.run').run()" -c qa`
Expected: PASS.

**Step 3: Apply minimal fixes only if required**

Keep changes limited to lifecycle edge cases or test fragility.

**Step 4: Run full suite again**

Run: `nvim --headless -u tests/minimal_init.lua -c "lua require('tests.run').run()" -c qa`
Expected: PASS with stable behavior.

**Step 5: Commit**

```bash
git add lua/git-review/init.lua tests/git_review/setup_spec.lua
git commit -m "test: lock inactive-only range keymap lifecycle behavior"
```
