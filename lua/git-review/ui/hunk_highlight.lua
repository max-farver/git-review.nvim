local M = {}

local namespace = vim.api.nvim_create_namespace("git-review-hunks")
local file_hunks_namespace = vim.api.nvim_create_namespace("git-review-file-hunks")
local deletion_namespace = vim.api.nvim_create_namespace("git-review-deletions")
local state = {
  bufnr = nil,
  file_hunk_bufnrs = {},
  deletion_bufnrs = {},
  deletion_blocks_by_bufnr = {},
}

local function clear_namespace_in_buffer(bufnr, ns_id)
  if type(bufnr) ~= "number" or bufnr <= 0 or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  return true
end

local function clear_namespace_in_all_buffers(ns_id)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    clear_namespace_in_buffer(bufnr, ns_id)
  end
end

local function resolve_highlight_groups()
  local ok, config = pcall(require, "git-review.config")
  if not ok or type(config) ~= "table" or type(config.get) ~= "function" then
    return {
      add = "DiffAdd",
      change = "DiffChange",
      delete = "DiffDelete",
    }
  end

  local values = config.get()
  local highlights = type(values) == "table" and values.highlights or nil
  local add = type(highlights) == "table" and highlights.add or nil
  local change = type(highlights) == "table" and highlights.change or nil
  local delete = type(highlights) == "table" and highlights.delete or nil
  return {
    add = type(add) == "string" and add ~= "" and add or "DiffAdd",
    change = type(change) == "string" and change ~= "" and change or "DiffChange",
    delete = type(delete) == "string" and delete ~= "" and delete or "DiffDelete",
  }
end

local function resolve_deletion_settings()
  local defaults = {
    enabled = true,
    max_preview_lines = 6,
    default_expanded = false,
  }

  local ok, config = pcall(require, "git-review.config")
  if not ok or type(config) ~= "table" or type(config.get) ~= "function" then
    return defaults
  end

  local values = config.get()
  local deletions = type(values) == "table" and values.deletions or nil
  local enabled = type(deletions) == "table" and deletions.enabled or nil
  local max_preview_lines = type(deletions) == "table" and deletions.max_preview_lines or nil
  local default_expanded = type(deletions) == "table" and deletions.default_expanded or nil

  return {
    enabled = enabled ~= false,
    max_preview_lines = type(max_preview_lines) == "number" and max_preview_lines > 0 and max_preview_lines or 6,
    default_expanded = default_expanded == true,
  }
end

local function resolve_line_highlight_group(line, added_lines, groups)
  if type(added_lines) == "table" and added_lines[line] == true then
    return groups.add
  end

  return groups.change
end

local function resolve_target_bufnr(qf_item)
  if type(qf_item.bufnr) == "number" and qf_item.bufnr > 0 and vim.api.nvim_buf_is_valid(qf_item.bufnr) then
    return qf_item.bufnr
  end

  if type(qf_item.filename) ~= "string" or qf_item.filename == "" then
    return nil
  end

  local bufnr = vim.fn.bufnr(qf_item.filename)
  if bufnr < 0 then
    bufnr = vim.fn.bufadd(qf_item.filename)
  end

  if type(bufnr) ~= "number" or bufnr <= 0 or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  pcall(vim.fn.bufload, bufnr)
  return bufnr
end

local function normalize_deleted_blocks(deleted_blocks, default_expanded)
  if type(deleted_blocks) ~= "table" then
    return {}
  end

  local normalized = {}
  for _, block in ipairs(deleted_blocks) do
    if type(block) == "table" then
      local anchor_lnum = block.anchor_lnum
      local lines = block.lines
      if type(anchor_lnum) == "number" and anchor_lnum > 0 and type(lines) == "table" then
        local normalized_lines = {}
        for _, line in ipairs(lines) do
          if type(line) == "string" then
            table.insert(normalized_lines, line)
          end
        end

        if #normalized_lines > 0 then
          table.insert(normalized, {
            anchor_lnum = math.floor(anchor_lnum),
            lines = normalized_lines,
            expanded = block.expanded == true or (block.expanded == nil and default_expanded == true),
          })
        end
      end
    end
  end

  return normalized
end

local function build_virtual_lines(block, opts)
  local display_lines = {}
  local line_count = #block.lines
  local max_preview_lines = opts.max_preview_lines
  local hl_group = opts.hl_group

  if block.expanded == true or line_count <= max_preview_lines then
    for _, line in ipairs(block.lines) do
      table.insert(display_lines, { { "- " .. line, hl_group } })
    end
    return display_lines
  end

  for i = 1, max_preview_lines do
    table.insert(display_lines, { { "- " .. block.lines[i], hl_group } })
  end

  local remaining = line_count - max_preview_lines
  if remaining > 0 then
    table.insert(display_lines, { { string.format("... %d more deleted lines", remaining), hl_group } })
  end

  return display_lines
end

local function render_deletion_state(bufnr, deletion_state)
  if type(bufnr) ~= "number" or bufnr <= 0 or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  vim.api.nvim_buf_clear_namespace(bufnr, deletion_namespace, 0, -1)

  if type(deletion_state) ~= "table" or type(deletion_state.blocks) ~= "table" then
    state.deletion_bufnrs[bufnr] = nil
    return false
  end

  local line_count = math.max(vim.api.nvim_buf_line_count(bufnr), 1)
  local rendered = 0
  for _, block in ipairs(deletion_state.blocks) do
    local virt_lines = build_virtual_lines(block, {
      max_preview_lines = deletion_state.max_preview_lines,
      hl_group = deletion_state.hl_group,
    })

    if #virt_lines > 0 then
      local row = nil
      if block.anchor_lnum > line_count then
        row = line_count
      else
        row = math.min(math.max(block.anchor_lnum, 1), line_count) - 1
      end
      vim.api.nvim_buf_set_extmark(bufnr, deletion_namespace, row, 0, {
        virt_lines = virt_lines,
        virt_lines_above = true,
      })
      rendered = rendered + 1
    end
  end

  if rendered > 0 then
    state.deletion_bufnrs[bufnr] = true
    return true
  end

  state.deletion_bufnrs[bufnr] = nil
  return false
end

local function resolve_block_index_for_line(blocks, lnum)
  if type(blocks) ~= "table" or #blocks == 0 or type(lnum) ~= "number" or lnum <= 0 then
    return nil
  end

  local best_index = nil
  local best_distance = nil
  for i, block in ipairs(blocks) do
    if type(block) == "table" and type(block.anchor_lnum) == "number" then
      local distance = math.abs(block.anchor_lnum - lnum)
      if best_distance == nil or distance < best_distance then
        best_distance = distance
        best_index = i
      end
      if distance == 0 then
        return i
      end
    end
  end

  return best_index
end

function M.clear(opts)
  opts = opts or {}
  if opts.all == true then
    clear_namespace_in_all_buffers(namespace)
    M.clear_all_deletions({ all = true })
    state.bufnr = nil
    return
  end

  local bufnr = opts.bufnr or state.bufnr
  if not clear_namespace_in_buffer(bufnr, namespace) then
    state.bufnr = nil
    return
  end

  M.clear_deletions({ bufnr = bufnr })

  if state.bufnr == bufnr then
    state.bufnr = nil
  end
end

function M.clear_file_hunks(opts)
  opts = opts or {}
  local bufnr = opts.bufnr
  if type(bufnr) ~= "number" or bufnr <= 0 or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  clear_namespace_in_buffer(bufnr, file_hunks_namespace)
  state.file_hunk_bufnrs[bufnr] = nil
  M.clear_deletions({ bufnr = bufnr })
end

function M.clear_all_file_hunks(opts)
  opts = opts or {}
  if opts.all == true then
    clear_namespace_in_all_buffers(file_hunks_namespace)
    M.clear_all_deletions({ all = true })
    state.file_hunk_bufnrs = {}
    return
  end

  for bufnr, _ in pairs(state.file_hunk_bufnrs) do
    clear_namespace_in_buffer(bufnr, file_hunks_namespace)
  end

  state.file_hunk_bufnrs = {}
  M.clear_all_deletions()
end

function M.clear_deletions(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or state.bufnr
  if type(bufnr) ~= "number" or bufnr <= 0 then
    return false
  end

  if not clear_namespace_in_buffer(bufnr, deletion_namespace) then
    state.deletion_bufnrs[bufnr] = nil
    state.deletion_blocks_by_bufnr[bufnr] = nil
    return false
  end

  state.deletion_bufnrs[bufnr] = nil
  state.deletion_blocks_by_bufnr[bufnr] = nil
  return true
end

function M.clear_all_deletions(opts)
  opts = opts or {}
  if opts.all == true then
    clear_namespace_in_all_buffers(deletion_namespace)
    state.deletion_bufnrs = {}
    state.deletion_blocks_by_bufnr = {}
    return
  end

  for bufnr, _ in pairs(state.deletion_bufnrs) do
    clear_namespace_in_buffer(bufnr, deletion_namespace)
  end
  state.deletion_bufnrs = {}
  state.deletion_blocks_by_bufnr = {}
end

function M.render_deletions(opts)
  opts = opts or {}
  local bufnr = opts.bufnr
  if type(bufnr) ~= "number" or bufnr <= 0 or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local settings = resolve_deletion_settings()
  if settings.enabled ~= true then
    M.clear_deletions({ bufnr = bufnr })
    return false
  end

  local groups = resolve_highlight_groups()
  local blocks = normalize_deleted_blocks(opts.deleted_blocks, settings.default_expanded)
  if #blocks == 0 then
    M.clear_deletions({ bufnr = bufnr })
    return false
  end

  local deletion_state = {
    blocks = blocks,
    max_preview_lines = settings.max_preview_lines,
    hl_group = groups.delete,
  }

  state.deletion_blocks_by_bufnr[bufnr] = deletion_state
  return render_deletion_state(bufnr, deletion_state)
end

function M.toggle_current_block(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  if type(bufnr) ~= "number" or bufnr <= 0 or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local deletion_state = state.deletion_blocks_by_bufnr[bufnr]
  if type(deletion_state) ~= "table" or type(deletion_state.blocks) ~= "table" or #deletion_state.blocks == 0 then
    return false
  end

  local lnum = opts.lnum
  if type(lnum) ~= "number" or lnum <= 0 then
    lnum = vim.api.nvim_win_get_cursor(0)[1]
  end

  local block_index = resolve_block_index_for_line(deletion_state.blocks, lnum)
  if block_index == nil then
    return false
  end

  local block = deletion_state.blocks[block_index]
  block.expanded = not (block.expanded == true)
  render_deletion_state(bufnr, deletion_state)
  return block.expanded
end

function M.get_deletion_toggle_mode(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  if type(bufnr) ~= "number" or bufnr <= 0 or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local deletion_state = state.deletion_blocks_by_bufnr[bufnr]
  local blocks = type(deletion_state) == "table" and deletion_state.blocks or nil
  if type(blocks) ~= "table" or #blocks == 0 then
    return nil
  end

  for _, block in ipairs(blocks) do
    if type(block) == "table" and block.expanded ~= true then
      return "expand"
    end
  end

  return "collapse"
end

function M.expand_all_blocks(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local deletion_state = state.deletion_blocks_by_bufnr[bufnr]
  if type(deletion_state) ~= "table" or type(deletion_state.blocks) ~= "table" or #deletion_state.blocks == 0 then
    return false
  end

  for _, block in ipairs(deletion_state.blocks) do
    block.expanded = true
  end
  return render_deletion_state(bufnr, deletion_state)
end

function M.collapse_all_blocks(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local deletion_state = state.deletion_blocks_by_bufnr[bufnr]
  if type(deletion_state) ~= "table" or type(deletion_state.blocks) ~= "table" or #deletion_state.blocks == 0 then
    return false
  end

  for _, block in ipairs(deletion_state.blocks) do
    block.expanded = false
  end
  return render_deletion_state(bufnr, deletion_state)
end

function M.render_file_hunks(opts)
  opts = opts or {}
  local bufnr = opts.bufnr
  local ranges = opts.ranges

  if type(bufnr) ~= "number" or bufnr <= 0 or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  if type(ranges) ~= "table" then
    return false
  end

  local groups = resolve_highlight_groups()
  vim.api.nvim_buf_clear_namespace(bufnr, file_hunks_namespace, 0, -1)

  local highlighted = 0
  local deleted_blocks = {}
  for _, range in ipairs(ranges) do
    if type(range) == "table" then
      local lnum = range.lnum
      local end_lnum = range.end_lnum or range.lnum
      if type(lnum) == "number" and lnum > 0 and type(end_lnum) == "number" and end_lnum > 0 then
        local first = math.min(lnum, end_lnum)
        local last = math.max(lnum, end_lnum)
        local added_lines = range.added_lines
        for line = first, last do
          local hl_group = resolve_line_highlight_group(line, added_lines, groups)
          vim.api.nvim_buf_add_highlight(bufnr, file_hunks_namespace, hl_group, line - 1, 0, -1)
          highlighted = highlighted + 1
        end
      end

      if type(range.deleted_blocks) == "table" then
        for _, block in ipairs(range.deleted_blocks) do
          table.insert(deleted_blocks, block)
        end
      end
    end
  end

  local deletions_rendered = M.render_deletions({
    bufnr = bufnr,
    deleted_blocks = deleted_blocks,
  })

  if highlighted > 0 or deletions_rendered == true then
    state.file_hunk_bufnrs[bufnr] = true
    return true
  end

  state.file_hunk_bufnrs[bufnr] = nil
  return false
end

function M.render_range(bufnr, start_lnum, end_lnum, opts)
  opts = opts or {}
  if type(bufnr) ~= "number" or bufnr <= 0 or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  if type(start_lnum) ~= "number" or start_lnum <= 0 then
    return false
  end

  if type(end_lnum) ~= "number" or end_lnum <= 0 then
    return false
  end

  local groups = resolve_highlight_groups()
  local added_lines = opts.added_lines

  local first = math.min(start_lnum, end_lnum)
  local last = math.max(start_lnum, end_lnum)

  M.clear({ bufnr = state.bufnr })
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)

  for line = first, last do
    local hl_group = resolve_line_highlight_group(line, added_lines, groups)
    vim.api.nvim_buf_add_highlight(bufnr, namespace, hl_group, line - 1, 0, -1)
  end

  M.render_deletions({
    bufnr = bufnr,
    deleted_blocks = opts.deleted_blocks,
  })

  state.bufnr = bufnr
  return true
end

function M.render_current_hunk(opts)
  opts = opts or {}
  local qf_item = opts.qf_item

  if qf_item == nil then
    local quickfix = vim.fn.getqflist({ idx = 0, items = 1 })
    if type(quickfix) ~= "table" or type(quickfix.idx) ~= "number" then
      return false
    end

    local current = type(quickfix.items) == "table" and quickfix.items[quickfix.idx] or nil
    if type(current) ~= "table" then
      return false
    end

    qf_item = current
  end

  if type(qf_item) ~= "table" then
    return false
  end

  local lnum = qf_item.lnum
  local end_lnum = qf_item.end_lnum or qf_item.lnum
  if type(lnum) ~= "number" or lnum <= 0 or type(end_lnum) ~= "number" or end_lnum <= 0 then
    return false
  end

  local bufnr = resolve_target_bufnr(qf_item)
  if type(bufnr) ~= "number" then
    return false
  end

  return M.render_range(bufnr, lnum, end_lnum, {
    added_lines = qf_item.added_lines,
    deleted_blocks = qf_item.deleted_blocks,
  })
end

function M.namespace_id()
  return namespace
end

function M.file_hunks_namespace_id()
  return file_hunks_namespace
end

function M.deletion_namespace_id()
  return deletion_namespace
end

return M
