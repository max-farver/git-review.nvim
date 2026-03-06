# git-review.nvim

`git-review.nvim` is a Neovim plugin for pull-request review using your local checkout.
It builds a quickfix list of changed files plus a location list of hunks for the selected file,
keeps review navigation in normal file buffers,
and uses GitHub CLI (`gh`) for thread lookup and comment/reply actions.

## Requirements

- Neovim 0.9+
- `git`
- `gh` with an authenticated session (`gh auth status`)

## Install

Install with your plugin manager, then load it on demand or at startup.

`lazy.nvim`:

```lua
{
  "max-farver/git-review.nvim",
}
```

`mini.deps`:

```lua
local add = MiniDeps.add

add({ source = "max-farver/git-review.nvim" })

require("git-review").setup({})
```

`vim.pack` (Neovim 0.12+):

```lua
vim.pack.add({ "https://github.com/max-farver/git-review.nvim" })

require("git-review").setup({})
```

The plugin bootstrap auto-registers commands during startup.

## Usage

Run `:GitReview <subcommand>` from a branch that has a pull request:

- `:GitReview start` - open a file picker for changed files, seed the current window location list with hunks after selection (using startup-cached hunk data when available), keep comments panel closed by default, and enable hunk highlights in file buffers.
- `:GitReview range` - open a two-step commit picker (end first, then start) and start a commit-range review session for `start...end` (available when review is inactive, like `:GitReview start`).
- `:GitReview range <start> <end>` - start a commit-range review session directly for `start...end`.
- `:GitReview files` - populate the review quickfix list with changed files without opening the window.
- `:GitReview refresh` - recompute hunks and refresh panel/thread state.
- `:GitReview panel` - toggle the comments panel scoped to the current buffer path; renders cached comments immediately and refreshes comments in the background.
- `:GitReview panel-all` - toggle the comments panel with all review threads.
- `:GitReview toggle-resolved` - toggle resolved-thread body visibility in the comments panel.
- `:GitReview toggle-deletion-block` - toggle the deleted-lines ghost block nearest the cursor between preview and full modes.
- `:GitReview toggle-deletions` - toggle all deleted-lines ghost blocks in the current buffer between preview and full modes.
- `:GitReview expand-deletion-blocks` - expand all deleted-lines ghost blocks in the current buffer to full mode.
- `:GitReview collapse-deletion-blocks` - collapse all deleted-lines ghost blocks in the current buffer to preview mode.
- `:GitReview info` - open the PR info page for the current branch pull request.
- `:GitReview comment` - create a review comment for cursor line or visual range.
- `:GitReview reply` - reply to the currently selected review thread.
- `:GitReview react` - add a reaction to the currently selected review thread via a command-palette picker (`vim.ui.select`).
- `:GitReview submit` - submit a review; prompts for `APPROVE` or `REQUEST_CHANGES`, then an optional message body.
- `:GitReview stop` - stop review mode, clear active/passive/deletion highlights, and clear review quickfix and review hunk location list items.

Range sessions are read-only: mutating actions (`:GitReview comment`, `:GitReview reply`, `:GitReview react`, and `:GitReview submit`) are rejected in range mode.

While review mode is active, use location list (`:lnext` / `:lprev`) to move between
hunks in the selected file. Run `:GitReview files` when you want quickfix navigation,
then use quickfix (`:cnext` / `:cprev`) to move between files.
Changed lines are highlighted with diff-semantic groups in file buffers (`DiffAdd` for added lines and `DiffChange` for other changed lines by default).
Deleted lines are shown as virtual ghost blocks above anchor lines. In preview mode blocks show up to `deletions.max_preview_lines` plus a summary line; full mode shows every deleted line.

`:GitReview panel` is optimized for markdown comment/reply workflows, while `:GitReview info`
shows PR metadata and description in a dedicated info page.
When panel comments refresh in the background, git-review.nvim notifies with
`GitReview: fetching comments...` so users know data is being updated.

The comments panel normalizes common embedded HTML from bot and CI comments into
readable markdown-like text (for example links, inline/code blocks, emphasis,
quotes, lists, and line breaks). Thread headings include comment count and
resolved status, and multi-comment threads use a visible `> ---` separator to
improve scanning in dense reviews. Reaction summaries are rendered compactly per
comment (for example `> Reactions: 👍 2  ❤️ 1`). Paragraph tags are normalized to
paragraph breaks so nested links render correctly, and HTML comment blocks are
folded to `[HTML comment hidden]` placeholders. Resolved thread bodies are
collapsed by default; use `:GitReview toggle-resolved` to toggle them in the
panel.

Typical flow:

1. `:GitReview start`
2. Pick a file from the picker to seed the hunk loclist
3. Jump between hunks with `:lnext` / `:lprev`
4. Optional: run `:GitReview files` then `:cnext` / `:cprev` to move between files
5. Optional: use `:GitReview toggle-deletion-block`, `:GitReview toggle-deletions`, `:GitReview expand-deletion-blocks`, or `:GitReview collapse-deletion-blocks` to switch deleted-lines blocks between preview/full rendering
6. Use `:GitReview comment` on changed lines
7. Select a thread in the panel and run `:GitReview reply`
8. Optional: run `:GitReview react` to add a quick emoji reaction from the picker
9. Optional: run `:GitReview submit` to approve or request changes (with an optional message)
10. Run `:GitReview stop` when done reviewing

Default keybinds (`keymaps.enabled = true`) use the prefix `<leader>gr`:

| Mode | Key | Action |
| --- | --- | --- |
| Normal | `o` | Toggle review start/stop (`:GitReview start` when inactive, `:GitReview stop` when active) |
| Normal | `O` | `:GitReview range` (inactive only; mapping is removed while review is active) |
| Normal | `s` | `:GitReview submit` |
| Normal | `r` | `:GitReview refresh` |
| Normal | `f` | `:GitReview files` |
| Normal | `p` | Toggle panel for current buffer comments |
| Normal | `P` | Toggle panel for all comments |
| Normal | `i` | `:GitReview info` |
| Normal | `c` | Context-aware action: reply in the panel when a thread is selected; otherwise prompt for a new comment |
| Normal | `e` | `:GitReview react` (reaction picker for selected thread) |
| Normal | `t` | `:GitReview toggle-resolved` |
| Normal | `b` | Toggle the nearest deleted-lines ghost block in the current buffer |
| Normal | `d` | Toggle deleted-lines ghost blocks buffer-wide between preview/full |
| Visual | `c` | `:GitReview comment` for the selected range |

## Configuration

`setup()` supports startup panel behavior toggles:

- `open_pr_info_on_start` (default: `false`) - open the PR info page automatically when `:GitReview start` runs.
- `open_comments_panel_on_start` (default: `false`) - open the comments panel automatically when `:GitReview start` runs.
- `highlights.add` (default: `"DiffAdd"`) - highlight group for added diff lines.
- `highlights.change` (default: `"DiffChange"`) - highlight group for changed (non-added) diff lines.
- `highlights.delete` (default: `"DiffDelete"`) - highlight group for deleted-line ghost blocks.
- `deletions.enabled` (default: `true`) - enable deleted-line ghost block rendering.
- `deletions.max_preview_lines` (default: `6`) - number of deleted lines shown per block in preview mode.
- `deletions.default_expanded` (default: `false`) - start each deleted block in full mode instead of preview mode.
- `keymaps.enabled` (default: `true`) - register built-in keymaps.
- `keymaps.prefix` (default: `"<leader>gr"`) - prefix prepended to each action suffix.
- `keymaps.normal` action suffixes (defaults):
  - `start = "o"`, `stop = false`, `range = "O"`, `submit = "s"`, `refresh = "r"`, `files = "f"`, `panel = "p"`, `panel_all = "P"`, `info = "i"`
  - `action = "c"` (context-aware: reply in panel on selected thread, comment otherwise)
  - `react = "e"` (opens a picker with: 👍 👎 🔥 ✅ 👀 ❤️)
  - `toggle_resolved = "t"`, `toggle_deletion_block = "b"` (nearest block), `toggle_deletions = "d"` (buffer-wide toggle)
- `keymaps.visual` action suffixes (defaults):
  - `comment = "c"`

In range mode, review sessions are read-only regardless of keymap configuration (`comment`, `reply`, `react`, and `submit` are rejected).

Example:

```lua
require("git-review").setup({
  highlights = {
    add = "DiffAdd",
    change = "DiffChange",
    delete = "DiffDelete",
  },
  deletions = {
    enabled = true,
    max_preview_lines = 6,
    default_expanded = false,
  },
  keymaps = {
    enabled = true,
    prefix = "<leader>gr",
    normal = {
      start = "o",
      stop = false,
      range = "O",
      submit = "s",
      refresh = "r",
      files = "f",
      panel = "p",
      panel_all = "P",
      info = "i",
      action = "c",
      react = "e",
      toggle_resolved = "t",
      toggle_deletion_block = "b",
      toggle_deletions = "d",
    },
    visual = {
      comment = "c",
    },
  },
})
```

Disable all default mappings (opt-out):

```lua
require("git-review").setup({
  keymaps = {
    enabled = false,
  },
})
```

Override one action and disable another:

```lua
require("git-review").setup({
  keymaps = {
    normal = {
      action = "a", -- use <leader>gra for context-aware comment/reply
      panel = false, -- disable the panel mapping
    },
  },
})
```

## Help

After install, run `:help git-review` for command details.
