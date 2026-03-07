# Commit Range Review Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `:GitReview range` so users can review an explicit commit range accurately using the range end commit as source of truth, without changing their active checkout.

**Architecture:** Introduce a new range-mode session path in `session.start()` that creates an ephemeral worktree at the selected end commit, computes/uses diff and path mapping from that worktree, and marks the session read-only for mutating review actions. Extend dispatcher/completion to expose `range`, and add picker-driven commit selection when refs are omitted.

**Tech Stack:** Lua (Neovim plugin), `vim.ui.select`, `vim.system` via existing `git-review.system`, Busted/MiniTest test harness in `tests/git_review/*`.

---

### Task 1: Add failing tests for dispatcher and command shape

**Files:**
- Modify: `tests/git_review/setup_spec.lua`
- Modify: `tests/git_review/start_spec.lua`

**Step 1: Write the failing tests**

Add tests that assert:

- `:GitReview range` is valid when review is inactive.
- `:GitReview range <start> <end>` forwards both refs into range start path.
- `:GitReview range` with no args enters commit-picker path.

Example sketch:

```lua
set["GitReview range subcommand is accepted when inactive"] = function()
  -- Execute :GitReview range and assert session.start_range or equivalent is invoked.
end
```

**Step 2: Run test to verify it fails**

Run: `nvim --headless -u tests/minimal_init.lua -c "lua require('tests.run').run({ 'tests/git_review/setup_spec.lua' })" -c qa`
Expected: FAIL with unknown subcommand or missing `range` handling.

**Step 3: Write minimal implementation**

Do only enough to register/accept `range` in dispatcher/completion with argument validation.

**Step 4: Run test to verify it passes**

Run: `nvim --headless -u tests/minimal_init.lua -c "lua require('tests.run').run({ 'tests/git_review/setup_spec.lua' })" -c qa`
Expected: PASS for new range-dispatch tests.

**Step 5: Commit**

```bash
git add tests/git_review/setup_spec.lua tests/git_review/start_spec.lua lua/git-review/init.lua
git commit -m "feat: add GitReview range dispatcher entrypoint"
```

### Task 2: Add failing tests for range session context and read-only gating

**Files:**
- Modify: `tests/git_review/start_spec.lua`
- Modify: `tests/git_review/comment_create_spec.lua`
- Modify: `tests/git_review/submit_spec.lua`

**Step 1: Write the failing tests**

Add tests that assert in range mode:

- Session context stores `mode = "range"`, `range_start`, `range_end`, `review_commit_id = range_end`.
- `create_comment` returns unsupported state.
- `reply_to_selected_thread` returns unsupported state.
- `submit_review` returns unsupported state.

Example sketch:

```lua
assert(result.state == "unsupported_in_range_mode")
```

**Step 2: Run test to verify it fails**

Run: `nvim --headless -u tests/minimal_init.lua -c "lua require('tests.run').run({ 'tests/git_review/comment_create_spec.lua', 'tests/git_review/submit_spec.lua', 'tests/git_review/start_spec.lua' })" -c qa`
Expected: FAIL because range mode and unsupported-state gating are not implemented yet.

**Step 3: Write minimal implementation**

Implement only:

- Session context fields.
- Mode checks in comment/reply/submit paths.
- User-facing error message text for range read-only mode.

**Step 4: Run test to verify it passes**

Run: `nvim --headless -u tests/minimal_init.lua -c "lua require('tests.run').run({ 'tests/git_review/comment_create_spec.lua', 'tests/git_review/submit_spec.lua', 'tests/git_review/start_spec.lua' })" -c qa`
Expected: PASS for new range-mode behavior.

**Step 5: Commit**

```bash
git add tests/git_review/start_spec.lua tests/git_review/comment_create_spec.lua tests/git_review/submit_spec.lua lua/git-review/session.lua
git commit -m "feat: add range session context and read-only action gating"
```

### Task 3: Add failing tests for commit picker flow

**Files:**
- Modify: `tests/git_review/start_spec.lua`
- Modify: `lua/git-review/session.lua`

**Step 1: Write the failing tests**

Add tests for `:GitReview range` (no refs) that:

- Stubs commit-list resolver returning current-branch ancestry.
- Stubs two picker interactions (`range_end`, then `range_start`).
- Verifies selected refs are passed into range start internals.

**Step 2: Run test to verify it fails**

Run: `nvim --headless -u tests/minimal_init.lua -c "lua require('tests.run').run({ 'tests/git_review/start_spec.lua' })" -c qa`
Expected: FAIL due to missing picker-driven range selection.

**Step 3: Write minimal implementation**

Implement helpers in session module:

- list branch commits (`git log` on `HEAD` ancestry)
- render picker items (short SHA + subject)
- perform two-step selection with cancellation handling

**Step 4: Run test to verify it passes**

Run: `nvim --headless -u tests/minimal_init.lua -c "lua require('tests.run').run({ 'tests/git_review/start_spec.lua' })" -c qa`
Expected: PASS for commit picker tests.

**Step 5: Commit**

```bash
git add tests/git_review/start_spec.lua lua/git-review/session.lua
git commit -m "feat: add commit picker workflow for GitReview range"
```

### Task 4: Add failing tests for worktree-backed diff execution

**Files:**
- Modify: `tests/git_review/start_spec.lua`
- Modify: `lua/git-review/session.lua`
- Modify: `lua/git-review/system.lua` (only if helper APIs are required)

**Step 1: Write the failing tests**

Add tests that assert range start:

- validates both refs
- creates ephemeral worktree at `range_end`
- executes diff generation in worktree context
- stores `review_repo_root` and `worktree_path`

Use injected `run_command`/filesystem shims where possible to avoid real git writes.

**Step 2: Run test to verify it fails**

Run: `nvim --headless -u tests/minimal_init.lua -c "lua require('tests.run').run({ 'tests/git_review/start_spec.lua' })" -c qa`
Expected: FAIL because worktree lifecycle and context switching are not implemented.

**Step 3: Write minimal implementation**

Implement:

- ref verification helpers
- unique temp worktree path generation
- `git worktree add --detach <path> <range_end>` and diff invocation in that context
- session fields for worktree ownership and repo roots

**Step 4: Run test to verify it passes**

Run: `nvim --headless -u tests/minimal_init.lua -c "lua require('tests.run').run({ 'tests/git_review/start_spec.lua' })" -c qa`
Expected: PASS for worktree-backed range flow.

**Step 5: Commit**

```bash
git add tests/git_review/start_spec.lua lua/git-review/session.lua lua/git-review/system.lua
git commit -m "feat: run range review diff from ephemeral worktree"
```

### Task 5: Add failing tests for cleanup and failure paths

**Files:**
- Modify: `tests/git_review/start_spec.lua`
- Modify: `tests/git_review/errors_spec.lua`
- Modify: `lua/git-review/session.lua`

**Step 1: Write the failing tests**

Add tests that assert:

- `:GitReview stop` removes owned worktree.
- start failures after worktree creation attempt cleanup.
- picker cancel does not activate a session.
- invalid refs report actionable errors.

**Step 2: Run test to verify it fails**

Run: `nvim --headless -u tests/minimal_init.lua -c "lua require('tests.run').run({ 'tests/git_review/start_spec.lua', 'tests/git_review/errors_spec.lua' })" -c qa`
Expected: FAIL because cleanup/failure behavior is incomplete.

**Step 3: Write minimal implementation**

Add teardown helpers and call them in both normal stop and guarded error paths.

**Step 4: Run test to verify it passes**

Run: `nvim --headless -u tests/minimal_init.lua -c "lua require('tests.run').run({ 'tests/git_review/start_spec.lua', 'tests/git_review/errors_spec.lua' })" -c qa`
Expected: PASS for cleanup and error-path tests.

**Step 5: Commit**

```bash
git add tests/git_review/start_spec.lua tests/git_review/errors_spec.lua lua/git-review/session.lua
git commit -m "fix: clean up range review worktrees on stop and errors"
```

### Task 6: Documentation and regression verification

**Files:**
- Modify: `README.md`
- Modify: `doc/git-review.txt`

**Step 1: Write the failing doc-oriented checks**

Define expected docs updates before editing:

- new `:GitReview range` command usage
- read-only behavior in range mode
- picker behavior and explicit-args behavior

**Step 2: Run tests to capture baseline**

Run: `nvim --headless -u tests/minimal_init.lua -c "lua require('tests.run').run()" -c qa`
Expected: current baseline (pass/fail known before docs edits).

**Step 3: Write minimal documentation updates**

Update user docs with concise command semantics and mode caveats.

**Step 4: Run full tests again**

Run: `nvim --headless -u tests/minimal_init.lua -c "lua require('tests.run').run()" -c qa`
Expected: PASS with no regressions.

**Step 5: Commit**

```bash
git add README.md doc/git-review.txt
git commit -m "docs: add GitReview range usage and read-only semantics"
```

### Task 7: Final integration pass

**Files:**
- Modify: `lua/git-review/init.lua`
- Modify: `lua/git-review/session.lua`
- Modify: `tests/git_review/start_spec.lua`

**Step 1: Write final failing integration assertion**

Add one end-to-end-style test that simulates:

- `:GitReview range` picker selections
- session activation
- `:GitReview stop` cleanup

**Step 2: Run focused integration test to verify it fails**

Run: `nvim --headless -u tests/minimal_init.lua -c "lua require('tests.run').run({ 'tests/git_review/start_spec.lua' })" -c qa`
Expected: FAIL until integration edges are complete.

**Step 3: Write minimal integration fixes**

Polish command wiring, status messages, and cleanup ordering only as needed for passing behavior.

**Step 4: Run full suite**

Run: `nvim --headless -u tests/minimal_init.lua -c "lua require('tests.run').run()" -c qa`
Expected: PASS.

**Step 5: Commit**

```bash
git add lua/git-review/init.lua lua/git-review/session.lua tests/git_review/start_spec.lua
git commit -m "feat: complete GitReview range review workflow"
```
