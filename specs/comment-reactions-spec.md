# GitReviewPanel Comment Reactions (Command Palette UX)

Add support for reacting to review comments from the GitReviewPanel while preserving existing reply behavior. This feature introduces a constrained emoji reaction set, command + keymap entry points, and a command-palette style picker (`vim.ui.select`) for choosing reactions. Implementation must follow TDD (write failing tests first, then implementation, then refactor).

## TASK-01: Add reaction transport in GitHub API layer
Priority: P1
Files: lua/git-review/github.lua (modify), tests/git_review/reply_spec.lua (modify or split), tests/git_review/github_spec.lua (modify)
Depends on: none
Acceptance: New API function posts a thread reaction via GraphQL; includes validation for thread_id and reaction content; command_error and parse_error paths are covered by tests; tests are added first and fail before implementation.

## TASK-02: Add session action for reacting to selected thread
Priority: P1
Files: lua/git-review/session.lua (modify), tests/git_review/reply_spec.lua (modify), tests/git_review/start_spec.lua (modify if range-mode guard coverage belongs there)
Depends on: TASK-01
Acceptance: Session exposes `react_to_selected_thread` (or equivalent) that resolves selected thread from panel cursor context, prompts/passes selected reaction, forwards transport callback, and blocks in range mode similarly to reply/comment; tests cover success, no-selection context_error, invalid/empty reaction cancellation, and range-mode rejection; tests are written before implementation.

## TASK-03: Add command-palette style reaction picker
Priority: P1
Files: lua/git-review/init.lua (modify), tests/git_review/setup_spec.lua (modify), tests/git_review/reply_spec.lua (modify)
Depends on: TASK-02
Acceptance: New subcommand is available (e.g., `:GitReview react`) and routes through `vim.ui.select` with a compact preset list (at minimum 👍 👎 🔥 ✅ plus 1-2 more such as 👀 ❤️); command exits cleanly if picker is cancelled; picker output maps to API-accepted reaction values; failing tests are created first for dispatcher wiring and picker behavior.

## TASK-04: Add keymap support for reactions
Priority: P2
Files: lua/git-review/config.lua (modify), lua/git-review/init.lua (modify), tests/git_review/setup_spec.lua (modify), README.md (modify)
Depends on: TASK-03
Acceptance: Config gains a normal-mode keymap slot for reaction action (default suffix decided and documented); active keymap registration installs the mapping only in active review mode; disabling/overriding keymap continues to work with existing patterns; tests prove defaults + override/disable behavior; tests are written first.

## TASK-05: Render thread reaction summary in panel
Priority: P2
Files: lua/git-review/ui/panel.lua (modify), tests/git_review/panel_spec.lua (modify)
Depends on: TASK-02
Acceptance: Panel rendering can show a compact reaction summary per thread/comment (format deterministic and non-disruptive to existing body rendering); thread-id line mapping still works for selection across new lines; snapshot/assertion tests confirm rendering output and mapping with reactions present and absent; tests are written first.

## TASK-06: Documentation and regression pass
Priority: P2
Files: README.md (modify), doc/git-review.txt (modify if present), tests/run.lua (verify no harness changes needed)
Depends on: TASK-03, TASK-04, TASK-05
Acceptance: User-facing docs include new command, default keymap, reaction set, and command-palette UX behavior; test suite passes end-to-end with new cases; no regressions in comment/reply workflows.

## TASK-07: TDD quality gate and rollout checklist
Priority: P1
Files: tests/git_review/reply_spec.lua (modify), tests/git_review/setup_spec.lua (modify), tests/git_review/panel_spec.lua (modify), tests/git_review/github_spec.lua (modify)
Depends on: TASK-01, TASK-02, TASK-03, TASK-04, TASK-05
Acceptance: For each implementation task, commit history or PR notes explicitly show red→green progression; all new logic paths have failing-first tests; edge cases include picker cancel, missing panel selection, command transport failure, and range mode; final test run is green.
