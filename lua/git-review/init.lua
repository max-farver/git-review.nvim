local M = {}

local ACTIVE_SUBCOMMANDS = {
  "stop",
  "refresh",
  "files",
  "panel",
  "panel-all",
  "info",
  "comment",
  "reply",
  "react",
  "submit",
  "toggle-resolved",
  "toggle-deletion-block",
  "toggle-deletions",
  "expand-deletion-blocks",
  "collapse-deletion-blocks",
}

local INACTIVE_SUBCOMMANDS = {
  "start",
  "local",
  "branch",
  "range",
}

local ACTIVE_SUBCOMMAND_LOOKUP = {}
for _, subcommand in ipairs(ACTIVE_SUBCOMMANDS) do
  ACTIVE_SUBCOMMAND_LOOKUP[subcommand] = true
end

local ACTIVE_KEYMAPS = {}
local DEFAULT_KEYMAPS = {}
local load_session_or_notify
local register_default_keymaps

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function build_actionable_message(command_name, result)
  if type(result) ~= "table" then
    return command_name .. " failed: unexpected result"
  end

  local message = type(result.message) == "string" and trim(result.message) or ""
  if message == "" then
    message = "unknown error"
  end

  if result.state == "no_pr" then
    return command_name
      .. " failed: "
      .. message
      .. ". Push your branch and open a pull request, then run :GitReview refresh."
  end

  if result.state == "context_error" then
    if message == "No diff text available for position mapping"
      or message == "pr_number is required to create comments"
      or message == "repo is required to create comments"
      or message == "commit_id is required to create comments"
    then
      return command_name
        .. " failed: "
        .. message
        .. ". Run :GitReview start on a pull request branch, then run :GitReview refresh."
    end

    return command_name .. " failed: " .. message
  end

  if result.state == "position_error" then
    return command_name
      .. " failed: "
      .. message
      .. ". Your local diff may be stale; run :GitReview refresh and try again."
  end

  if result.state == "command_error" then
    local lower = string.lower(message)
    if string.find(lower, "gh auth", 1, true)
      or string.find(lower, "authenticate", 1, true)
      or string.find(lower, "not logged into", 1, true)
    then
      return command_name
        .. " failed: "
        .. message
        .. ". Verify GitHub CLI auth with 'gh auth status', then run 'gh auth login'."
    end

    return command_name .. " failed: " .. message
  end

  return command_name .. " failed: " .. message
end

local function notify_result(command_name, result)
  if type(result) == "table" and result.state == "ok" then
    return
  end

  vim.notify(build_actionable_message(command_name, result), vim.log.levels.ERROR)
end

local function run_session_command(command_name, callback)
  local ok, result = pcall(callback)
  if not ok then
    vim.notify(command_name .. " failed: " .. tostring(result), vim.log.levels.ERROR)
    return false, result
  end

  notify_result(command_name, result)
  return type(result) == "table" and result.state == "ok", result
end

local function evaluate_start_like_result(command_name, result)
  if type(result) == "table" and type(result.state) == "string" and result.state ~= "ok" then
    if result.state == "cancelled" or result.state == "pending" then
      return false, result
    end

    notify_result(command_name, result)
    return false, result
  end

  if type(result) == "table" then
    return true, result
  end

  vim.notify(command_name .. " failed: unexpected result", vim.log.levels.ERROR)
  return false, result
end

local function run_start_like_command(command_name, callback, panic_suffix)
  local ok, result = pcall(callback)
  if not ok then
    local suffix = type(panic_suffix) == "string" and panic_suffix or ""
    vim.notify(command_name .. " failed: " .. tostring(result) .. suffix, vim.log.levels.ERROR)
    return false, result
  end

  return evaluate_start_like_result(command_name, result)
end

local function prompt_for_body(prompt_text)
  local body = vim.fn.input(prompt_text)
  if type(body) ~= "string" or trim(body) == "" then
    return nil
  end

  return body
end

local function prompt_for_submit_event(on_choice)
  local ui = type(vim.ui) == "table" and vim.ui or nil
  if type(ui) == "table" and type(ui.select) == "function" then
    ui.select({ "APPROVE", "REQUEST_CHANGES" }, {
      prompt = "Submit review as:",
    }, function(choice)
      on_choice(choice)
    end)
    return
  end

  local selection = vim.fn.inputlist({
    "Submit review as:",
    "1. APPROVE",
    "2. REQUEST_CHANGES",
    "0. Cancel",
  })

  if selection == 1 then
    on_choice("APPROVE")
    return
  end

  if selection == 2 then
    on_choice("REQUEST_CHANGES")
    return
  end

  on_choice(nil)
end

local REACTION_OPTIONS = {
  { label = "👍  Thumbs up", value = "THUMBS_UP" },
  { label = "👎  Thumbs down", value = "THUMBS_DOWN" },
  { label = "🔥  Hooray", value = "HOORAY" },
  { label = "✅  Rocket", value = "ROCKET" },
  { label = "👀  Eyes", value = "EYES" },
  { label = "❤️  Heart", value = "HEART" },
}

local function prompt_for_reaction(on_choice)
  local ui = type(vim.ui) == "table" and vim.ui or nil
  if type(ui) == "table" and type(ui.select) == "function" then
    ui.select(REACTION_OPTIONS, {
      prompt = "React with:",
      format_item = function(item)
        if type(item) == "table" and type(item.label) == "string" then
          return item.label
        end

        return tostring(item)
      end,
    }, function(choice)
      if type(choice) == "table" then
        on_choice(choice.value)
        return
      end

      on_choice(nil)
    end)
    return
  end

  on_choice(nil)
end

local function run_submit_review_action()
  prompt_for_submit_event(function(event)
    if event ~= "APPROVE" and event ~= "REQUEST_CHANGES" then
      return
    end

    local body = prompt_for_body("Review message (optional): ")
    run_session_command("GitReviewSubmit", function()
      return require("git-review.session").submit_review({
        event = event,
        body = body,
      })
    end)
  end)
end

local function run_react_action()
  prompt_for_reaction(function(reaction)
    if reaction == nil then
      return
    end

    local ok, result = pcall(function()
      return require("git-review.session").react_to_selected_thread({
        reaction = reaction,
      })
    end)

    if not ok then
      vim.notify("GitReviewReact failed: " .. tostring(result), vim.log.levels.ERROR)
      return
    end

    if type(result) == "table" and result.state == "cancelled" then
      return
    end

    notify_result("GitReviewReact", result)
  end)
end

local function resolve_visual_range()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_line = type(start_pos) == "table" and start_pos[2] or nil
  local end_line = type(end_pos) == "table" and end_pos[2] or nil

  if type(start_line) ~= "number" or start_line <= 0 or type(end_line) ~= "number" or end_line <= 0 then
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = type(cursor) == "table" and cursor[1] or 1
    return line, line
  end

  return math.min(start_line, end_line), math.max(start_line, end_line)
end

local function run_visual_comment_action()
  local body = prompt_for_body("Comment: ")
  if body == nil then
    vim.notify("GitReviewComment failed: comment body is required", vim.log.levels.ERROR)
    return
  end

  local start_line, end_line = resolve_visual_range()
  run_session_command("GitReviewComment", function()
    return require("git-review.session").create_comment({
      body = body,
      context = {
        start_line = start_line,
        end_line = end_line,
      },
    })
  end)
end

local function run_context_aware_action()
  local session = require("git-review.session")
  local panel = require("git-review.ui.panel")
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = type(cursor) == "table" and cursor[1] or nil

  local thread_id = nil
  if type(panel) == "table" and type(panel.get_selected_thread_id) == "function" and type(cursor_line) == "number" then
    thread_id = panel.get_selected_thread_id({
      bufnr = bufnr,
      cursor_line = cursor_line,
    })
  end

  if type(thread_id) == "string" and thread_id ~= "" then
    run_session_command("GitReviewReply", function()
      return session.reply_to_selected_thread({ thread_id = thread_id })
    end)
    return
  end

  local body = prompt_for_body("Comment: ")
  if body == nil then
    vim.notify("GitReviewComment failed: comment body is required", vim.log.levels.ERROR)
    return
  end

  run_session_command("GitReviewComment", function()
    return session.create_comment({
      body = body,
      context = {
        start_line = cursor_line,
        end_line = cursor_line,
      },
    })
  end)
end

local function unregister_tracked_keymaps(entries)
  for _, entry in ipairs(entries) do
    pcall(vim.keymap.del, entry.mode, entry.lhs)
    if type(entry.previous) == "table" then
      local rhs = nil
      if type(entry.previous.callback) == "function" then
        rhs = entry.previous.callback
      elseif type(entry.previous.rhs) == "string" and entry.previous.rhs ~= "" then
        rhs = entry.previous.rhs
      end

      if rhs ~= nil then
        local restore_opts = {
          desc = entry.previous.desc,
          expr = entry.previous.expr == 1,
          nowait = entry.previous.nowait == 1,
          remap = entry.previous.noremap == 0,
          script = entry.previous.script == 1,
          silent = entry.previous.silent == 1,
        }

        if entry.previous_buffer_local == true and type(entry.previous_bufnr) == "number" then
          if vim.api.nvim_buf_is_valid(entry.previous_bufnr) then
            restore_opts.buffer = entry.previous_bufnr
          end
        end

        pcall(vim.keymap.set, entry.mode, entry.previous.lhs or entry.lhs, rhs, restore_opts)
      end
    end
  end

  return {}
end

local function set_tracked_keymap(entries, mode, lhs, rhs, desc)
  local current_buf = vim.api.nvim_get_current_buf()
  local previous = vim.fn.maparg(lhs, mode, false, true)
  if type(previous) ~= "table" or previous.lhs == nil or previous.lhs == "" then
    local resolved_lhs = vim.api.nvim_replace_termcodes(lhs, true, true, true)
    previous = vim.fn.maparg(resolved_lhs, mode, false, true)
  end

  local previous_buffer_local = false
  if type(previous) ~= "table" or type(previous.lhs) ~= "string" or previous.lhs == "" then
    previous = nil
  else
    previous_buffer_local = previous.buffer == 1
  end

  vim.keymap.set(mode, lhs, rhs, {
    silent = true,
    desc = desc,
  })

  table.insert(entries, {
    mode = mode,
    lhs = lhs,
    previous = previous,
    previous_buffer_local = previous_buffer_local,
    previous_bufnr = previous_buffer_local and current_buf or nil,
  })
end

local function unregister_active_keymaps()
  ACTIVE_KEYMAPS = unregister_tracked_keymaps(ACTIVE_KEYMAPS)
end

local function unregister_default_keymaps()
  DEFAULT_KEYMAPS = unregister_tracked_keymaps(DEFAULT_KEYMAPS)
end

local function session_is_active(session)
  return type(session) == "table" and type(session.is_active) == "function" and session.is_active() == true
end

local function reconcile_active_keymaps(session)
  local is_active = session_is_active(session)
  if not is_active and #ACTIVE_KEYMAPS > 0 then
    unregister_active_keymaps()
    register_default_keymaps()
  end

  return is_active
end

local function register_active_keymaps()
  local cfg = require("git-review.config").get()
  local keymaps = type(cfg) == "table" and cfg.keymaps or nil
  if type(keymaps) ~= "table" or keymaps.enabled ~= true then
    return
  end

  unregister_active_keymaps()
  unregister_default_keymaps()

  local prefix = type(keymaps.prefix) == "string" and keymaps.prefix or ""
  local normal = type(keymaps.normal) == "table" and keymaps.normal or {}
  local visual = type(keymaps.visual) == "table" and keymaps.visual or {}

  local function map_active_if_enabled(mode, suffix, rhs, desc)
    if suffix == nil or suffix == false then
      return
    end

    local lhs = prefix .. suffix
    set_tracked_keymap(ACTIVE_KEYMAPS, mode, lhs, rhs, desc)
  end

  map_active_if_enabled("n", normal.start, function()
    local session = load_session_or_notify("toggle")
    if session == nil then
      return
    end

    if session_is_active(session) then
      vim.cmd("GitReview stop")
      return
    end

    vim.cmd("GitReview start")
  end, "GitReview: start/stop review")
  map_active_if_enabled("n", normal.stop, "<cmd>GitReview stop<cr>", "GitReview: stop review")
  map_active_if_enabled("n", normal.submit, "<cmd>GitReview submit<cr>", "GitReview: submit review")
  map_active_if_enabled("n", normal.refresh, "<cmd>GitReview refresh<cr>", "GitReview: refresh")
  map_active_if_enabled("n", normal.files, "<cmd>GitReview files<cr>", "GitReview: files")
  map_active_if_enabled("n", normal.panel, "<cmd>GitReview panel<cr>", "GitReview: panel")
  map_active_if_enabled("n", normal.panel_all, "<cmd>GitReview panel-all<cr>", "GitReview: panel all")
  map_active_if_enabled("n", normal.info, "<cmd>GitReview info<cr>", "GitReview: info")
  map_active_if_enabled("n", normal.action, run_context_aware_action, "GitReview: comment or reply")
  map_active_if_enabled("n", normal.react, run_react_action, "GitReview: react to selected thread")
  map_active_if_enabled("n", normal.toggle_resolved, "<cmd>GitReview toggle-resolved<cr>", "GitReview: toggle resolved")
  map_active_if_enabled("n", normal.toggle_deletion_block, function()
    run_session_command("GitReviewToggleDeletionBlock", function()
      return require("git-review.session").toggle_current_deletion_block()
    end)
  end, "GitReview: toggle deletion block")
  map_active_if_enabled("n", normal.toggle_deletions, function()
    run_session_command("GitReviewToggleDeletions", function()
      return require("git-review.session").toggle_deletion_blocks()
    end)
  end, "GitReview: toggle deletion blocks")

  map_active_if_enabled("x", visual.comment, run_visual_comment_action, "GitReview: comment range")
end

register_default_keymaps = function()
  local cfg = require("git-review.config").get()
  local keymaps = type(cfg) == "table" and cfg.keymaps or nil
  if type(keymaps) ~= "table" or keymaps.enabled ~= true then
    return
  end

  unregister_default_keymaps()

  local prefix = type(keymaps.prefix) == "string" and keymaps.prefix or ""
  local normal = type(keymaps.normal) == "table" and keymaps.normal or {}
  local start_suffix = normal.start
  local range_suffix = normal.range

  if not (start_suffix == nil or start_suffix == false) then
    set_tracked_keymap(DEFAULT_KEYMAPS, "n", prefix .. start_suffix, function()
      local session = load_session_or_notify("toggle")
      if session == nil then
        return
      end

      local is_active = session_is_active(session)
      if is_active then
        vim.cmd("GitReview stop")
        return
      end

      vim.cmd("GitReview start")
    end, "GitReview: start/stop review")
  end

  if not (range_suffix == nil or range_suffix == false) then
    set_tracked_keymap(DEFAULT_KEYMAPS, "n", prefix .. range_suffix, function()
      local session = load_session_or_notify("range")
      if session == nil then
        return
      end

      if session_is_active(session) then
        return
      end

      vim.cmd("GitReview range")
    end, "GitReview: start range review")
  end
end

local function run_start_action()
  local success = run_start_like_command("GitReview start", function()
    return require("git-review.session").start()
  end, ". Check your branch upstream or pass opts.diff_command to session.start().")
  if success then
    register_active_keymaps()
    return true
  end

  return false
end

local function run_local_action()
  local success = run_start_like_command("GitReviewLocal", function()
    return require("git-review.session").start_local()
  end)
  if success then
    register_active_keymaps()
    return true
  end

  return false
end

local function run_branch_action(base_ref, head_ref, command_opts)
  local success = run_start_like_command("GitReviewBranch", function()
    return require("git-review.session").start_branch({
      base_ref = base_ref,
      head_ref = head_ref,
      command_opts = command_opts,
    })
  end)
  if success then
    register_active_keymaps()
    return true
  end

  return false
end

load_session_or_notify = function(context)
  local ok, session_or_err = pcall(require, "git-review.session")
  if ok then
    return session_or_err
  end

  vim.notify(
    "GitReview "
      .. context
      .. " failed: could not load git-review.session: "
      .. tostring(session_or_err)
      .. ". Check plugin installation and runtimepath, then restart Neovim.",
    vim.log.levels.ERROR
  )
  return nil
end

local function filter_completion_items(items, arglead)
  local matches = {}
  local prefix = type(arglead) == "string" and string.lower(arglead) or ""
  for _, item in ipairs(items) do
    if prefix == "" or string.find(item, prefix, 1, true) == 1 then
      table.insert(matches, item)
    end
  end

  return matches
end

local function complete_dispatcher(arglead, cmdline, _)
  local session = load_session_or_notify("completion")
  if session == nil then
    return {}
  end

  local is_active = reconcile_active_keymaps(session)
  local raw_cmdline = type(cmdline) == "string" and cmdline or ""
  local args = {}
  for arg in string.gmatch(raw_cmdline, "%S+") do
    table.insert(args, arg)
  end
  local has_subcommand = #args > 2 or (#args == 2 and string.find(raw_cmdline, "%s$") ~= nil)

  if has_subcommand then
    return {}
  end

  if is_active then
    return filter_completion_items(ACTIVE_SUBCOMMANDS, arglead)
  end

  return filter_completion_items(INACTIVE_SUBCOMMANDS, arglead)
end

local function valid_subcommands_for_state(is_active)
  if is_active then
    return ACTIVE_SUBCOMMANDS
  end

  return INACTIVE_SUBCOMMANDS
end

local function format_valid_subcommands(is_active)
  return table.concat(valid_subcommands_for_state(is_active), "|")
end

local function notify_unknown_or_missing_subcommand(subcommand, is_active)
  local valid = format_valid_subcommands(is_active)
  if type(subcommand) ~= "string" or subcommand == "" then
    vim.notify("GitReview: missing subcommand. Valid subcommands: " .. valid, vim.log.levels.ERROR)
    return
  end

  vim.notify("GitReview: unknown subcommand '" .. subcommand .. "'. Valid subcommands: " .. valid, vim.log.levels.ERROR)
end

local function run_comment_action(command_opts)
  local body = prompt_for_body("Comment: ")
  if body == nil then
    vim.notify("GitReviewComment failed: comment body is required", vim.log.levels.ERROR)
    return
  end

  local line1 = type(command_opts) == "table" and command_opts.line1 or nil
  local line2 = type(command_opts) == "table" and command_opts.line2 or nil
  if type(line1) ~= "number" or line1 <= 0 or type(line2) ~= "number" or line2 <= 0 then
    local cursor = vim.api.nvim_win_get_cursor(0)
    local cursor_line = type(cursor) == "table" and cursor[1] or 1
    line1 = cursor_line
    line2 = cursor_line
  end

  run_session_command("GitReviewComment", function()
    return require("git-review.session").create_comment({
      body = body,
      context = {
        start_line = math.min(line1, line2),
        end_line = math.max(line1, line2),
      },
    })
  end)
end

local function run_dispatcher(command_opts)
  local args = {}
  if type(command_opts) == "table" and type(command_opts.fargs) == "table" then
    args = command_opts.fargs
  end

  local subcommand = args[1]

  if subcommand == "start" then
    if #args > 1 then
      vim.notify("GitReview: subcommand 'start' does not accept arguments. Usage: :GitReview start", vim.log.levels.ERROR)
      return
    end

    run_start_action()
    return
  end

  if subcommand == "local" then
    if #args > 1 then
      vim.notify("GitReview: subcommand 'local' does not accept arguments. Usage: :GitReview local", vim.log.levels.ERROR)
      return
    end

    run_local_action()
    return
  end

  local session = load_session_or_notify("dispatcher")
  if session == nil then
    return
  end

  local is_active = reconcile_active_keymaps(session)

  if not is_active then
    if subcommand == "branch" then
      if #args == 2 or #args == 3 then
        run_branch_action(args[2], args[3], command_opts)
        return
      end

      vim.notify("GitReview: subcommand 'branch' expects a base ref and optional head ref. Usage: :GitReview branch <base> [<head>]", vim.log.levels.ERROR)
      return
    end

    if subcommand == "range" then
      if #args == 1 then
        local ok_picker, picker_result = pcall(session.start_range_picker, {
          command_opts = command_opts,
          on_complete = function(async_result)
            local success = evaluate_start_like_result("GitReviewRange", async_result)
            if success then
              register_active_keymaps()
            end
          end,
        })
        if not ok_picker then
          vim.notify("GitReviewRange failed: " .. tostring(picker_result), vim.log.levels.ERROR)
          return
        end

        local success = evaluate_start_like_result("GitReviewRange", picker_result)
        if success and not (type(picker_result) == "table" and picker_result.state == "pending") then
          register_active_keymaps()
        end
        return
      end

      if #args == 3 then
        local success = run_start_like_command("GitReviewRange", function()
          return session.start_range({
            start_ref = args[2],
            end_ref = args[3],
            command_opts = command_opts,
          })
        end)
        if success then
          register_active_keymaps()
        end
        return
      end

      vim.notify("GitReview: subcommand 'range' expects zero refs or exactly two refs. Usage: :GitReview range [<start> <end>]", vim.log.levels.ERROR)
      return
    end

    if ACTIVE_SUBCOMMAND_LOOKUP[subcommand] == true then
      vim.notify("Review not active. Run :GitReview start", vim.log.levels.ERROR)
      return
    end

    notify_unknown_or_missing_subcommand(subcommand, false)
    return
  end

  if #args > 1 and type(subcommand) == "string" and subcommand ~= "" and ACTIVE_SUBCOMMAND_LOOKUP[subcommand] == true then
    vim.notify(
      "GitReview: subcommand '" .. subcommand .. "' does not accept arguments. Usage: :GitReview " .. subcommand,
      vim.log.levels.ERROR
    )
    return
  end

  if subcommand == "stop" then
    local success = run_session_command("GitReviewStop", function()
      return require("git-review.session").stop()
    end)
    if success then
      unregister_active_keymaps()
      register_default_keymaps()
    end
    return
  end

  if subcommand == "submit" then
    run_submit_review_action()
    return
  end

  if subcommand == "comment" then
    run_comment_action(command_opts)
    return
  end

  if subcommand == "reply" then
    run_session_command("GitReviewReply", function()
      return require("git-review.session").reply_to_selected_thread()
    end)
    return
  end

  if subcommand == "react" then
    run_react_action()
    return
  end

  if subcommand == "refresh" then
    run_session_command("GitReviewRefresh", function()
      return require("git-review.session").refresh()
    end)
    return
  end

  if subcommand == "files" then
    run_session_command("GitReviewFiles", function()
      return require("git-review.session").populate_files_quickfix()
    end)
    return
  end

  if subcommand == "panel" then
    run_session_command("GitReviewPanel", function()
      local session_api = require("git-review.session")
      if type(session_api.open_panel_toggle) == "function" then
        return session_api.open_panel_toggle({ scope = "current" })
      end

      return session_api.open_panel()
    end)
    return
  end

  if subcommand == "panel-all" then
    run_session_command("GitReviewPanelAll", function()
      local session_api = require("git-review.session")
      if type(session_api.open_panel_toggle) == "function" then
        return session_api.open_panel_toggle({ scope = "all" })
      end

      return session_api.open_panel()
    end)
    return
  end

  if subcommand == "info" then
    run_session_command("GitReviewInfo", function()
      return require("git-review.session").open_pr_info()
    end)
    return
  end

  if subcommand == "toggle-resolved" then
    run_session_command("GitReviewToggleResolved", function()
      return require("git-review.session").toggle_resolved_thread_visibility()
    end)
    return
  end

  if subcommand == "toggle-deletion-block" then
    run_session_command("GitReviewToggleDeletionBlock", function()
      return require("git-review.session").toggle_current_deletion_block()
    end)
    return
  end

  if subcommand == "toggle-deletions" then
    run_session_command("GitReviewToggleDeletions", function()
      return require("git-review.session").toggle_deletion_blocks()
    end)
    return
  end

  if subcommand == "expand-deletion-blocks" then
    run_session_command("GitReviewExpandDeletionBlocks", function()
      return require("git-review.session").expand_deletion_blocks()
    end)
    return
  end

  if subcommand == "collapse-deletion-blocks" then
    run_session_command("GitReviewCollapseDeletionBlocks", function()
      return require("git-review.session").collapse_deletion_blocks()
    end)
    return
  end

  notify_unknown_or_missing_subcommand(subcommand, true)
end

function M.setup(opts)
  require("git-review.config").setup(opts)

  if vim.fn.exists(":GitReview") == 0 then
    vim.api.nvim_create_user_command("GitReview", run_dispatcher, {
      desc = "Git review command dispatcher",
      nargs = "*",
      range = true,
      complete = complete_dispatcher,
    })
  end

  register_default_keymaps()
end

return M
