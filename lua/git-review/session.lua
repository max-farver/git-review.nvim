local M = {}

local thread_refresh_group = nil
local current_session = nil

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalize_run_result(result)
  if type(result) ~= "table" then
    return nil, "run_command must return a table"
  end

  if type(result.code) ~= "number" then
    return nil, "run_command result.code must be a number"
  end

  if result.stdout ~= nil and type(result.stdout) ~= "string" then
    return nil, "run_command result.stdout must be a string"
  end

  if result.stderr ~= nil and type(result.stderr) ~= "string" then
    return nil, "run_command result.stderr must be a string"
  end

  return {
    code = result.code,
    stdout = result.stdout or "",
    stderr = result.stderr or "",
  }
end

local function resolve_default_diff_command(run_command)
  local raw_result = run_command({ "git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}" })
  local result, result_error = normalize_run_result(raw_result)
  if not result then
    return nil, "Unable to determine review diff range: " .. result_error
  end

  if result.code ~= 0 then
    local detail = result.stderr ~= "" and result.stderr or "upstream branch is not configured"
    return nil, "Unable to determine review diff range. Set an upstream branch or pass opts.diff_command. Git error: " .. detail
  end

  local upstream = trim(result.stdout)
  if upstream == "" then
    return nil, "Unable to determine review diff range. Upstream branch is empty; set an upstream branch or pass opts.diff_command."
  end

  return { "git", "diff", "--no-color", upstream .. "...HEAD" }
end

local function resolve_pr_base_diff_command(run_command, resolve_branch, resolve_pr_for_branch)
  local branch, branch_error = resolve_branch(run_command)
  if type(branch) ~= "string" or branch == "" then
    return nil, "Unable to determine current branch for pull request lookup: " .. tostring(branch_error)
  end

  local pr_result = resolve_pr_for_branch(branch, run_command)
  if type(pr_result) ~= "table" then
    return nil, "Pull request lookup returned invalid state"
  end

  if pr_result.state ~= "single_pr" or type(pr_result.pr) ~= "table" then
    return nil, pr_result.message or ("Pull request lookup state: " .. tostring(pr_result.state))
  end

  local base_branch = pr_result.pr.baseRefName
  if type(base_branch) ~= "string" or trim(base_branch) == "" then
    return nil, "Pull request payload is missing baseRefName"
  end

  return {
    diff_command = { "git", "diff", "--no-color", "origin/" .. trim(base_branch) .. "...HEAD" },
    pr = pr_result.pr,
  }
end

local function command_to_string(command)
  if type(command) == "table" then
    return table.concat(command, " ")
  end

  return tostring(command)
end

local function paths_match(left, right)
  if type(left) ~= "string" or left == "" or type(right) ~= "string" or right == "" then
    return false
  end

  local normalized_left = vim.fs.normalize(left)
  local normalized_right = vim.fs.normalize(right)
  if normalized_left == normalized_right then
    return true
  end

  local real_left = vim.loop.fs_realpath(normalized_left)
  local real_right = vim.loop.fs_realpath(normalized_right)
  return type(real_left) == "string" and type(real_right) == "string" and real_left == real_right
end

local function resolve_initial_quickfix_index(items)
  if type(items) ~= "table" or #items == 0 then
    return 1
  end

  local current_bufnr = vim.api.nvim_get_current_buf()
  if type(current_bufnr) ~= "number" or current_bufnr <= 0 or not vim.api.nvim_buf_is_valid(current_bufnr) then
    return 1
  end

  local current_bufname = vim.api.nvim_buf_get_name(current_bufnr)
  if type(current_bufname) ~= "string" or current_bufname == "" then
    return 1
  end

  for idx, item in ipairs(items) do
    if type(item) == "table" and type(item.filename) == "string" and item.filename ~= "" then
      if paths_match(item.filename, current_bufname) then
        return idx
      end
    end
  end

  return 1
end

local function build_file_quickfix_items(hunks)
  if type(hunks) ~= "table" then
    return {}
  end

  local items = {}
  local seen = {}
  for _, hunk in ipairs(hunks) do
    if type(hunk) == "table" and type(hunk.filename) == "string" and hunk.filename ~= "" then
      if seen[hunk.filename] ~= true then
        seen[hunk.filename] = true
        table.insert(items, {
          filename = hunk.filename,
          lnum = hunk.lnum,
          end_lnum = hunk.end_lnum,
          text = hunk.text,
        })
      end
    end
  end

  return items
end

local function normalize_review_file(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end

  return vim.fs.normalize(path)
end

local function build_review_file_order(file_items)
  local order = {}
  if type(file_items) ~= "table" then
    return order
  end

  for _, item in ipairs(file_items) do
    if type(item) == "table" and type(item.filename) == "string" and item.filename ~= "" then
      local normalized = normalize_review_file(item.filename)
      if type(normalized) == "string" and normalized ~= "" then
        table.insert(order, normalized)
      end
    end
  end

  return order
end

local function build_reviewed_file_map(review_file_order, previous)
  local reviewed = {}
  if type(review_file_order) ~= "table" then
    return reviewed
  end

  for _, path in ipairs(review_file_order) do
    if type(path) == "string" and path ~= "" and type(previous) == "table" and previous[path] == true then
      reviewed[path] = true
    end
  end

  return reviewed
end

local function is_reviewed_file(session, path)
  if type(session) ~= "table" then
    return false
  end

  local normalized = normalize_review_file(path)
  if type(normalized) ~= "string" then
    return false
  end

  local reviewed_files = session.reviewed_files
  return type(reviewed_files) == "table" and reviewed_files[normalized] == true
end

local function find_review_file_index(session, path)
  if type(session) ~= "table" then
    return nil
  end

  local normalized = normalize_review_file(path)
  if type(normalized) ~= "string" then
    return nil
  end

  local review_file_order = session.review_file_order
  if type(review_file_order) ~= "table" then
    return nil
  end

  for idx, item in ipairs(review_file_order) do
    if item == normalized then
      return idx
    end
  end

  return nil
end

local function format_review_file_status(session, path)
  if is_reviewed_file(session, path) then
    return "[x] "
  end

  return "[ ] "
end

local function build_review_quickfix_items(session)
  local base_items = build_file_quickfix_items(type(session) == "table" and session.hunks or {})
  local items = {}
  for _, item in ipairs(base_items) do
    if type(item) == "table" then
      local copy = vim.deepcopy(item)
      local status = format_review_file_status(session, copy.filename)
      local text = type(copy.text) == "string" and copy.text or "Git Review File"
      copy.text = status .. text
      table.insert(items, copy)
    end
  end

  return items
end

local function refresh_review_quickfix_markers(session)
  if type(session) ~= "table" then
    return
  end

  local review_quickfix_list_id = session.review_quickfix_list_id
  if type(review_quickfix_list_id) ~= "number" then
    return
  end

  local current_quickfix_list = vim.fn.getqflist({ id = 0 })
  if type(current_quickfix_list) ~= "table" or current_quickfix_list.id ~= review_quickfix_list_id then
    return
  end

  local quickfix_idx = vim.fn.getqflist({ idx = 0 })
  local current_idx = type(quickfix_idx) == "table" and type(quickfix_idx.idx) == "number" and quickfix_idx.idx or 1
  local items = build_review_quickfix_items(session)

  vim.fn.setqflist({}, "r", {
    id = review_quickfix_list_id,
    title = "Git Review Files",
    items = items,
    idx = resolve_initial_quickfix_index(items) or current_idx,
  })
end

local function build_picker_file_choices(file_items, repo_root)
  if type(file_items) ~= "table" then
    return {}
  end

  local choices = {}
  for _, item in ipairs(file_items) do
    if type(item) == "table" and type(item.filename) == "string" and item.filename ~= "" then
      local label = item.filename
      if type(repo_root) == "string" and repo_root ~= "" then
        local rel = vim.fs.relpath(repo_root, item.filename)
        if type(rel) == "string" and rel ~= "" then
          label = rel
        end
      end

      table.insert(choices, {
        label = label,
        filename = item.filename,
      })
    end
  end

  return choices
end

local function select_review_file(choices, on_choice)
  vim.ui.select(choices, {
    prompt = "Select file for review",
    format_item = function(choice)
      if type(choice) == "table" and type(choice.label) == "string" then
        return choice.label
      end

      return tostring(choice)
    end,
  }, function(choice, choice_idx)
    on_choice(choice, choice_idx)
  end)
end

local default_vim_ui_select = vim.ui.select

local function can_use_picker_ui()
  if type(vim.ui.select) ~= "function" then
    return false
  end

  if vim.ui.select ~= default_vim_ui_select then
    return true
  end

  local uis = vim.api.nvim_list_uis()
  return type(uis) == "table" and #uis > 0
end

local function indexed_file_keys(path)
  if type(path) ~= "string" or path == "" then
    return {}
  end

  local normalized = vim.fs.normalize(path)
  local keys = { normalized }
  local real = vim.loop.fs_realpath(normalized)
  if type(real) == "string" and real ~= normalized then
    table.insert(keys, real)
  end

  return keys
end

local function resolve_picker_cache_value(cache, selected_file)
  if type(cache) ~= "table" or type(selected_file) ~= "string" or selected_file == "" then
    return nil
  end

  for _, key in ipairs(indexed_file_keys(selected_file)) do
    if cache[key] ~= nil then
      return cache[key]
    end
  end

  return nil
end

local function build_picker_file_choice_cache(choices)
  local cache = {
    by_index = {},
    by_file = {},
  }

  if type(choices) ~= "table" then
    return cache
  end

  for idx, choice in ipairs(choices) do
    if type(choice) == "table" and type(choice.filename) == "string" and choice.filename ~= "" then
      cache.by_index[idx] = choice
      for _, key in ipairs(indexed_file_keys(choice.filename)) do
        cache.by_file[key] = choice
      end
    end
  end

  return cache
end

local function build_picker_file_loclist_cache(choices, hunks_by_file)
  local cache = {}
  if type(choices) ~= "table" or type(hunks_by_file) ~= "table" then
    return cache
  end

  for _, choice in ipairs(choices) do
    if type(choice) == "table" and type(choice.filename) == "string" and choice.filename ~= "" then
      local ranges = resolve_picker_cache_value(hunks_by_file, choice.filename)
      if type(ranges) == "table" then
        local loclist_items = {}
        for _, range in ipairs(ranges) do
          if type(range) == "table" and type(range.lnum) == "number" then
            table.insert(loclist_items, {
              filename = choice.filename,
              lnum = range.lnum,
              end_lnum = range.end_lnum,
              added_lines = range.added_lines,
              deleted_blocks = range.deleted_blocks,
              user_data = {
                added_lines = range.added_lines,
                deleted_blocks = range.deleted_blocks,
              },
              text = "Git Review Hunk",
            })
          end
        end

        for _, key in ipairs(indexed_file_keys(choice.filename)) do
          cache[key] = loclist_items
        end
      end
    end
  end

  return cache
end

local function build_picker_file_first_hunk_cache(loclist_cache)
  local cache = {}
  if type(loclist_cache) ~= "table" then
    return cache
  end

  for key, loclist_items in pairs(loclist_cache) do
    if type(loclist_items) == "table" then
      local first_item = loclist_items[1]
      if type(first_item) == "table" and type(first_item.lnum) == "number" and first_item.lnum > 0 then
        cache[key] = {
          lnum = first_item.lnum,
          end_lnum = first_item.end_lnum,
          added_lines = first_item.added_lines,
          deleted_blocks = first_item.deleted_blocks,
        }
      end
    end
  end

  return cache
end

local function build_hunks_by_file(hunks)
  local by_file = {}
  if type(hunks) ~= "table" then
    return by_file
  end

  for _, hunk in ipairs(hunks) do
    if type(hunk) == "table" and type(hunk.filename) == "string" and hunk.filename ~= "" then
      for _, key in ipairs(indexed_file_keys(hunk.filename)) do
        by_file[key] = by_file[key] or {}
        table.insert(by_file[key], {
          lnum = hunk.lnum,
          end_lnum = hunk.end_lnum,
          added_lines = hunk.added_lines,
          deleted_blocks = hunk.deleted_blocks,
        })
      end
    end
  end

  return by_file
end


local function quickfix_item_path(item)
  if type(item) ~= "table" then
    return nil
  end

  if type(item.filename) == "string" and item.filename ~= "" then
    return item.filename
  end

  if type(item.bufnr) == "number" and item.bufnr > 0 then
    local buffer_name = vim.api.nvim_buf_get_name(item.bufnr)
    if type(buffer_name) == "string" and buffer_name ~= "" then
      return buffer_name
    end
  end

  return nil
end

local function resolve_selected_quickfix_item(review_quickfix_list_id)
  if type(review_quickfix_list_id) ~= "number" then
    return nil
  end

  local current_quickfix_list = vim.fn.getqflist({ id = 0 })
  if type(current_quickfix_list) ~= "table" or current_quickfix_list.id ~= review_quickfix_list_id then
    return nil
  end

  local current_idx = 1
  local quickfix_idx = vim.fn.getqflist({ idx = 0 })
  if type(quickfix_idx) == "table" and type(quickfix_idx.idx) == "number" and quickfix_idx.idx > 0 then
    current_idx = quickfix_idx.idx
  end

  local quickfix_items = vim.fn.getqflist()
  if type(quickfix_items) ~= "table" then
    return nil
  end

  local item = quickfix_items[current_idx]
  if type(item) ~= "table" then
    return nil
  end

  return item
end

local function is_valid_hunk_item(item)
  if type(item) ~= "table" then
    return false
  end

  if type(item.lnum) ~= "number" or item.lnum <= 0 then
    return false
  end

  if item.end_lnum ~= nil and (type(item.end_lnum) ~= "number" or item.end_lnum <= 0) then
    return false
  end

  return true
end

local function resolve_first_hunk_range(session, selected_file)
  if type(session) ~= "table" or type(selected_file) ~= "string" or selected_file == "" then
    return nil
  end

  local by_file = session.hunks_by_file
  if type(by_file) ~= "table" then
    return nil
  end

  for _, key in ipairs(indexed_file_keys(selected_file)) do
    local ranges = by_file[key]
    local first_range = type(ranges) == "table" and ranges[1] or nil
    if is_valid_hunk_item(first_range) then
      return first_range
    end
  end

  return nil
end

local function resolve_review_loclist_winid(session)
  if type(session) == "table" then
    local review_source_winid = session.review_source_winid
    if type(review_source_winid) == "number" and review_source_winid > 0 and vim.api.nvim_win_is_valid(review_source_winid) then
      return review_source_winid
    end
  end

  return 0
end

local function resolve_hunk_item_metadata(item, key)
  if type(item) ~= "table" or type(key) ~= "string" or key == "" then
    return nil
  end

  if item[key] ~= nil then
    return item[key]
  end

  local user_data = item.user_data
  if type(user_data) ~= "table" then
    return nil
  end

  return user_data[key]
end

local function with_hunk_item_metadata(item)
  if type(item) ~= "table" then
    return item
  end

  local added_lines = resolve_hunk_item_metadata(item, "added_lines")
  local deleted_blocks = resolve_hunk_item_metadata(item, "deleted_blocks")
  if added_lines == nil and deleted_blocks == nil then
    return item
  end

  local enriched = vim.deepcopy(item)
  if enriched.added_lines == nil then
    enriched.added_lines = added_lines
  end
  if enriched.deleted_blocks == nil then
    enriched.deleted_blocks = deleted_blocks
  end

  return enriched
end

local function resolve_active_hunk_item(session, opts)
  if type(session) ~= "table" then
    return nil
  end

  opts = opts or {}
  local is_review_quickfix = type(opts.review_quickfix_list_id) == "number"
  local selected_qf_item = resolve_selected_quickfix_item(opts.review_quickfix_list_id)
  local selected_file = quickfix_item_path(selected_qf_item)
  local has_selected_file = type(session.selected_file) == "string" and session.selected_file ~= ""
  if (type(selected_file) ~= "string" or selected_file == "") and type(session.selected_file) == "string" and session.selected_file ~= "" then
    selected_file = session.selected_file
  end

  local loclist = vim.fn.getloclist(resolve_review_loclist_winid(session), { idx = 0, items = 1 })
  local loclist_idx = type(loclist) == "table" and loclist.idx or nil
  local loclist_items = type(loclist) == "table" and loclist.items or nil
  local loclist_item = type(loclist_items) == "table" and loclist_items[loclist_idx] or nil
  local loclist_file = quickfix_item_path(loclist_item)

  if is_valid_hunk_item(loclist_item) then
    if not is_review_quickfix then
      if not has_selected_file then
        return nil
      end
      return with_hunk_item_metadata(loclist_item)
    end

    if type(selected_file) ~= "string" or selected_file == "" then
      return with_hunk_item_metadata(loclist_item)
    end

    if type(loclist_file) == "string" and loclist_file ~= "" and paths_match(loclist_file, selected_file) then
      return with_hunk_item_metadata(loclist_item)
    end
  end

  if type(selected_file) ~= "string" or selected_file == "" then
    return nil
  end

  local by_file = session.hunks_by_file
  if type(by_file) == "table" then
    for _, key in ipairs(indexed_file_keys(selected_file)) do
      local ranges = by_file[key]
      local first_range = type(ranges) == "table" and ranges[1] or nil
      if is_valid_hunk_item(first_range) then
        return {
          filename = selected_file,
          lnum = first_range.lnum,
          end_lnum = first_range.end_lnum,
          added_lines = first_range.added_lines,
          deleted_blocks = first_range.deleted_blocks,
        }
      end
    end
  end

  return nil
end

local function sync_loclist_for_current_quickfix_file(session, opts)
  if type(session) ~= "table" then
    return
  end

  opts = opts or {}
  local review_quickfix_list_id = opts.review_quickfix_list_id
  local current_quickfix_list = vim.fn.getqflist({ id = 0 })
  if type(review_quickfix_list_id) == "number" then
    if type(current_quickfix_list) ~= "table" or current_quickfix_list.id ~= review_quickfix_list_id then
      return
    end
  end

  local selected_item = resolve_selected_quickfix_item(review_quickfix_list_id)
  local selected_file = quickfix_item_path(selected_item)
  session.selected_file = selected_file

  local loclist_items = {}
  if type(selected_file) == "string" and selected_file ~= "" then
    local ranges = nil
    local by_file = session.hunks_by_file
    if type(by_file) == "table" then
      for _, key in ipairs(indexed_file_keys(selected_file)) do
        if type(by_file[key]) == "table" then
          ranges = by_file[key]
          break
        end
      end
    end

    if type(ranges) == "table" then
      for _, range in ipairs(ranges) do
        if type(range) == "table" and type(range.lnum) == "number" then
          table.insert(loclist_items, {
            filename = selected_file,
            lnum = range.lnum,
            end_lnum = range.end_lnum,
            added_lines = range.added_lines,
            deleted_blocks = range.deleted_blocks,
            user_data = {
              added_lines = range.added_lines,
              deleted_blocks = range.deleted_blocks,
            },
            text = "Git Review Hunk",
          })
        end
      end
    end
  end

  vim.fn.setloclist(resolve_review_loclist_winid(session), {}, " ", {
    title = "Git Review Hunks",
    items = loclist_items,
    idx = #loclist_items > 0 and 1 or nil,
  })
end

local function sync_loclist_for_selected_file(session, selected_file)
  if type(session) ~= "table" then
    return
  end

  if type(selected_file) ~= "string" or selected_file == "" then
    return
  end

  session.selected_file = selected_file

  local loclist_items = {}
  local ranges = nil
  local by_file = session.hunks_by_file
  if type(by_file) == "table" then
    for _, key in ipairs(indexed_file_keys(selected_file)) do
      if type(by_file[key]) == "table" then
        ranges = by_file[key]
        break
      end
    end
  end

  if type(ranges) == "table" then
    for _, range in ipairs(ranges) do
      if type(range) == "table" and type(range.lnum) == "number" then
        table.insert(loclist_items, {
          filename = selected_file,
          lnum = range.lnum,
          end_lnum = range.end_lnum,
          added_lines = range.added_lines,
          deleted_blocks = range.deleted_blocks,
          user_data = {
            added_lines = range.added_lines,
            deleted_blocks = range.deleted_blocks,
          },
          text = "Git Review Hunk",
        })
      end
    end
  end

  vim.fn.setloclist(resolve_review_loclist_winid(session), {}, " ", {
    title = "Git Review Hunks",
    items = loclist_items,
    idx = #loclist_items > 0 and 1 or nil,
  })
end

local render_current_buffer_file_hunks
local refresh_thread_panel

local function capture_review_navigation_state(session, review_quickfix_list_id)
  local current_quickfix_list = vim.fn.getqflist({ id = 0 })
  if type(current_quickfix_list) ~= "table" then
    return nil
  end

  local quickfix_list_id = type(current_quickfix_list.id) == "number" and current_quickfix_list.id or nil
  if type(review_quickfix_list_id) == "number" and quickfix_list_id ~= review_quickfix_list_id then
    return nil
  end

  local quickfix_idx = vim.fn.getqflist({ idx = 0 })
  local quickfix_index = type(quickfix_idx) == "table" and type(quickfix_idx.idx) == "number" and quickfix_idx.idx or 1
  if quickfix_index < 1 then
    quickfix_index = 1
  end

  local selected_file = nil
  if type(review_quickfix_list_id) == "number" then
    local selected_quickfix_item = resolve_selected_quickfix_item(review_quickfix_list_id)
    selected_file = quickfix_item_path(selected_quickfix_item)
  elseif type(session) == "table" and type(session.selected_file) == "string" and session.selected_file ~= "" then
    selected_file = session.selected_file
  end

  local loclist = vim.fn.getloclist(resolve_review_loclist_winid(session), { id = 0, idx = 0 })
  local loclist_id = type(loclist) == "table" and type(loclist.id) == "number" and loclist.id or 0
  local loclist_index = type(loclist) == "table" and type(loclist.idx) == "number" and loclist.idx or 0

  return {
    quickfix_list_id = quickfix_list_id,
    quickfix_index = quickfix_index,
    selected_file = selected_file,
    loclist_id = loclist_id,
    loclist_index = loclist_index,
  }
end

local function refresh_review_navigation_state(session, opts)
  if type(session) ~= "table" then
    return
  end

  opts = opts or {}
  local review_quickfix_list_id = opts.review_quickfix_list_id
  local force = opts.force == true
  local navigation_state = capture_review_navigation_state(session, review_quickfix_list_id)
  if type(navigation_state) ~= "table" then
    return
  end

  local previous_state = session.navigation_state
  local quickfix_changed = force
    or type(previous_state) ~= "table"
    or previous_state.quickfix_list_id ~= navigation_state.quickfix_list_id
    or previous_state.quickfix_index ~= navigation_state.quickfix_index
    or previous_state.selected_file ~= navigation_state.selected_file
  local loclist_changed = force
    or type(previous_state) ~= "table"
    or previous_state.loclist_id ~= navigation_state.loclist_id
    or previous_state.loclist_index ~= navigation_state.loclist_index

  if not quickfix_changed and not loclist_changed then
    return
  end

  if quickfix_changed and type(review_quickfix_list_id) == "number" then
    sync_loclist_for_current_quickfix_file(session, {
      review_quickfix_list_id = review_quickfix_list_id,
    })
  end

  if type(session.hunk_highlight) == "table" and type(session.hunk_highlight.render_current_hunk) == "function" then
    local active_hunk_item = resolve_active_hunk_item(session, {
      review_quickfix_list_id = review_quickfix_list_id,
    })
    pcall(session.hunk_highlight.render_current_hunk, {
      quickfix_list_id = review_quickfix_list_id,
      qf_item = active_hunk_item,
    })
  end

  if quickfix_changed then
    render_current_buffer_file_hunks(session)
  end

  local latest_state = capture_review_navigation_state(session, review_quickfix_list_id)
  session.navigation_state = latest_state or navigation_state
end

render_current_buffer_file_hunks = function(session)
  if type(session) ~= "table" then
    return
  end

  local hunk_highlight = session.hunk_highlight
  if type(hunk_highlight) ~= "table" then
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  if type(bufnr) ~= "number" or bufnr <= 0 or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local buffer_name = vim.api.nvim_buf_get_name(bufnr)
  if type(buffer_name) ~= "string" or buffer_name == "" then
    if type(hunk_highlight.clear_file_hunks) == "function" then
      pcall(hunk_highlight.clear_file_hunks, { bufnr = bufnr })
    end
    return
  end

  local ranges = nil
  local by_file = session.hunks_by_file
  if type(by_file) == "table" then
    for _, key in ipairs(indexed_file_keys(buffer_name)) do
      if type(by_file[key]) == "table" then
        ranges = by_file[key]
        break
      end
    end
  end

  if type(ranges) == "table" and #ranges > 0 then
    if type(hunk_highlight.render_file_hunks) == "function" then
      pcall(hunk_highlight.render_file_hunks, {
        bufnr = bufnr,
        ranges = ranges,
      })
    end
    return
  end

  if type(hunk_highlight.clear_file_hunks) == "function" then
    pcall(hunk_highlight.clear_file_hunks, { bufnr = bufnr })
  end
end

local function resolve_debug_log(opts)
  if type(opts.debug_log) == "function" then
    return opts.debug_log
  end

  if vim.g.git_review_debug == true then
    return function(message)
      vim.notify("[git-review] " .. tostring(message), vim.log.levels.INFO)
    end
  end

  return function(_) end
end
local function resolve_current_branch(run_command)
  local raw_result = run_command({ "git", "rev-parse", "--abbrev-ref", "HEAD" })
  local result, result_error = normalize_run_result(raw_result)
  if not result then
    return nil, result_error
  end

  if result.code ~= 0 then
    return nil, result.stderr ~= "" and result.stderr or "git rev-parse failed"
  end

  local branch = trim(result.stdout)
  if branch == "" then
    return nil, "branch name is empty"
  end

  return branch
end

local function resolve_single_pr(run_command, resolve_branch, resolve_pr_for_branch)
  local ok_branch, branch_or_error = pcall(resolve_branch, run_command)
  if not ok_branch then
    return {
      state = "command_error",
      message = "Failed to determine current branch: " .. tostring(branch_or_error),
    }
  end

  if type(branch_or_error) ~= "string" or branch_or_error == "" then
    return {
      state = "context_error",
      message = "Unable to determine current branch for pull request lookup",
    }
  end

  local ok_pr, pr_result = pcall(resolve_pr_for_branch, branch_or_error, run_command)
  if not ok_pr then
    return {
      state = "command_error",
      message = "Failed to resolve pull request for current branch: " .. tostring(pr_result),
    }
  end

  if type(pr_result) ~= "table" then
    return {
      state = "parse_error",
      message = "Pull request lookup returned invalid state",
    }
  end

  if pr_result.state == "no_pr" then
    return {
      state = "no_pr",
      message = pr_result.message or "No pull request found for current branch",
    }
  end

  if pr_result.state == "multiple_prs" then
    return {
      state = "context_error",
      message = pr_result.message or "Multiple pull requests found for current branch",
    }
  end

  if pr_result.state ~= "single_pr" or type(pr_result.pr) ~= "table" then
    return {
      state = pr_result.state or "context_error",
      message = pr_result.message or "Unable to resolve a single pull request for current branch",
    }
  end

  if type(pr_result.pr.number) ~= "number" then
    return {
      state = "parse_error",
      message = "Pull request payload is missing number",
    }
  end

  return {
    state = "ok",
    pr = pr_result.pr,
  }
end

local function resolve_repo_relative_path(abs_path, repo_root)
  if abs_path == "" then
    return nil
  end

  if type(repo_root) == "string" and repo_root ~= "" then
    local repo_prefix = repo_root .. "/"
    if abs_path:sub(1, #repo_prefix) == repo_prefix then
      return abs_path:sub(#repo_prefix + 1)
    end
  end

  return abs_path
end

local function resolve_repo_root(run_command, fallback_cwd)
  local ok, raw_result = pcall(run_command, { "git", "rev-parse", "--show-toplevel" })
  if not ok then
    return fallback_cwd
  end

  local result = normalize_run_result(raw_result)
  if not result or result.code ~= 0 then
    return fallback_cwd
  end

  local repo_root = trim(result.stdout)
  if repo_root == "" then
    return fallback_cwd
  end

  return repo_root
end

local function parse_repo_slug(remote_url)
  if type(remote_url) ~= "string" then
    return nil
  end

  local url = trim(remote_url)
  if url == "" then
    return nil
  end

  local path = nil
  path = url:match("^git@[^:]+:(.+)$")
    or url:match("^ssh://[^/]+/(.+)$")
    or url:match("^https?://[^/]+/(.+)$")

  if type(path) ~= "string" or path == "" then
    return nil
  end

  path = path:gsub("%.git$", ""):gsub("/+$", "")
  local owner_repo = path:match("([^/]+/[^/]+)$")
  if type(owner_repo) ~= "string" or owner_repo == "" then
    return nil
  end

  return owner_repo
end

local function resolve_repo_slug(run_command)
  local ok, raw_result = pcall(run_command, { "git", "config", "--get", "remote.origin.url" })
  if not ok then
    return nil
  end

  local result, result_error = normalize_run_result(raw_result)
  if not result or result.code ~= 0 then
    return nil, result_error
  end

  return parse_repo_slug(result.stdout)
end

local function resolve_head_commit(run_command)
  local ok, raw_result = pcall(run_command, { "git", "rev-parse", "HEAD" })
  if not ok then
    return nil
  end

  local result, result_error = normalize_run_result(raw_result)
  if not result or result.code ~= 0 then
    return nil, result_error
  end

  local commit_id = trim(result.stdout)
  if commit_id == "" then
    return nil
  end

  return commit_id
end

local function validate_commit_ref(run_command, ref, label)
  local guidance = "Verify ref with: git rev-parse --verify " .. ref .. "^{commit}"
  local raw_result = run_command({ "git", "rev-parse", "--verify", ref .. "^{commit}" })
  local result, result_error = normalize_run_result(raw_result)
  if not result then
    return nil, "Unable to validate " .. label .. " ref '" .. ref .. "': " .. result_error .. ". " .. guidance
  end

  if result.code ~= 0 then
    local detail = result.stderr ~= "" and trim(result.stderr) or "invalid ref"
    return nil, "Unable to validate " .. label .. " ref '" .. ref .. "': " .. detail .. ". " .. guidance
  end

  local commit_id = trim(result.stdout)
  if commit_id == "" then
    return nil, "Unable to validate " .. label .. " ref '" .. ref .. "': empty commit id. " .. guidance
  end

  return commit_id
end

local function remove_owned_worktree(session, opts)
  if type(session) ~= "table" or session.worktree_owned ~= true then
    return true
  end

  local worktree_path = session.worktree_path
  if type(worktree_path) ~= "string" or worktree_path == "" then
    return true
  end

  opts = opts or {}
  local run_command = opts.run_command or session.run_command or require("git-review.system").run
  local command = { "git", "worktree", "remove", "--force", worktree_path }
  local ok_call, raw_result = pcall(run_command, command)
  if not ok_call then
    return false,
      "Unable to remove owned worktree '"
        .. worktree_path
        .. "': "
        .. tostring(raw_result)
        .. ". Run 'git worktree remove --force "
        .. worktree_path
        .. "' manually."
  end

  local result, result_error = normalize_run_result(raw_result)
  if not result then
    return false,
      "Unable to remove owned worktree '"
        .. worktree_path
        .. "': "
        .. tostring(result_error)
        .. ". Run 'git worktree remove --force "
        .. worktree_path
        .. "' manually."
  end

  if result.code ~= 0 then
    local detail = result.stderr ~= "" and trim(result.stderr) or "git worktree remove failed"
    return false,
      "Unable to remove owned worktree '"
        .. worktree_path
        .. "': "
        .. detail
        .. ". Run 'git worktree remove --force "
        .. worktree_path
        .. "' manually."
  end

  return true
end

local function should_cleanup_previous_owned_worktree(previous_session, next_opts)
  if type(previous_session) ~= "table" or previous_session.worktree_owned ~= true then
    return false
  end

  local previous_worktree_path = previous_session.worktree_path
  if type(previous_worktree_path) ~= "string" or previous_worktree_path == "" then
    return false
  end

  if type(next_opts) ~= "table" then
    return true
  end

  if next_opts.worktree_owned ~= true then
    return true
  end

  local next_worktree_path = next_opts.worktree_path
  if type(next_worktree_path) ~= "string" or next_worktree_path == "" then
    return true
  end

  return not paths_match(previous_worktree_path, next_worktree_path)
end

local function resolve_context_path_from_buffer(opts)
  local bufnr = opts.bufnr or 0
  local buffer_name = vim.api.nvim_buf_get_name(bufnr)
  if type(buffer_name) ~= "string" or buffer_name == "" then
    return nil, "Current buffer has no file path"
  end

  local repo_root = opts.repo_root or (current_session and current_session.repo_root)
  if repo_root == nil or repo_root == "" then
    repo_root = opts.cwd or vim.loop.cwd()
  end

  local relative_path = resolve_repo_relative_path(buffer_name, repo_root)
  if type(relative_path) ~= "string" or relative_path == "" then
    return nil, "Unable to determine repo-relative path for current buffer"
  end

  return relative_path
end

local function resolve_comment_context(opts)
  if type(opts.context) == "table" then
    local path = opts.context.path
    if path == nil then
      local inferred_path, path_error = resolve_context_path_from_buffer(opts)
      if not inferred_path then
        return nil, path_error
      end

      path = inferred_path
    end

    if type(path) ~= "string" or path == "" then
      return nil, "context.path must be a non-empty string"
    end

    if type(opts.context.start_line) ~= "number" or opts.context.start_line <= 0 then
      return nil, "context.start_line must be a positive number"
    end

    local end_line = opts.context.end_line or opts.context.start_line
    if type(end_line) ~= "number" or end_line <= 0 then
      return nil, "context.end_line must be a positive number"
    end

    return {
      path = path,
      start_line = opts.context.start_line,
      end_line = end_line,
    }
  end

  local relative_path, path_error = resolve_context_path_from_buffer(opts)
  if not relative_path then
    return nil, path_error
  end

  local cursor = opts.cursor or vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  return {
    path = relative_path,
    start_line = line,
    end_line = line,
  }
end

local function resolve_panel_scope_threads(session, scope, panel_current_path)
  local threads = type(session.threads) == "table" and session.threads or {}
  if scope ~= "current" then
    return threads
  end

  if type(panel_current_path) ~= "string" or panel_current_path == "" then
    return {}
  end

  local filtered = {}
  for _, thread in ipairs(threads) do
    if type(thread) == "table" and thread.path == panel_current_path then
      table.insert(filtered, thread)
    end
  end

  return filtered
end

local function resolve_panel_empty_message(scope)
  if scope == "current" then
    return "No review threads for current buffer."
  end

  return nil
end

local function refresh_session_threads(session, deps, opts)
  opts = opts or {}
  local resolve_branch = deps.resolve_branch
  local resolve_pr_for_branch = deps.resolve_pr_for_branch
  local fetch_review_threads = deps.fetch_review_threads
  local run_command = deps.run_command

  session.pr = nil
  session.pr_number = nil

  local preloaded_pr = opts.preloaded_pr
  local pr_state = nil
  if type(preloaded_pr) == "table" and type(preloaded_pr.number) == "number" then
    pr_state = {
      state = "ok",
      pr = preloaded_pr,
    }
  else
    pr_state = resolve_single_pr(run_command, resolve_branch, resolve_pr_for_branch)
    if pr_state.state ~= "ok" then
      return pr_state
    end
  end

  session.pr = pr_state.pr
  session.pr_number = pr_state.pr.number

  local ok_threads, thread_result = pcall(fetch_review_threads, pr_state.pr.number, run_command)
  if not ok_threads then
    return {
      state = "command_error",
      message = "Failed to fetch review threads: " .. tostring(thread_result),
    }
  end

  if type(thread_result) ~= "table" then
    return {
      state = "parse_error",
      message = "Review thread lookup returned invalid state",
    }
  end

  if thread_result.state ~= "ok" or type(thread_result.threads) ~= "table" then
    return {
      state = thread_result.state or "context_error",
      message = thread_result.message or "Unable to load review threads",
    }
  end

  session.threads = thread_result.threads

  return {
    state = "ok",
  }
end

refresh_thread_panel = function(session, deps, opts)
  opts = opts or {}
  local panel = deps.panel

  local thread_state = refresh_session_threads(session, deps, {
    preloaded_pr = opts.preloaded_pr,
  })
  if thread_state.state ~= "ok" then
    return thread_state
  end

  local scope = opts.scope or session.panel_scope or "all"
  local panel_current_path = opts.panel_current_path
  if panel_current_path == nil then
    panel_current_path = session.panel_current_path
  end
  local scoped_threads = resolve_panel_scope_threads(session, scope, panel_current_path)

  local ok_render, render_error = pcall(panel.render, scoped_threads, {
    open = opts.open_panel == true,
    empty_message = resolve_panel_empty_message(scope),
  })
  if not ok_render then
    return {
      state = "command_error",
      message = "Failed to render review panel: " .. tostring(render_error),
    }
  end

  return {
    state = "ok",
  }
end

local function rerender_thread_panel_from_session(session, opts)
  opts = opts or {}

  local panel = opts.panel or session.panel
  if type(panel) ~= "table" or type(panel.render) ~= "function" then
    return {
      state = "context_error",
      message = "Review panel is unavailable",
    }
  end

  if type(session.threads) ~= "table" then
    session.threads = {}
  end

  local open_panel = false
  if opts.open_panel == true then
    open_panel = true
  end
  if type(panel.is_open) == "function" then
    local ok_is_open, is_open = pcall(panel.is_open)
    if ok_is_open and is_open == true then
      open_panel = true
    end
  end

  local cursor_before = nil
  local panel_winid = nil
  local panel_bufnr = nil

  if open_panel and type(panel.open) == "function" then
    local ok_open, opened = pcall(panel.open, {})
    if ok_open and type(opened) == "table" then
      panel_winid = opened.winid
      panel_bufnr = opened.bufnr
      if type(panel_winid) == "number" and panel_winid > 0 and vim.api.nvim_win_is_valid(panel_winid) then
        local ok_cursor, cursor = pcall(vim.api.nvim_win_get_cursor, panel_winid)
        if ok_cursor and type(cursor) == "table" and type(cursor[1]) == "number" and type(cursor[2]) == "number" then
          cursor_before = cursor
        end
      end
    end
  end

  local scope = opts.scope or session.panel_scope or "all"
  local panel_current_path = opts.panel_current_path
  if panel_current_path == nil then
    panel_current_path = session.panel_current_path
  end
  local scoped_threads = resolve_panel_scope_threads(session, scope, panel_current_path)

  local ok_render, render_error = pcall(panel.render, scoped_threads, {
    open = open_panel,
    show_resolved_bodies = opts.show_resolved_bodies,
    empty_message = resolve_panel_empty_message(scope),
  })
  if not ok_render then
    return {
      state = "command_error",
      message = "Failed to render review panel: " .. tostring(render_error),
    }
  end

  if cursor_before ~= nil
    and type(panel_winid) == "number"
    and panel_winid > 0
    and vim.api.nvim_win_is_valid(panel_winid)
    and type(panel_bufnr) == "number"
    and panel_bufnr > 0
    and vim.api.nvim_buf_is_valid(panel_bufnr)
  then
    local line_count = vim.api.nvim_buf_line_count(panel_bufnr)
    local target_line = math.max(1, math.min(cursor_before[1], line_count))
    local target_col = math.max(0, cursor_before[2])
    pcall(vim.api.nvim_win_set_cursor, panel_winid, { target_line, target_col })
  end

  return {
    state = "ok",
  }
end

local function open_review_quickfix_preserving_focus()
  local original_winid = vim.api.nvim_get_current_win()
  vim.cmd("copen")

  if vim.api.nvim_win_is_valid(original_winid) then
    vim.api.nvim_set_current_win(original_winid)
  end
end

local function readonly_mode_unsupported(action_name)
  if type(current_session) ~= "table" then
    return nil
  end

  local mode = current_session.mode
  if mode == "range" or mode == "local" or mode == "branch" then
    return {
      state = "unsupported_in_range_mode",
      message = action_name .. " is unsupported in " .. mode .. " mode",
    }
  end

  return nil
end

function M.start(opts)
  opts = opts or {}
  vim.validate({
    opts = { opts, "table" },
  })

  local previous_session = current_session
  local should_cleanup_previous = should_cleanup_previous_owned_worktree(previous_session, opts)
  if should_cleanup_previous then
    local _, cleanup_error = remove_owned_worktree(previous_session)
    if cleanup_error ~= nil then
      error(cleanup_error)
    end
  end

  current_session = nil
  local review_source_winid = vim.api.nvim_get_current_win()
  local review_quickfix_list_id = nil

  local run_command = opts.run_command or require("git-review.system").run
  local parse_diff = opts.parse_diff or require("git-review.hunks").parse_diff
  local resolve_diff_command = opts.resolve_diff_command or resolve_default_diff_command
  local resolve_branch = opts.resolve_branch or resolve_current_branch
  local resolve_pr_for_branch = opts.resolve_pr_for_branch or require("git-review.github").resolve_pr_for_branch
  local fetch_review_threads = opts.fetch_review_threads or require("git-review.github").fetch_review_threads
  local panel = opts.panel or require("git-review.ui.panel")
  local hunk_highlight = opts.hunk_highlight or require("git-review.ui.hunk_highlight")
  local debug_log = resolve_debug_log(opts)
  local diff_command = opts.diff_command
  local pr_diff_payload = nil

  if diff_command == nil then
    local ok_pr_diff
    ok_pr_diff, pr_diff_payload = pcall(resolve_pr_base_diff_command, run_command, resolve_branch, resolve_pr_for_branch)
    local has_pr_diff_payload = ok_pr_diff
      and type(pr_diff_payload) == "table"
      and type(pr_diff_payload.diff_command) == "table"
    if has_pr_diff_payload then
      diff_command = pr_diff_payload.diff_command
      debug_log("using PR base diff command: " .. command_to_string(diff_command))
    else
      local pr_diff_error = "unknown error"
      if ok_pr_diff then
        pr_diff_error = tostring(pr_diff_payload)
      else
        pr_diff_error = "resolver crashed: " .. tostring(pr_diff_payload)
      end
      local upstream_command
      local command_error
      upstream_command, command_error = resolve_diff_command(run_command)
      if not upstream_command then
        error(command_error)
      end

      diff_command = upstream_command
      debug_log("falling back to upstream diff command; PR base unavailable: " .. pr_diff_error)
    end
  end

  if type(diff_command) == "string" then
    diff_command = vim.split(trim(diff_command), "%s+", { trimempty = true })
  end

  debug_log("running diff command: " .. command_to_string(diff_command))

  local raw_result = run_command(diff_command)
  local result, result_error = normalize_run_result(raw_result)
  if not result then
    error(result_error)
  end

  debug_log("diff command exit code: " .. tostring(result.code) .. ", stdout bytes: " .. tostring(#result.stdout))

  if result.code ~= 0 then
    error(result.stderr ~= "" and result.stderr or "git diff failed")
  end

  local fallback_cwd = opts.cwd or vim.loop.cwd()
  local repo_root = opts.repo_root or resolve_repo_root(run_command, fallback_cwd)
  local repo = opts.repo or resolve_repo_slug(run_command)
  local commit_id = opts.commit_id or resolve_head_commit(run_command)

  current_session = {
    diff_text = result.stdout,
    repo_root = repo_root,
    run_command = run_command,
    parse_diff = parse_diff,
    resolve_branch = resolve_branch,
    resolve_pr_for_branch = resolve_pr_for_branch,
    fetch_review_threads = fetch_review_threads,
    panel = panel,
    hunk_highlight = hunk_highlight,
    diff_command = diff_command,
    cwd = fallback_cwd,
    repo = repo,
    commit_id = commit_id,
    review_source_winid = review_source_winid,
    review_quickfix_list_id = review_quickfix_list_id,
    pr = type(pr_diff_payload) == "table" and pr_diff_payload.pr or nil,
    pr_number = type(pr_diff_payload) == "table" and type(pr_diff_payload.pr) == "table" and pr_diff_payload.pr.number or nil,
    panel_scope = "all",
    panel_current_path = nil,
    threads_fetch_in_flight = false,
    threads = {},
    mode = opts.mode,
    range_start = opts.range_start,
    range_end = opts.range_end,
    review_commit_id = opts.review_commit_id,
    review_repo_root = opts.review_repo_root,
    worktree_path = opts.worktree_path,
    worktree_owned = opts.worktree_owned == true,
  }

  local hunks = parse_diff(result.stdout, {
    repo_root = repo_root,
  })
  local file_items = build_file_quickfix_items(hunks)
  local review_file_order = build_review_file_order(file_items)
  current_session.hunks_by_file = build_hunks_by_file(hunks)
  current_session.hunks = hunks
  current_session.review_file_order = review_file_order
  current_session.reviewed_files = build_reviewed_file_map(review_file_order, opts.reviewed_files)
  debug_log("parsed hunks: " .. tostring(#hunks))
  local picker_choices = build_picker_file_choices(file_items, repo_root)
  current_session.picker_file_choice_cache = build_picker_file_choice_cache(picker_choices)
  current_session.picker_file_loclist_cache = build_picker_file_loclist_cache(picker_choices, current_session.hunks_by_file)
  current_session.picker_file_first_hunk_cache = build_picker_file_first_hunk_cache(current_session.picker_file_loclist_cache)
  if #picker_choices > 0 and can_use_picker_ui() then
    local picker_session = current_session
    select_review_file(picker_choices, function(choice, choice_idx)
      if current_session ~= picker_session then
        return
      end

      local active_session = picker_session
      if type(active_session) ~= "table" then
        return
      end

      local selected_choice = nil
      if type(choice_idx) == "number" and type(active_session.picker_file_choice_cache) == "table" then
        selected_choice = active_session.picker_file_choice_cache.by_index[choice_idx]
      end

      if type(selected_choice) ~= "table" and type(choice) == "table" and type(choice.filename) == "string" then
        if type(active_session.picker_file_choice_cache) == "table" then
          selected_choice = resolve_picker_cache_value(active_session.picker_file_choice_cache.by_file, choice.filename)
        end
        if type(selected_choice) ~= "table" then
          selected_choice = choice
        end
      end

      local selected_file = type(selected_choice) == "table" and selected_choice.filename or nil
      if type(selected_file) ~= "string" or selected_file == "" then
        return
      end

      local cached_loclist_items = resolve_picker_cache_value(active_session.picker_file_loclist_cache, selected_file)
      if type(cached_loclist_items) == "table" then
        active_session.selected_file = selected_file
        vim.fn.setloclist(resolve_review_loclist_winid(active_session), {}, " ", {
          title = "Git Review Hunks",
          items = vim.deepcopy(cached_loclist_items),
          idx = #cached_loclist_items > 0 and 1 or nil,
        })
      else
        sync_loclist_for_selected_file(active_session, selected_file)
      end

      local target_winid = resolve_review_loclist_winid(active_session)
      if type(target_winid) == "number" and target_winid > 0 and vim.api.nvim_win_is_valid(target_winid) then
        vim.api.nvim_set_current_win(target_winid)
      end
      pcall(vim.api.nvim_cmd, { cmd = "edit", args = { selected_file } }, {})

      local first_range = resolve_picker_cache_value(active_session.picker_file_first_hunk_cache, selected_file)
      if not is_valid_hunk_item(first_range) then
        first_range = resolve_first_hunk_range(active_session, selected_file)
      end

      if is_valid_hunk_item(first_range) then
        pcall(vim.api.nvim_win_set_cursor, 0, { first_range.lnum, 0 })
      end

      pcall(refresh_review_navigation_state, active_session, {
        review_quickfix_list_id = nil,
      })

      local scheduled_session = active_session
      vim.schedule(function()
        if current_session ~= scheduled_session then
          return
        end

        pcall(refresh_review_navigation_state, scheduled_session, {
          review_quickfix_list_id = nil,
        })
      end)
    end)
  end

  if type(hunk_highlight) == "table" and type(hunk_highlight.render_current_hunk) == "function" then
    local active_hunk_item = resolve_active_hunk_item(current_session, {
      review_quickfix_list_id = review_quickfix_list_id,
    })
    pcall(hunk_highlight.render_current_hunk, {
      quickfix_list_id = review_quickfix_list_id,
      qf_item = active_hunk_item,
    })
  end
  render_current_buffer_file_hunks(current_session)

  local open_panel_on_start = opts.open_panel_on_start
  if open_panel_on_start == nil then
    open_panel_on_start = require("git-review.config").get_open_comments_panel_on_start()
  end

  current_session.navigation_state = capture_review_navigation_state(current_session, review_quickfix_list_id)

  local function run_thread_panel_refresh(session)
    if current_session ~= session then
      return
    end

    local ok_thread_state, thread_state_or_error = pcall(refresh_thread_panel, session, {
      run_command = run_command,
      resolve_branch = resolve_branch,
      resolve_pr_for_branch = resolve_pr_for_branch,
      fetch_review_threads = fetch_review_threads,
      panel = panel,
    }, {
      open_panel = open_panel_on_start,
      preloaded_pr = session.pr,
    })

    local thread_state = nil
    if ok_thread_state and type(thread_state_or_error) == "table" then
      thread_state = thread_state_or_error
    elseif ok_thread_state then
      thread_state = {
        state = "parse_error",
        message = "Thread panel refresh returned invalid state",
      }
    else
      thread_state = {
        state = "command_error",
        message = "Failed to refresh thread panel: " .. tostring(thread_state_or_error),
      }
    end

    if current_session ~= session then
      return
    end

    session.thread_state = thread_state
    debug_log("thread panel refresh state: " .. tostring(thread_state.state))
  end

  local defer_thread_refresh = opts.defer_thread_refresh
  if defer_thread_refresh == nil then
    local uis = vim.api.nvim_list_uis()
    defer_thread_refresh = type(uis) == "table" and #uis > 0
  end

  if defer_thread_refresh == true then
    current_session.thread_state = {
      state = "pending",
      message = "Thread panel refresh scheduled",
    }
    local scheduled_thread_session = current_session
    vim.schedule(function()
      run_thread_panel_refresh(scheduled_thread_session)
    end)
  else
    run_thread_panel_refresh(current_session)
  end

  local open_pr_info_on_start = opts.open_pr_info_on_start
  if open_pr_info_on_start == nil then
    open_pr_info_on_start = require("git-review.config").get_open_pr_info_on_start()
  end

  if open_pr_info_on_start == true then
    local open_pr_info = opts.open_pr_info or M.open_pr_info
    if type(open_pr_info) == "function" then
      local ok_open_pr_info, open_pr_info_result = pcall(open_pr_info, {
        run_command = run_command,
        resolve_branch = resolve_branch,
        resolve_pr_for_branch = resolve_pr_for_branch,
      })

      if not ok_open_pr_info then
        debug_log("failed to auto-open PR info on start: " .. tostring(open_pr_info_result))
      elseif type(open_pr_info_result) == "table" and open_pr_info_result.state ~= "ok" then
        debug_log(
          "auto-open PR info returned state "
            .. tostring(open_pr_info_result.state)
            .. ": "
            .. tostring(open_pr_info_result.message)
        )
      end
    end
  end

  if thread_refresh_group == nil then
    thread_refresh_group = vim.api.nvim_create_augroup("GitReviewThreadPanel", { clear = true })
  end

  vim.api.nvim_clear_autocmds({ group = thread_refresh_group })
  vim.api.nvim_create_autocmd({ "BufEnter", "CursorMoved", "QuickFixCmdPost", "WinScrolled" }, {
    group = thread_refresh_group,
    callback = function()
      if current_session == nil then
        return
      end

      refresh_review_navigation_state(current_session, {
        review_quickfix_list_id = current_session.review_quickfix_list_id,
      })
    end,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = thread_refresh_group,
    callback = function()
      if current_session == nil then
        return
      end

      render_current_buffer_file_hunks(current_session)
    end,
  })

  return {
    hunks = hunks,
    thread_state = current_session.thread_state and current_session.thread_state.state,
    thread_message = current_session.thread_state and current_session.thread_state.message,
  }
end

function M.start_local(opts)
  opts = opts or {}
  vim.validate({
    opts = { opts, "table" },
  })

  local local_opts = vim.deepcopy(opts)
  if local_opts.diff_command == nil then
    local_opts.diff_command = { "git", "diff", "--no-color", "HEAD" }
  end

  if local_opts.mode == nil then
    local_opts.mode = "local"
  end

  return M.start(local_opts)
end

function M.start_branch(opts)
  opts = opts or {}
  vim.validate({
    opts = { opts, "table" },
    base_ref = { opts.base_ref, "string" },
    head_ref = { opts.head_ref, "string", true },
  })

  local run_command = opts.run_command or require("git-review.system").run
  local head_ref = opts.head_ref or "HEAD"

  local _, base_ref_error = validate_commit_ref(run_command, opts.base_ref, "base")
  if base_ref_error ~= nil then
    return {
      state = "command_error",
      message = base_ref_error,
    }
  end

  local _, head_ref_error = validate_commit_ref(run_command, head_ref, "head")
  if head_ref_error ~= nil then
    return {
      state = "command_error",
      message = head_ref_error,
    }
  end

  local branch_opts = vim.deepcopy(opts)
  branch_opts.diff_command = branch_opts.diff_command
    or { "git", "diff", "--no-color", opts.base_ref .. "..." .. head_ref }
  branch_opts.mode = branch_opts.mode or "branch"
  branch_opts.base_ref = nil
  branch_opts.head_ref = nil

  return M.start(branch_opts)
end

function M.start_range(opts)
  opts = opts or {}
  vim.validate({
    opts = { opts, "table" },
    start_ref = { opts.start_ref, "string" },
    end_ref = { opts.end_ref, "string" },
  })

  local run_command = opts.run_command or require("git-review.system").run
  local review_repo_root = resolve_repo_root(run_command, opts.cwd or vim.loop.cwd())

  local _, start_ref_error = validate_commit_ref(run_command, opts.start_ref, "start")
  if start_ref_error ~= nil then
    return {
      state = "command_error",
      message = start_ref_error,
    }
  end

  local _, end_ref_error = validate_commit_ref(run_command, opts.end_ref, "end")
  if end_ref_error ~= nil then
    return {
      state = "command_error",
      message = end_ref_error,
    }
  end

  local worktree_path = vim.fn.tempname()
  local raw_worktree_result = run_command({ "git", "worktree", "add", "--detach", worktree_path, opts.end_ref })
  local worktree_result, worktree_error = normalize_run_result(raw_worktree_result)
  if not worktree_result then
    return {
      state = "command_error",
      message = "Unable to create range worktree: " .. worktree_error,
    }
  end

  if worktree_result.code ~= 0 then
    local detail = worktree_result.stderr ~= "" and trim(worktree_result.stderr) or "git worktree add failed"
    return {
      state = "command_error",
      message = "Unable to create range worktree: " .. detail,
    }
  end

  local range_opts = vim.deepcopy(opts)
  range_opts.diff_command = { "git", "-C", worktree_path, "diff", "--no-color", opts.start_ref .. "..." .. opts.end_ref }
  range_opts.cwd = worktree_path
  range_opts.repo_root = worktree_path
  range_opts.mode = "range"
  range_opts.range_start = opts.start_ref
  range_opts.range_end = opts.end_ref
  range_opts.review_commit_id = opts.end_ref
  range_opts.review_repo_root = review_repo_root
  range_opts.worktree_path = worktree_path
  range_opts.worktree_owned = true
  range_opts.start_ref = nil
  range_opts.end_ref = nil

  local ok_start, start_result = pcall(M.start, range_opts)
  if ok_start
    and type(start_result) == "table"
    and (type(start_result.state) ~= "string" or start_result.state == "ok")
  then
    return start_result
  end

  local start_error = nil
  if not ok_start then
    start_error = tostring(start_result)
  elseif type(start_result) == "table" then
    start_error = start_result.message or ("Range start failed (state: " .. tostring(start_result.state) .. ")")
  else
    start_error = "Range start returned invalid state"
  end

  local _, cleanup_error = remove_owned_worktree(range_opts, {
    run_command = run_command,
  })
  if cleanup_error ~= nil then
    start_error = start_error .. " Cleanup failed: " .. cleanup_error
  end

  return {
    state = "command_error",
    message = "Unable to start range review: " .. start_error,
  }
end

function M.start_range_picker(opts)
  opts = opts or {}
  vim.validate({
    opts = { opts, "table" },
  })

  local run_command = opts.run_command or require("git-review.system").run

  local function list_range_picker_commits(ref)
    local raw_result = run_command({ "git", "log", "--format=%H%x09%s", ref })
    local result, result_error = normalize_run_result(raw_result)
    if not result then
      return nil, "Unable to load commits for range picker: " .. result_error
    end

    if result.code ~= 0 then
      local detail = result.stderr ~= "" and result.stderr or "git log failed"
      return nil, "Unable to load commits for range picker: " .. detail
    end

    local commits = {}
    for line in string.gmatch(result.stdout, "[^\r\n]+") do
      local sha, subject = line:match("^([^%s]+)%s+(.+)$")
      if type(sha) == "string" and sha ~= "" then
        table.insert(commits, {
          sha = sha,
          short_sha = sha:sub(1, 7),
          subject = type(subject) == "string" and subject or "",
        })
      end
    end

    if #commits == 0 then
      return nil, "Unable to load commits for range picker: no commits found for " .. ref
    end

    return commits
  end

  local function pick_commit(commits, prompt, default_index, on_choice)
    if type(vim.ui) ~= "table" or type(vim.ui.select) ~= "function" then
      on_choice(nil, {
        state = "context_error",
        message = "Commit picker UI is unavailable",
      })
      return
    end

    local choices = {}
    for _, commit in ipairs(commits) do
      table.insert(choices, {
        sha = commit.sha,
        short_sha = commit.short_sha,
        subject = commit.subject,
        label = commit.short_sha .. " " .. commit.subject,
      })
    end

    local ok_select, select_err = pcall(vim.ui.select, choices, {
      prompt = prompt,
      default = default_index,
      format_item = function(choice)
        if type(choice) == "table" and type(choice.label) == "string" then
          return choice.label
        end

        return tostring(choice)
      end,
    }, function(choice)
      if choice == nil then
        on_choice(nil, {
          state = "cancelled",
          message = "Commit range picker cancelled",
        })
        return
      end

      on_choice(choice)
    end)

    if not ok_select then
      on_choice(nil, {
        state = "command_error",
        message = "Commit picker failed: " .. tostring(select_err),
      })
    end
  end

  local on_complete = type(opts.on_complete) == "function" and opts.on_complete or nil
  local completed = false
  local completed_result = nil
  local function finish(result)
    if completed then
      return
    end

    completed = true
    completed_result = result
    if on_complete ~= nil then
      on_complete(result)
    end
  end

  local end_commits, end_error = list_range_picker_commits("HEAD")
  if type(end_commits) ~= "table" then
    return finish({
      state = "command_error",
      message = end_error,
    })
  end

  pick_commit(end_commits, "Select range end", 1, function(selected_end, end_pick_error)
    if selected_end == nil then
      finish(end_pick_error)
      return
    end

    local start_commits, start_error = list_range_picker_commits(selected_end.sha)
    if type(start_commits) ~= "table" then
      finish({
        state = "command_error",
        message = start_error,
      })
      return
    end

    local start_default = start_commits[2] and 2 or 1
    pick_commit(start_commits, "Select range start", start_default, function(selected_start, start_pick_error)
      if selected_start == nil then
        finish(start_pick_error)
        return
      end

      local range_opts = vim.deepcopy(opts)
      range_opts.start_ref = selected_start.sha
      range_opts.end_ref = selected_end.sha
      range_opts.on_complete = nil

      finish(M.start_range(range_opts))
    end)
  end)

  if on_complete ~= nil then
    return {
      state = "pending",
    }
  end

  if completed then
    return completed_result
  end

  return {
    state = "pending",
  }
end

function M.populate_files_quickfix()
  if current_session == nil then
    return {
      state = "context_error",
      message = "No active review session. Run :GitReview start first.",
    }
  end

  local items = build_review_quickfix_items(current_session)
  vim.fn.setqflist({}, " ", {
    title = "Git Review Files",
    items = items,
    idx = resolve_initial_quickfix_index(items),
  })

  local quickfix_list = vim.fn.getqflist({ id = 0 })
  local review_quickfix_list_id = type(quickfix_list) == "table" and quickfix_list.id or nil
  current_session.review_quickfix_list_id = review_quickfix_list_id
  sync_loclist_for_current_quickfix_file(current_session, {
    review_quickfix_list_id = review_quickfix_list_id,
  })
  refresh_review_navigation_state(current_session, {
    force = true,
    review_quickfix_list_id = review_quickfix_list_id,
  })

  return {
    state = "ok",
  }
end

function M.refresh(opts)
  opts = opts or {}
  vim.validate({
    opts = { opts, "table" },
  })

  if next(opts) == nil then
    if current_session == nil then
      return {
        state = "context_error",
        message = "No active review session. Run :GitReview start first.",
      }
    end

    opts = {
      run_command = current_session.run_command,
      parse_diff = current_session.parse_diff,
      resolve_branch = current_session.resolve_branch,
      resolve_pr_for_branch = current_session.resolve_pr_for_branch,
      fetch_review_threads = current_session.fetch_review_threads,
      panel = current_session.panel,
      hunk_highlight = current_session.hunk_highlight,
      diff_command = current_session.diff_command,
      cwd = current_session.cwd,
      repo = current_session.repo,
      mode = current_session.mode,
      range_start = current_session.range_start,
      range_end = current_session.range_end,
      review_commit_id = current_session.review_commit_id,
      review_repo_root = current_session.review_repo_root,
      worktree_path = current_session.worktree_path,
      worktree_owned = current_session.worktree_owned,
      reviewed_files = current_session.reviewed_files,
    }
  end

  local ok_start, start_result = pcall(M.start, opts)
  if not ok_start then
    return {
      state = "command_error",
      message = tostring(start_result),
    }
  end

  if type(start_result) ~= "table" then
    return {
      state = "parse_error",
      message = "Refresh returned invalid session state",
    }
  end

  if start_result.thread_state ~= nil and start_result.thread_state ~= "ok" then
    return {
      state = start_result.thread_state,
      message = start_result.thread_message,
      hunks = start_result.hunks,
    }
  end

  return {
    state = "ok",
    hunks = start_result.hunks,
  }
end

function M.stop(opts)
  opts = opts or {}
  vim.validate({
    opts = { opts, "table" },
  })

  local session_to_stop = current_session

  local hunk_highlight = opts.hunk_highlight
  if hunk_highlight == nil and current_session ~= nil then
    hunk_highlight = current_session.hunk_highlight
  end
  if hunk_highlight == nil then
    local ok, loaded = pcall(require, "git-review.ui.hunk_highlight")
    if ok then
      hunk_highlight = loaded
    end
  end

  if type(hunk_highlight) == "table" and type(hunk_highlight.clear) == "function" then
    pcall(hunk_highlight.clear, { all = true })
  end

  if type(hunk_highlight) == "table" and type(hunk_highlight.clear_all_file_hunks) == "function" then
    pcall(hunk_highlight.clear_all_file_hunks, { all = true })
  end

  if type(hunk_highlight) == "table" and type(hunk_highlight.clear_all_deletions) == "function" then
    pcall(hunk_highlight.clear_all_deletions, { all = true })
  end

  local panel = opts.panel
  if panel == nil and current_session ~= nil then
    panel = current_session.panel
  end
  if panel == nil then
    local ok, loaded = pcall(require, "git-review.ui.panel")
    if ok then
      panel = loaded
    end
  end
  if type(panel) == "table" and type(panel.close) == "function" then
    pcall(panel.close)
  end

  vim.fn.setqflist({}, " ", {
    title = "Git Review Files",
    items = {},
  })

  local loclist_winid = 0
  if session_to_stop ~= nil then
    local review_source_winid = session_to_stop.review_source_winid
    if type(review_source_winid) == "number" and review_source_winid > 0 and vim.api.nvim_win_is_valid(review_source_winid) then
      loclist_winid = review_source_winid
    end
  end

  vim.fn.setloclist(loclist_winid, {}, " ", {
    title = "Git Review Hunks",
    items = {},
  })

  if type(thread_refresh_group) == "number" then
    pcall(vim.api.nvim_clear_autocmds, { group = thread_refresh_group })
  end

  local _, cleanup_error = remove_owned_worktree(session_to_stop, {
    run_command = opts.run_command,
  })

  current_session = nil

  if cleanup_error ~= nil then
    return {
      state = "command_error",
      message = cleanup_error,
    }
  end

  return {
    state = "ok",
  }
end

function M.is_active()
  return current_session ~= nil
end

local function resolve_current_review_file_path(session, opts)
  opts = opts or {}

  local selected_file = nil
  local selected_qf_item = resolve_selected_quickfix_item(session.review_quickfix_list_id)
  selected_file = quickfix_item_path(selected_qf_item)

  if type(selected_file) ~= "string" or selected_file == "" then
    local bufnr = opts.bufnr or 0
    local buffer_name = vim.api.nvim_buf_get_name(bufnr)
    if type(buffer_name) == "string" and buffer_name ~= "" then
      selected_file = buffer_name
    end
  end

  local selected_normalized = normalize_review_file(selected_file)
  if type(selected_normalized) ~= "string" then
    return nil
  end

  local review_idx = find_review_file_index(session, selected_normalized)
  if type(review_idx) ~= "number" then
    return nil
  end

  return selected_normalized
end

local function resolve_pull_request_node_id(session, opts)
  if type(session) ~= "table" then
    return nil
  end

  if type(session.pr) == "table" and type(session.pr.id) == "string" and session.pr.id ~= "" then
    return session.pr.id
  end

  local resolve_branch = opts.resolve_branch or session.resolve_branch
  local resolve_pr_for_branch = opts.resolve_pr_for_branch or session.resolve_pr_for_branch
  local run_command = opts.run_command or session.run_command
  if type(resolve_branch) ~= "function" or type(resolve_pr_for_branch) ~= "function" or type(run_command) ~= "function" then
    return nil
  end

  local branch = resolve_branch(run_command)
  if type(branch) ~= "string" or branch == "" then
    return nil
  end

  local pr_result = resolve_pr_for_branch(branch, run_command)
  if type(pr_result) ~= "table" or pr_result.state ~= "single_pr" or type(pr_result.pr) ~= "table" then
    return nil
  end

  if type(pr_result.pr.id) == "string" and pr_result.pr.id ~= "" then
    session.pr = pr_result.pr
    session.pr_number = pr_result.pr.number
    return pr_result.pr.id
  end

  return nil
end

local function should_sync_progress_to_github(session)
  if type(session) ~= "table" then
    return false
  end

  if session.mode == "range" or session.mode == "local" or session.mode == "branch" then
    return false
  end

  local cfg = require("git-review.config").get()
  return type(cfg) == "table"
    and type(cfg.progress) == "table"
    and cfg.progress.github_sync == true
end

local function sync_file_viewed_state(session, opts)
  opts = opts or {}
  if should_sync_progress_to_github(session) ~= true then
    return nil
  end

  local pull_request_id = resolve_pull_request_node_id(session, opts)
  if type(pull_request_id) ~= "string" or pull_request_id == "" then
    return {
      state = "context_error",
      message = "Unable to resolve pull request node id for viewed sync",
    }
  end

  local path = opts.path
  if type(path) ~= "string" or path == "" then
    return {
      state = "context_error",
      message = "Unable to resolve file path for viewed sync",
    }
  end

  local repo_root = session.repo_root
  local relative_path = resolve_repo_relative_path(path, repo_root)
  if type(relative_path) ~= "string" or relative_path == "" then
    relative_path = path
  end

  if opts.reviewed == true then
    local mark_file_viewed = opts.mark_file_viewed or require("git-review.github").mark_file_viewed
    return mark_file_viewed(pull_request_id, relative_path, opts.send)
  end

  local unmark_file_viewed = opts.unmark_file_viewed or require("git-review.github").unmark_file_viewed
  return unmark_file_viewed(pull_request_id, relative_path, opts.send)
end

function M.toggle_current_file_reviewed(opts)
  opts = opts or {}
  vim.validate({
    opts = { opts, "table" },
  })

  if current_session == nil then
    return {
      state = "context_error",
      message = "No active review session. Run :GitReview start first.",
    }
  end

  local path = resolve_current_review_file_path(current_session, opts)
  if type(path) ~= "string" then
    return {
      state = "context_error",
      message = "Current file is not part of the active review.",
    }
  end

  current_session.reviewed_files = current_session.reviewed_files or {}
  local reviewed = current_session.reviewed_files[path] ~= true
  if reviewed then
    current_session.reviewed_files[path] = true
  else
    current_session.reviewed_files[path] = nil
  end

  refresh_review_quickfix_markers(current_session)

  local sync_state = sync_file_viewed_state(current_session, {
    path = path,
    reviewed = reviewed,
    mark_file_viewed = opts.mark_file_viewed,
    unmark_file_viewed = opts.unmark_file_viewed,
    run_command = opts.run_command,
    resolve_branch = opts.resolve_branch,
    resolve_pr_for_branch = opts.resolve_pr_for_branch,
    send = opts.send,
  })

  local synced = nil
  if type(sync_state) == "table" then
    synced = sync_state.state == "ok"
    if synced ~= true then
      vim.notify("GitReview: viewed sync failed: " .. tostring(sync_state.message or sync_state.state), vim.log.levels.WARN)
    end
  end

  return {
    state = "ok",
    path = path,
    reviewed = reviewed,
    synced = synced,
  }
end

function M.review_progress(opts)
  opts = opts or {}
  vim.validate({
    opts = { opts, "table" },
  })

  if current_session == nil then
    return {
      state = "context_error",
      message = "No active review session. Run :GitReview start first.",
    }
  end

  local total = type(current_session.review_file_order) == "table" and #current_session.review_file_order or 0
  local reviewed = 0
  if type(current_session.reviewed_files) == "table" and type(current_session.review_file_order) == "table" then
    for _, path in ipairs(current_session.review_file_order) do
      if current_session.reviewed_files[path] == true then
        reviewed = reviewed + 1
      end
    end
  end

  return {
    state = "ok",
    reviewed = reviewed,
    total = total,
    remaining = math.max(0, total - reviewed),
  }
end

function M.goto_next_unreviewed_file(opts)
  opts = opts or {}
  vim.validate({
    opts = { opts, "table" },
  })

  if current_session == nil then
    return {
      state = "context_error",
      message = "No active review session. Run :GitReview start first.",
    }
  end

  local review_file_order = current_session.review_file_order
  if type(review_file_order) ~= "table" or #review_file_order == 0 then
    return {
      state = "context_error",
      message = "No review files available.",
    }
  end

  local current_path = resolve_current_review_file_path(current_session, opts)
  local start_index = 0
  if type(current_path) == "string" then
    local current_index = find_review_file_index(current_session, current_path)
    if type(current_index) == "number" then
      start_index = current_index
    end
  end

  local target = nil
  for idx = start_index + 1, #review_file_order do
    local path = review_file_order[idx]
    if not is_reviewed_file(current_session, path) then
      target = path
      break
    end
  end

  if type(target) ~= "string" then
    return {
      state = "ok",
      done = true,
    }
  end

  sync_loclist_for_selected_file(current_session, target)
  local target_winid = resolve_review_loclist_winid(current_session)
  if type(target_winid) == "number" and target_winid > 0 and vim.api.nvim_win_is_valid(target_winid) then
    vim.api.nvim_set_current_win(target_winid)
  end

  pcall(vim.api.nvim_cmd, { cmd = "edit", args = { target } }, {})

  local first_range = resolve_first_hunk_range(current_session, target)
  if is_valid_hunk_item(first_range) then
    pcall(vim.api.nvim_win_set_cursor, 0, { first_range.lnum, 0 })
  end

  pcall(refresh_review_navigation_state, current_session, {
    review_quickfix_list_id = current_session.review_quickfix_list_id,
  })

  return {
    state = "ok",
    done = false,
    path = target,
  }
end

function M.open_panel(opts)
  opts = opts or {}
  vim.validate({
    opts = { opts, "table" },
  })

  if current_session == nil then
    return {
      state = "context_error",
      message = "No active review session. Run :GitReview start first.",
    }
  end

  local thread_state = refresh_thread_panel(current_session, {
    run_command = opts.run_command or current_session.run_command,
    resolve_branch = opts.resolve_branch or current_session.resolve_branch,
    resolve_pr_for_branch = opts.resolve_pr_for_branch or current_session.resolve_pr_for_branch,
    fetch_review_threads = opts.fetch_review_threads or current_session.fetch_review_threads,
    panel = opts.panel or current_session.panel,
  }, {
    open_panel = true,
  })
  current_session.thread_state = thread_state

  if thread_state.state ~= "ok" then
    return thread_state
  end

  return {
    state = "ok",
  }
end

local function resolve_requested_panel_scope(scope)
  if scope == nil then
    return "current"
  end

  if scope == "current" or scope == "all" then
    return scope
  end

  return nil
end

local function resolve_current_panel_path(session, opts)
  local context_path, context_error = resolve_context_path_from_buffer({
    bufnr = opts.bufnr,
    repo_root = session.repo_root,
  })
  if context_path then
    return context_path, nil
  end

  return nil, context_error
end

local function notify_thread_fetch_error(state)
  local message = type(state) == "table" and state.message or "Unable to load review threads"
  vim.notify("GitReview: failed to fetch comments: " .. tostring(message), vim.log.levels.ERROR)
end

local function refresh_panel_threads_async(session, deps)
  if session.threads_fetch_in_flight == true then
    return
  end

  session.threads_fetch_in_flight = true
  vim.notify("GitReview: fetching comments...", vim.log.levels.INFO)

  vim.schedule(function()
    if current_session ~= session then
      session.threads_fetch_in_flight = false
      return
    end

    local ok_thread_state, thread_state_or_error = pcall(refresh_session_threads, session, deps, {
      preloaded_pr = session.pr,
    })

    local thread_state = nil
    if ok_thread_state and type(thread_state_or_error) == "table" then
      thread_state = thread_state_or_error
    elseif ok_thread_state then
      thread_state = {
        state = "parse_error",
        message = "Thread panel refresh returned invalid state",
      }
    else
      thread_state = {
        state = "command_error",
        message = "Failed to refresh thread panel: " .. tostring(thread_state_or_error),
      }
    end

    session.thread_state = thread_state
    session.threads_fetch_in_flight = false

    if thread_state.state ~= "ok" then
      notify_thread_fetch_error(thread_state)
      return
    end

    local render_state = rerender_thread_panel_from_session(session, {
      panel = session.panel,
      scope = session.panel_scope,
      panel_current_path = session.panel_current_path,
    })
    if render_state.state ~= "ok" then
      notify_thread_fetch_error(render_state)
    end
  end)
end

function M.open_panel_toggle(opts)
  opts = opts or {}
  vim.validate({
    opts = { opts, "table" },
    scope = { opts.scope, "string", true },
  })

  if current_session == nil then
    return {
      state = "context_error",
      message = "No active review session. Run :GitReview start first.",
    }
  end

  local scope = resolve_requested_panel_scope(opts.scope)
  if scope == nil then
    return {
      state = "context_error",
      message = "scope must be 'current' or 'all'",
    }
  end

  local panel = opts.panel or current_session.panel
  if type(panel) ~= "table" or type(panel.render) ~= "function" then
    return {
      state = "context_error",
      message = "Review panel is unavailable",
    }
  end

  current_session.panel = panel

  local panel_current_path = nil
  if scope == "current" then
    panel_current_path = opts.path
    if type(panel_current_path) ~= "string" or panel_current_path == "" then
      panel_current_path = nil
      local resolved_path, path_error = resolve_current_panel_path(current_session, opts)
      if resolved_path then
        panel_current_path = resolved_path
      elseif type(path_error) == "string" and path_error ~= "" then
        vim.notify("GitReview: " .. path_error, vim.log.levels.WARN)
      end
    end
  end

  local panel_is_open = false
  if type(panel.is_open) == "function" then
    local ok_is_open, is_open = pcall(panel.is_open)
    panel_is_open = ok_is_open and is_open == true
  end

  local same_scope = current_session.panel_scope == scope
  if same_scope and scope == "current" then
    same_scope = current_session.panel_current_path == panel_current_path
  end

  if panel_is_open and same_scope and type(panel.close) == "function" then
    pcall(panel.close)
    return {
      state = "ok",
    }
  end

  current_session.panel_scope = scope
  current_session.panel_current_path = panel_current_path

  local render_state = rerender_thread_panel_from_session(current_session, {
    panel = panel,
    scope = scope,
    panel_current_path = panel_current_path,
    open_panel = true,
  })
  if render_state.state ~= "ok" then
    return render_state
  end

  refresh_panel_threads_async(current_session, {
    run_command = opts.run_command or current_session.run_command,
    resolve_branch = opts.resolve_branch or current_session.resolve_branch,
    resolve_pr_for_branch = opts.resolve_pr_for_branch or current_session.resolve_pr_for_branch,
    fetch_review_threads = opts.fetch_review_threads or current_session.fetch_review_threads,
  })

  return {
    state = "ok",
  }
end

local function run_deletion_block_command(opts, api_name, action_label)
  opts = opts or {}
  vim.validate({
    opts = { opts, "table" },
  })

  if current_session == nil then
    return {
      state = "context_error",
      message = "No active review session. Run :GitReview start first.",
    }
  end

  local hunk_highlight = current_session.hunk_highlight
  local api = type(hunk_highlight) == "table" and hunk_highlight[api_name] or nil
  if type(api) ~= "function" then
    return {
      state = "context_error",
      message = "Hunk highlight does not support " .. action_label,
    }
  end

  local ok_call, call_result = pcall(api, opts)
  if not ok_call then
    return {
      state = "command_error",
      message = "Failed to " .. action_label .. ": " .. tostring(call_result),
    }
  end

  return {
    state = "ok",
  }
end

function M.toggle_current_deletion_block(opts)
  return run_deletion_block_command(opts, "toggle_current_block", "toggle current deletion block")
end

function M.expand_deletion_blocks(opts)
  return run_deletion_block_command(opts, "expand_all_blocks", "expand deletion blocks")
end

function M.collapse_deletion_blocks(opts)
  return run_deletion_block_command(opts, "collapse_all_blocks", "collapse deletion blocks")
end

function M.toggle_deletion_blocks(opts)
  opts = opts or {}
  vim.validate({
    opts = { opts, "table" },
  })

  if current_session == nil then
    return {
      state = "context_error",
      message = "No active review session. Run :GitReview start first.",
    }
  end

  local hunk_highlight = current_session.hunk_highlight
  local resolve_mode = type(hunk_highlight) == "table" and hunk_highlight.get_deletion_toggle_mode or nil
  if type(resolve_mode) ~= "function" then
    return {
      state = "context_error",
      message = "Hunk highlight does not support deletion mode toggling",
    }
  end

  local ok_mode, mode = pcall(resolve_mode, opts)
  if not ok_mode then
    return {
      state = "command_error",
      message = "Failed to resolve deletion block toggle mode: " .. tostring(mode),
    }
  end

  if mode == "expand" then
    return M.expand_deletion_blocks(opts)
  end

  if mode == "collapse" then
    return M.collapse_deletion_blocks(opts)
  end

  if mode == nil then
    return {
      state = "ok",
    }
  end

  return {
    state = "context_error",
    message = "No deletion blocks available to toggle",
  }
end

function M.toggle_resolved_thread_visibility(opts)
  opts = opts or {}
  vim.validate({
    opts = { opts, "table" },
  })

  if current_session == nil then
    return {
      state = "context_error",
      message = "No active review session. Run :GitReview start first.",
    }
  end

  local panel = opts.panel or current_session.panel
  if type(panel) ~= "table" or type(panel.toggle_show_resolved_bodies) ~= "function" then
    return {
      state = "context_error",
      message = "Review panel does not support resolved-thread toggling",
    }
  end

  local ok_toggle, show_resolved_bodies = pcall(panel.toggle_show_resolved_bodies)
  if not ok_toggle then
    return {
      state = "command_error",
      message = "Failed to toggle resolved-thread visibility: " .. tostring(show_resolved_bodies),
    }
  end

  local render_state = rerender_thread_panel_from_session(current_session, {
    panel = panel,
    show_resolved_bodies = show_resolved_bodies,
  })
  if render_state.state ~= "ok" then
    return render_state
  end

  return {
    state = "ok",
    show_resolved_bodies = show_resolved_bodies,
  }
end

function M.submit_review(opts)
  opts = opts or {}
  vim.validate({
    opts = { opts, "table" },
  })

  local range_mode_state = readonly_mode_unsupported("submit_review")
  if range_mode_state ~= nil then
    return range_mode_state
  end

  if opts.body ~= nil and type(opts.body) ~= "string" then
    error("body must be a string when provided")
  end

  if opts.event ~= "APPROVE" and opts.event ~= "REQUEST_CHANGES" then
    return {
      state = "context_error",
      message = "event must be APPROVE or REQUEST_CHANGES",
    }
  end

  local repo = opts.repo or (current_session and current_session.repo)
  local pr_number = opts.pr_number or (current_session and current_session.pr_number)
  local pr_resolution_error = nil

  if pr_number == nil and current_session and current_session.run_command then
    local pr_state = resolve_single_pr(
      current_session.run_command,
      current_session.resolve_branch,
      current_session.resolve_pr_for_branch
    )

    if pr_state.state == "ok" then
      current_session.pr = pr_state.pr
      current_session.pr_number = pr_state.pr.number
      pr_number = pr_state.pr.number
    else
      current_session.pr = nil
      current_session.pr_number = nil
      pr_resolution_error = {
        state = pr_state.state or "context_error",
        message = pr_state.message or ("Unable to resolve pull request for review submission (state: " .. tostring(pr_state.state) .. ")"),
      }
    end
  end

  if type(repo) ~= "string" or repo == "" then
    return {
      state = "context_error",
      message = "repo is required to submit review",
    }
  end

  if type(pr_number) ~= "number" then
    if pr_resolution_error ~= nil then
      return pr_resolution_error
    end

    return {
      state = "context_error",
      message = "pr_number is required to submit review",
    }
  end

  local submit_review = opts.submit_review or require("git-review.github").submit_review
  return submit_review({
    repo = repo,
    pr_number = pr_number,
    event = opts.event,
    body = opts.body,
  }, opts.send)
end

function M.create_comment(opts)
  opts = opts or {}
  local range_mode_state = readonly_mode_unsupported("create_comment")
  if range_mode_state ~= nil then
    return range_mode_state
  end

  vim.validate({
    opts = { opts, "table" },
    body = { opts.body, "string" },
  })

  local context, context_error = resolve_comment_context(opts)
  if not context then
    return {
      state = "context_error",
      message = context_error,
    }
  end

  local diff_text = opts.diff_text or (current_session and current_session.diff_text)
  if type(diff_text) ~= "string" or diff_text == "" then
    return {
      state = "context_error",
      message = "No diff text available for position mapping",
    }
  end

  local positions = opts.positions or require("git-review.positions")
  local mapped
  local map_error

  if context.start_line == context.end_line then
    mapped, map_error = positions.map_line(diff_text, context.path, context.start_line)
  else
    mapped, map_error = positions.map_range(diff_text, context.path, context.start_line, context.end_line)
  end

  if not mapped then
    return {
      state = "position_error",
      message = map_error,
    }
  end

  if opts.pr_number == nil and current_session and current_session.run_command then
    local pr_state = resolve_single_pr(
      current_session.run_command,
      current_session.resolve_branch,
      current_session.resolve_pr_for_branch
    )

    if pr_state.state == "ok" then
      current_session.pr = pr_state.pr
      current_session.pr_number = pr_state.pr.number
    else
      current_session.pr = nil
      current_session.pr_number = nil
    end
  end

  local comment_payload = {
    repo = opts.repo or (current_session and current_session.repo),
    pr_number = opts.pr_number or (current_session and current_session.pr_number),
    commit_id = opts.commit_id or (current_session and current_session.commit_id),
    body = opts.body,
    path = context.path,
    position = mapped.position,
  }

  if (type(comment_payload.repo) ~= "string" or comment_payload.repo == "") and current_session and current_session.run_command then
    comment_payload.repo = resolve_repo_slug(current_session.run_command)
    current_session.repo = comment_payload.repo
  end

  if (type(comment_payload.commit_id) ~= "string" or comment_payload.commit_id == "") and current_session and current_session.run_command then
    comment_payload.commit_id = resolve_head_commit(current_session.run_command)
    current_session.commit_id = comment_payload.commit_id
  end

  if mapped.start_position ~= nil and mapped.start_position ~= mapped.position then
    comment_payload.start_position = mapped.start_position
  end

  if type(comment_payload.repo) ~= "string" or comment_payload.repo == "" then
    return {
      state = "context_error",
      message = "repo is required to create comments",
    }
  end

  if type(comment_payload.pr_number) ~= "number" then
    return {
      state = "context_error",
      message = "pr_number is required to create comments",
    }
  end

  if type(comment_payload.commit_id) ~= "string" or comment_payload.commit_id == "" then
    return {
      state = "context_error",
      message = "commit_id is required to create comments",
    }
  end

  local create_review_comment = opts.create_review_comment or require("git-review.github").create_review_comment
  return create_review_comment(comment_payload, opts.send)
end

local function resolve_reaction_content(value)
  local github = require("git-review.github")
  if type(github.normalize_reaction_content) == "function" then
    return github.normalize_reaction_content(value)
  end

  return nil
end

function M.reply_to_selected_thread(opts)
  opts = opts or {}
  vim.validate({
    opts = { opts, "table" },
  })

  local range_mode_state = readonly_mode_unsupported("reply_to_selected_thread")
  if range_mode_state ~= nil then
    return range_mode_state
  end

  local panel = opts.panel or require("git-review.ui.panel")
  local has_explicit_selection_context = opts.cursor_line ~= nil or opts.bufnr ~= nil
  local selected_thread_id = opts.thread_id
  if selected_thread_id == nil and type(panel) == "table" and type(panel.get_selected_thread_id) == "function" then
    selected_thread_id = panel.get_selected_thread_id({
      bufnr = opts.bufnr,
      cursor_line = opts.cursor_line,
    })
  end

  if selected_thread_id == nil and current_session ~= nil and opts.auto_open_panel ~= false then
    local open_state = M.open_panel({
      panel = panel,
      run_command = opts.run_command,
      resolve_branch = opts.resolve_branch,
      resolve_pr_for_branch = opts.resolve_pr_for_branch,
      fetch_review_threads = opts.fetch_review_threads,
    })
    if type(open_state) == "table" and open_state.state ~= "ok" then
      return open_state
    end

    if has_explicit_selection_context and type(panel) == "table" and type(panel.get_selected_thread_id) == "function" then
      selected_thread_id = panel.get_selected_thread_id({
        bufnr = opts.bufnr,
        cursor_line = opts.cursor_line,
      })
    end
  end

  if type(selected_thread_id) ~= "string" or selected_thread_id == "" then
    return {
      state = "context_error",
      message = "No review thread selected",
    }
  end

  local body = opts.body
  if body == nil then
    local input = opts.input or vim.fn.input
    body = input("Reply: ")
  end

  if type(body) ~= "string" or trim(body) == "" then
    return {
      state = "context_error",
      message = "Reply body is required",
    }
  end

  local reply_to_thread = opts.reply_to_thread or require("git-review.github").reply_to_thread
  return reply_to_thread(selected_thread_id, body, opts.send)
end

function M.react_to_selected_thread(opts)
  opts = opts or {}
  vim.validate({
    opts = { opts, "table" },
  })

  local range_mode_state = readonly_mode_unsupported("react_to_selected_thread")
  if range_mode_state ~= nil then
    return range_mode_state
  end

  local panel = opts.panel or require("git-review.ui.panel")
  local selected_thread_id = opts.thread_id
  if selected_thread_id == nil and type(panel) == "table" and type(panel.get_selected_thread_id) == "function" then
    selected_thread_id = panel.get_selected_thread_id({
      bufnr = opts.bufnr,
      cursor_line = opts.cursor_line,
    })
  end

  if type(selected_thread_id) ~= "string" or selected_thread_id == "" then
    return {
      state = "context_error",
      message = "No review thread selected",
    }
  end

  if opts.reaction == nil then
    return {
      state = "cancelled",
      message = "Reaction selection cancelled",
    }
  end

  local normalized_reaction = resolve_reaction_content(opts.reaction)
  if normalized_reaction == nil then
    return {
      state = "context_error",
      message = "Invalid reaction selection",
    }
  end

  local add_thread_reaction = opts.add_thread_reaction or require("git-review.github").add_thread_reaction
  return add_thread_reaction(selected_thread_id, normalized_reaction, opts.send)
end

function M.open_pr_info(opts)
  opts = opts or {}
  vim.validate({
    opts = { opts, "table" },
  })

  local render_pr_info = opts.render_pr_info or require("git-review.ui.pr_info").render
  local run_command = opts.run_command
    or (current_session and current_session.run_command)
    or require("git-review.system").run
  local resolve_branch = opts.resolve_branch
    or (current_session and current_session.resolve_branch)
    or resolve_current_branch
  local resolve_pr_for_branch = opts.resolve_pr_for_branch
    or (current_session and current_session.resolve_pr_for_branch)
    or require("git-review.github").resolve_pr_for_branch

  local pr = opts.pr
  if type(pr) ~= "table" then
    pr = current_session and current_session.pr or nil
  end

  if type(pr) ~= "table" then
    local pr_state = resolve_single_pr(run_command, resolve_branch, resolve_pr_for_branch)
    if pr_state.state ~= "ok" then
      return pr_state
    end

    pr = pr_state.pr
    if current_session ~= nil then
      current_session.pr = pr
      current_session.pr_number = pr.number
    end
  end

  local ok_render, render_result = pcall(render_pr_info, pr, {
    bufnr = opts.bufnr,
    winid = opts.winid,
  })
  if not ok_render then
    return {
      state = "command_error",
      message = "Failed to render pull request info: " .. tostring(render_result),
    }
  end

  local state = {
    state = "ok",
    pr = pr,
  }

  if type(render_result) == "table" then
    state.bufnr = render_result.bufnr
    state.winid = render_result.winid
  end

  return state
end

return M
