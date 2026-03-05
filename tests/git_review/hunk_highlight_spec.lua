local T = require("mini.test")

local set = T.new_set()

set["hunk_highlight.render_range highlights each line in range"] = function()
  package.loaded["git-review.ui.hunk_highlight"] = nil
  local hunk_highlight = require("git-review.ui.hunk_highlight")

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c", "d", "e" })

  local ok = hunk_highlight.render_range(bufnr, 2, 4)
  assert(ok == true, "Expected render_range to succeed")

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, hunk_highlight.namespace_id(), 0, -1, {})
  assert(#marks == 3, "Expected one highlight extmark per highlighted line")
end

set["hunk_highlight.render_range clears previous highlight state"] = function()
  package.loaded["git-review.ui.hunk_highlight"] = nil
  local hunk_highlight = require("git-review.ui.hunk_highlight")

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c", "d", "e" })

  local first_ok = hunk_highlight.render_range(bufnr, 1, 3)
  assert(first_ok == true, "Expected first render_range to succeed")

  local second_ok = hunk_highlight.render_range(bufnr, 5, 5)
  assert(second_ok == true, "Expected second render_range to succeed")

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, hunk_highlight.namespace_id(), 0, -1, {})
  assert(#marks == 1, "Expected previous range highlights to be cleared")
end

set["hunk_highlight.render_current_hunk no-ops for invalid quickfix item"] = function()
  package.loaded["git-review.ui.hunk_highlight"] = nil
  local hunk_highlight = require("git-review.ui.hunk_highlight")

  local ok = hunk_highlight.render_current_hunk({
    qf_item = {
      filename = "README.md",
      lnum = 0,
      end_lnum = 0,
    },
  })

  assert(ok == false, "Expected invalid quickfix line range to return false")
end

set["hunk_highlight.render_file_hunks highlights all ranges in file"] = function()
  package.loaded["git-review.ui.hunk_highlight"] = nil
  local hunk_highlight = require("git-review.ui.hunk_highlight")

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "1", "2", "3", "4", "5", "6" })

  local ok = hunk_highlight.render_file_hunks({
    bufnr = bufnr,
    ranges = {
      { lnum = 1, end_lnum = 2 },
      { lnum = 5, end_lnum = 6 },
    },
  })

  assert(ok == true, "Expected file hunk rendering to succeed")

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, hunk_highlight.file_hunks_namespace_id(), 0, -1, {})
  assert(#marks == 4, "Expected passive highlights across both ranges")
end

set["hunk_highlight.clear_all_file_hunks clears passive highlights"] = function()
  package.loaded["git-review.ui.hunk_highlight"] = nil
  local hunk_highlight = require("git-review.ui.hunk_highlight")

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "1", "2", "3" })

  hunk_highlight.render_file_hunks({
    bufnr = bufnr,
    ranges = {
      { lnum = 1, end_lnum = 3 },
    },
  })

  hunk_highlight.clear_all_file_hunks()

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, hunk_highlight.file_hunks_namespace_id(), 0, -1, {})
  assert(#marks == 0, "Expected passive file highlights to clear")
end

set["hunk_highlight.clear removes deletion ghost extmarks for buffer"] = function()
  package.loaded["git-review.ui.hunk_highlight"] = nil
  package.loaded["git-review.config"] = nil
  require("git-review").setup({
    deletions = {
      enabled = true,
      max_preview_lines = 3,
      default_expanded = true,
    },
  })

  local hunk_highlight = require("git-review.ui.hunk_highlight")
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "keep", "line" })

  hunk_highlight.render_deletions({
    bufnr = bufnr,
    deleted_blocks = {
      {
        anchor_lnum = 1,
        lines = { "removed" },
      },
    },
  })

  hunk_highlight.clear({ bufnr = bufnr })

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, hunk_highlight.deletion_namespace_id(), 0, -1, {})
  assert(#marks == 0, "Expected deletion ghost extmarks to clear for the buffer")
end

set["hunk_highlight.clear_all_file_hunks clears deletion ghost extmarks"] = function()
  package.loaded["git-review.ui.hunk_highlight"] = nil
  package.loaded["git-review.config"] = nil
  require("git-review").setup({
    deletions = {
      enabled = true,
      max_preview_lines = 3,
      default_expanded = false,
    },
  })

  local hunk_highlight = require("git-review.ui.hunk_highlight")
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "new" })

  hunk_highlight.render_file_hunks({
    bufnr = bufnr,
    ranges = {
      {
        lnum = 1,
        end_lnum = 1,
        deleted_blocks = {
          {
            anchor_lnum = 1,
            lines = { "gone 1", "gone 2" },
          },
        },
      },
    },
  })

  hunk_highlight.clear_all_file_hunks()

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, hunk_highlight.deletion_namespace_id(), 0, -1, {})
  assert(#marks == 0, "Expected deletion ghost extmarks to clear with passive hunk cleanup")
end

set["hunk_highlight.clear with all option clears active highlights after module reload"] = function()
  package.loaded["git-review.ui.hunk_highlight"] = nil
  local first = require("git-review.ui.hunk_highlight")

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c" })
  first.render_range(bufnr, 1, 2)

  package.loaded["git-review.ui.hunk_highlight"] = nil
  local second = require("git-review.ui.hunk_highlight")
  second.clear({ all = true })

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, second.namespace_id(), 0, -1, {})
  assert(#marks == 0, "Expected active highlights to clear even when module state is rebuilt")
end

set["hunk_highlight.clear_all_file_hunks with all option clears passive highlights after module reload"] = function()
  package.loaded["git-review.ui.hunk_highlight"] = nil
  local first = require("git-review.ui.hunk_highlight")

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "1", "2", "3" })
  first.render_file_hunks({
    bufnr = bufnr,
    ranges = {
      { lnum = 1, end_lnum = 3 },
    },
  })

  package.loaded["git-review.ui.hunk_highlight"] = nil
  local second = require("git-review.ui.hunk_highlight")
  second.clear_all_file_hunks({ all = true })

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, second.file_hunks_namespace_id(), 0, -1, {})
  assert(#marks == 0, "Expected passive highlights to clear even when module state is rebuilt")
end

set["hunk_highlight.render_file_hunks uses configured add/change highlight groups"] = function()
  package.loaded["git-review.ui.hunk_highlight"] = nil
  package.loaded["git-review.config"] = nil
  require("git-review").setup({
    highlights = {
      add = "DiffAdd",
      change = "DiffChange",
    },
  })

  local hunk_highlight = require("git-review.ui.hunk_highlight")
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "1", "2", "3", "4" })

  local ok = hunk_highlight.render_file_hunks({
    bufnr = bufnr,
    ranges = {
      {
        lnum = 1,
        end_lnum = 3,
        added_lines = {
          [2] = true,
        },
      },
    },
  })

  assert(ok == true, "Expected file hunk rendering to succeed")

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, hunk_highlight.file_hunks_namespace_id(), 0, -1, { details = true })
  local groups_by_line = {}
  for _, mark in ipairs(marks) do
    local row = mark[2]
    local details = mark[4] or {}
    groups_by_line[row + 1] = details.hl_group
  end

  assert(groups_by_line[1] == "DiffChange", "Expected non-added line to use change highlight")
  assert(groups_by_line[2] == "DiffAdd", "Expected added line to use add highlight")
  assert(groups_by_line[3] == "DiffChange", "Expected non-added line to use change highlight")
end

set["hunk_highlight.render_current_hunk keeps semantic add/change groups"] = function()
  package.loaded["git-review.ui.hunk_highlight"] = nil
  package.loaded["git-review.config"] = nil
  require("git-review").setup({
    highlights = {
      add = "DiffAdd",
      change = "DiffChange",
    },
  })

  local hunk_highlight = require("git-review.ui.hunk_highlight")
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c" })

  local ok = hunk_highlight.render_current_hunk({
    qf_item = {
      bufnr = bufnr,
      lnum = 1,
      end_lnum = 3,
      added_lines = {
        [2] = true,
      },
    },
  })

  assert(ok == true, "Expected current hunk rendering to succeed")

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, hunk_highlight.namespace_id(), 0, -1, { details = true })
  local groups_by_line = {}
  for _, mark in ipairs(marks) do
    local row = mark[2]
    local details = mark[4] or {}
    groups_by_line[row + 1] = details.hl_group
  end

  assert(groups_by_line[1] == "DiffChange", "Expected non-added current line to use change highlight")
  assert(groups_by_line[2] == "DiffAdd", "Expected added current line to use add highlight")
  assert(groups_by_line[3] == "DiffChange", "Expected non-added current line to use change highlight")
end

set["hunk_highlight.render_deletions truncates preview and appends summary"] = function()
  package.loaded["git-review.ui.hunk_highlight"] = nil
  package.loaded["git-review.config"] = nil
  require("git-review").setup({
    highlights = {
      delete = "DiffDelete",
    },
    deletions = {
      enabled = true,
      max_preview_lines = 2,
      default_expanded = false,
    },
  })

  local hunk_highlight = require("git-review.ui.hunk_highlight")
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "keep", "new" })

  local ok = hunk_highlight.render_deletions({
    bufnr = bufnr,
    deleted_blocks = {
      {
        anchor_lnum = 2,
        lines = { "old 1", "old 2", "old 3", "old 4" },
      },
    },
  })

  assert(ok == true, "Expected deletion rendering to succeed")

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, hunk_highlight.deletion_namespace_id(), 0, -1, { details = true })
  assert(#marks == 1, "Expected one deletion ghost extmark")

  local details = marks[1][4] or {}
  local virt_lines = details.virt_lines
  assert(type(virt_lines) == "table", "Expected virtual deletion lines")
  assert(#virt_lines == 3, "Expected two preview lines and one summary line")
  assert(virt_lines[1][1][1] == "- old 1", "Expected first preview deletion line")
  assert(virt_lines[2][1][1] == "- old 2", "Expected second preview deletion line")
  assert(virt_lines[3][1][1] == "... 2 more deleted lines", "Expected truncation summary line")
  assert(virt_lines[1][1][2] == "DiffDelete", "Expected deletion highlight group for preview line")
  assert(virt_lines[3][1][2] == "DiffDelete", "Expected deletion highlight group for summary line")
end

set["hunk_highlight.render_deletions anchors EOF blocks at end of file"] = function()
  package.loaded["git-review.ui.hunk_highlight"] = nil
  package.loaded["git-review.config"] = nil
  require("git-review").setup({
    deletions = {
      enabled = true,
      max_preview_lines = 5,
      default_expanded = true,
    },
  })

  local hunk_highlight = require("git-review.ui.hunk_highlight")
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "keep", "new" })

  local ok = hunk_highlight.render_deletions({
    bufnr = bufnr,
    deleted_blocks = {
      {
        anchor_lnum = 999,
        lines = { "old eof" },
      },
    },
  })

  assert(ok == true, "Expected deletion rendering to succeed")

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, hunk_highlight.deletion_namespace_id(), 0, -1, { details = true })
  assert(#marks == 1, "Expected one deletion ghost extmark")

  local row = marks[1][2]
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  assert(row == line_count, "Expected EOF-anchored deletion block to render at end-of-file row")
end

set["hunk_highlight.toggle_current_block switches preview and full modes"] = function()
  package.loaded["git-review.ui.hunk_highlight"] = nil
  package.loaded["git-review.config"] = nil
  require("git-review").setup({
    deletions = {
      enabled = true,
      max_preview_lines = 1,
      default_expanded = false,
    },
  })

  local hunk_highlight = require("git-review.ui.hunk_highlight")
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "keep", "new" })

  local deleted_blocks = {
    {
      anchor_lnum = 2,
      lines = { "old 1", "old 2", "old 3" },
    },
  }

  hunk_highlight.render_deletions({
    bufnr = bufnr,
    deleted_blocks = deleted_blocks,
  })

  local function line_count()
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, hunk_highlight.deletion_namespace_id(), 0, -1, { details = true })
    local details = marks[1] and marks[1][4] or {}
    local virt_lines = details.virt_lines
    return type(virt_lines) == "table" and #virt_lines or 0
  end

  assert(line_count() == 2, "Expected preview to include one line plus summary")

  local expanded = hunk_highlight.toggle_current_block({
    bufnr = bufnr,
    lnum = 2,
  })
  assert(expanded == true, "Expected toggle to expand current block")
  assert(line_count() == 3, "Expected full mode to render all deleted lines")

  local collapsed = hunk_highlight.toggle_current_block({
    bufnr = bufnr,
    lnum = 2,
  })
  assert(collapsed == false, "Expected second toggle to collapse current block")
  assert(line_count() == 2, "Expected collapsed mode preview after second toggle")
end

set["hunk_highlight.expand_all_blocks and collapse_all_blocks update all blocks"] = function()
  package.loaded["git-review.ui.hunk_highlight"] = nil
  package.loaded["git-review.config"] = nil
  require("git-review").setup({
    deletions = {
      enabled = true,
      max_preview_lines = 1,
      default_expanded = false,
    },
  })

  local hunk_highlight = require("git-review.ui.hunk_highlight")
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c", "d" })

  hunk_highlight.render_deletions({
    bufnr = bufnr,
    deleted_blocks = {
      { anchor_lnum = 2, lines = { "drop 1", "drop 2" } },
      { anchor_lnum = 4, lines = { "drop 3", "drop 4", "drop 5" } },
    },
  })

  local function virt_line_counts()
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, hunk_highlight.deletion_namespace_id(), 0, -1, { details = true })
    local counts = {}
    for _, mark in ipairs(marks) do
      local details = mark[4] or {}
      local virt_lines = details.virt_lines
      table.insert(counts, type(virt_lines) == "table" and #virt_lines or 0)
    end
    table.sort(counts)
    return counts
  end

  local preview_counts = virt_line_counts()
  assert(preview_counts[1] == 2 and preview_counts[2] == 2, "Expected both blocks to be previewed")

  local expanded = hunk_highlight.expand_all_blocks({ bufnr = bufnr })
  assert(expanded == true, "Expected expand_all_blocks to succeed")

  local full_counts = virt_line_counts()
  assert(full_counts[1] == 2 and full_counts[2] == 3, "Expected both blocks to show full deletion lines")

  local collapsed = hunk_highlight.collapse_all_blocks({ bufnr = bufnr })
  assert(collapsed == true, "Expected collapse_all_blocks to succeed")

  local collapsed_counts = virt_line_counts()
  assert(collapsed_counts[1] == 2 and collapsed_counts[2] == 2, "Expected both blocks to return to preview mode")
end

set["hunk_highlight.get_deletion_toggle_mode returns expand when any block is collapsed"] = function()
  package.loaded["git-review.ui.hunk_highlight"] = nil
  package.loaded["git-review.config"] = nil
  require("git-review").setup({
    deletions = {
      enabled = true,
      max_preview_lines = 1,
      default_expanded = false,
    },
  })

  local hunk_highlight = require("git-review.ui.hunk_highlight")
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c" })

  hunk_highlight.render_deletions({
    bufnr = bufnr,
    deleted_blocks = {
      { anchor_lnum = 2, lines = { "drop 1", "drop 2" } },
      { anchor_lnum = 3, lines = { "drop 3" } },
    },
  })

  local mode = hunk_highlight.get_deletion_toggle_mode({ bufnr = bufnr })
  assert(mode == "expand", "Expected toggle mode to expand when blocks are collapsed")
end

set["hunk_highlight.get_deletion_toggle_mode returns collapse when all blocks are expanded"] = function()
  package.loaded["git-review.ui.hunk_highlight"] = nil
  package.loaded["git-review.config"] = nil
  require("git-review").setup({
    deletions = {
      enabled = true,
      max_preview_lines = 1,
      default_expanded = true,
    },
  })

  local hunk_highlight = require("git-review.ui.hunk_highlight")
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b" })

  hunk_highlight.render_deletions({
    bufnr = bufnr,
    deleted_blocks = {
      { anchor_lnum = 1, lines = { "drop 1", "drop 2" } },
    },
  })

  local mode = hunk_highlight.get_deletion_toggle_mode({ bufnr = bufnr })
  assert(mode == "collapse", "Expected toggle mode to collapse when all blocks are expanded")
end

set["hunk_highlight.get_deletion_toggle_mode returns nil without deletion state"] = function()
  package.loaded["git-review.ui.hunk_highlight"] = nil
  local hunk_highlight = require("git-review.ui.hunk_highlight")

  local bufnr = vim.api.nvim_create_buf(false, true)
  local mode = hunk_highlight.get_deletion_toggle_mode({ bufnr = bufnr })
  assert(mode == nil, "Expected nil toggle mode when no deletion state exists")
end

return set
