local M = {}

local function is_positive_integer(value)
  return type(value) == "number" and value > 0 and value % 1 == 0
end

local function is_keymap_action(value)
  return (type(value) == "string" and value ~= "") or value == false
end

M.defaults = {
  open_comments_panel_on_start = false,
  open_pr_info_on_start = false,
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
      toggle_resolved = "t",
      toggle_deletion_block = "b",
      toggle_deletions = "d",
    },
    visual = {
      comment = "c",
    },
  },
}

local values = vim.deepcopy(M.defaults)

function M.setup(opts)
  opts = opts or {}
  local keymaps = opts.keymaps
  local keymaps_normal = keymaps and keymaps.normal
  local keymaps_visual = keymaps and keymaps.visual

  vim.validate({
    opts = { opts, "table" },
    open_comments_panel_on_start = { opts.open_comments_panel_on_start, "boolean", true },
    open_pr_info_on_start = { opts.open_pr_info_on_start, "boolean", true },
    highlights = { opts.highlights, "table", true },
    highlights_add = { opts.highlights and opts.highlights.add, "string", true },
    highlights_change = { opts.highlights and opts.highlights.change, "string", true },
    highlights_delete = { opts.highlights and opts.highlights.delete, "string", true },
    deletions = { opts.deletions, "table", true },
    deletions_enabled = { opts.deletions and opts.deletions.enabled, "boolean", true },
    deletions_max_preview_lines = { opts.deletions and opts.deletions.max_preview_lines, is_positive_integer, true },
    deletions_default_expanded = { opts.deletions and opts.deletions.default_expanded, "boolean", true },
    keymaps = { keymaps, "table", true },
    keymaps_enabled = { keymaps and keymaps.enabled, "boolean", true },
    keymaps_prefix = { keymaps and keymaps.prefix, "string", true },
    keymaps_normal = { keymaps_normal, "table", true },
    keymaps_visual = { keymaps_visual, "table", true },
    keymaps_normal_start = { type(keymaps_normal) == "table" and keymaps_normal.start, is_keymap_action, true },
    keymaps_normal_stop = { type(keymaps_normal) == "table" and keymaps_normal.stop, is_keymap_action, true },
    keymaps_normal_range = { type(keymaps_normal) == "table" and keymaps_normal.range, is_keymap_action, true },
    keymaps_normal_submit = { type(keymaps_normal) == "table" and keymaps_normal.submit, is_keymap_action, true },
    keymaps_normal_refresh = { type(keymaps_normal) == "table" and keymaps_normal.refresh, is_keymap_action, true },
    keymaps_normal_files = { type(keymaps_normal) == "table" and keymaps_normal.files, is_keymap_action, true },
    keymaps_normal_panel = { type(keymaps_normal) == "table" and keymaps_normal.panel, is_keymap_action, true },
    keymaps_normal_panel_all = { type(keymaps_normal) == "table" and keymaps_normal.panel_all, is_keymap_action, true },
    keymaps_normal_info = { type(keymaps_normal) == "table" and keymaps_normal.info, is_keymap_action, true },
    keymaps_normal_action = { type(keymaps_normal) == "table" and keymaps_normal.action, is_keymap_action, true },
    keymaps_normal_toggle_resolved = { type(keymaps_normal) == "table" and keymaps_normal.toggle_resolved, is_keymap_action, true },
    keymaps_normal_toggle_deletion_block = {
      type(keymaps_normal) == "table" and keymaps_normal.toggle_deletion_block,
      is_keymap_action,
      true,
    },
    keymaps_normal_toggle_deletions = {
      type(keymaps_normal) == "table" and keymaps_normal.toggle_deletions,
      is_keymap_action,
      true,
    },
    keymaps_visual_comment = { type(keymaps_visual) == "table" and keymaps_visual.comment, is_keymap_action, true },
  })

  values = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
end

function M.get()
  return vim.deepcopy(values)
end

function M.get_open_comments_panel_on_start()
  return values.open_comments_panel_on_start == true
end

function M.get_open_pr_info_on_start()
  return values.open_pr_info_on_start == true
end

return M
