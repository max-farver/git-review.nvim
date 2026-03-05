local T = require("mini.test")

local child = T.new_child_neovim()

local set = T.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "tests/minimal_init.lua" })
    end,
    post_once = function()
      child.stop()
    end,
  },
})

set["setup creates :GitReview command"] = function()
  child.lua([[pcall(vim.api.nvim_del_user_command, "GitReview")]])
  child.lua([[require("git-review").setup()]])

  local exists = child.lua_get([[vim.fn.exists(":GitReview")]])
  assert(exists == 2, "Expected :GitReview to exist")
end

set["setup does not create legacy commands"] = function()
  child.lua([[require("git-review").setup()]])

  local legacy_commands = {
    "GitReviewStart",
    "GitReviewStop",
    "GitReviewRefresh",
    "GitReviewFiles",
    "GitReviewComment",
    "GitReviewReply",
    "GitReviewDiff",
    "GitReviewSubmit",
    "GitReviewPanel",
    "GitReviewToggleResolved",
    "GitReviewToggleDeletionBlock",
    "GitReviewExpandDeletionBlocks",
    "GitReviewCollapseDeletionBlocks",
    "GitReviewInfo",
  }

  for _, command in ipairs(legacy_commands) do
    local exists = child.lua_get(string.format([[vim.fn.exists(":%s")]], command))
    assert(exists == 0, string.format("Expected :%s to be absent", command))
  end
end

set["GitReview dispatcher routes active subcommands"] = function()
  child.lua([=[
    package.loaded["git-review.session"] = {
      is_active = function()
        return vim.g.git_review_setup_dispatcher_active == true
      end,
      start = function()
        vim.g.git_review_setup_dispatcher_start_calls = (vim.g.git_review_setup_dispatcher_start_calls or 0) + 1
        vim.g.git_review_setup_dispatcher_active = true
        return { state = "ok" }
      end,
      stop = function()
        vim.g.git_review_setup_dispatcher_stop_calls = (vim.g.git_review_setup_dispatcher_stop_calls or 0) + 1
        vim.g.git_review_setup_dispatcher_active = false
        return { state = "ok" }
      end,
      refresh = function()
        vim.g.git_review_setup_dispatcher_refresh_calls = (vim.g.git_review_setup_dispatcher_refresh_calls or 0) + 1
        return { state = "ok" }
      end,
      populate_files_quickfix = function()
        vim.g.git_review_setup_dispatcher_files_calls = (vim.g.git_review_setup_dispatcher_files_calls or 0) + 1
        return { state = "ok" }
      end,
      open_panel = function()
        vim.g.git_review_setup_dispatcher_panel_calls = (vim.g.git_review_setup_dispatcher_panel_calls or 0) + 1
        return { state = "ok" }
      end,
      open_panel_toggle = function(opts)
        local scope = type(opts) == "table" and opts.scope or ""
        if scope == "all" then
          vim.g.git_review_setup_dispatcher_panel_all_calls = (vim.g.git_review_setup_dispatcher_panel_all_calls or 0) + 1
        else
          vim.g.git_review_setup_dispatcher_panel_calls = (vim.g.git_review_setup_dispatcher_panel_calls or 0) + 1
        end
        return { state = "ok" }
      end,
      open_pr_info = function()
        vim.g.git_review_setup_dispatcher_info_calls = (vim.g.git_review_setup_dispatcher_info_calls or 0) + 1
        return { state = "ok" }
      end,
      create_comment = function(opts)
        vim.g.git_review_setup_dispatcher_comment_calls = (vim.g.git_review_setup_dispatcher_comment_calls or 0) + 1
        vim.g.git_review_setup_dispatcher_comment_opts = opts
        return { state = "ok" }
      end,
      reply_to_selected_thread = function()
        vim.g.git_review_setup_dispatcher_reply_calls = (vim.g.git_review_setup_dispatcher_reply_calls or 0) + 1
        return { state = "ok" }
      end,
      toggle_resolved_thread_visibility = function()
        vim.g.git_review_setup_dispatcher_toggle_resolved_calls =
          (vim.g.git_review_setup_dispatcher_toggle_resolved_calls or 0) + 1
        return { state = "ok" }
      end,
      toggle_current_deletion_block = function()
        vim.g.git_review_setup_dispatcher_toggle_block_calls =
          (vim.g.git_review_setup_dispatcher_toggle_block_calls or 0) + 1
        return { state = "ok" }
      end,
      toggle_deletion_blocks = function()
        vim.g.git_review_setup_dispatcher_toggle_deletions_calls =
          (vim.g.git_review_setup_dispatcher_toggle_deletions_calls or 0) + 1
        return { state = "ok" }
      end,
      expand_deletion_blocks = function()
        vim.g.git_review_setup_dispatcher_expand_deletions_calls =
          (vim.g.git_review_setup_dispatcher_expand_deletions_calls or 0) + 1
        return { state = "ok" }
      end,
      collapse_deletion_blocks = function()
        vim.g.git_review_setup_dispatcher_collapse_deletions_calls =
          (vim.g.git_review_setup_dispatcher_collapse_deletions_calls or 0) + 1
        return { state = "ok" }
      end,
    }

    package.loaded["git-review.ui.panel"] = {
      get_selected_thread_id = function(_)
        return nil
      end,
    }

    local original_input = vim.fn.input
    vim.fn.input = function(_)
      return "dispatcher comment body"
    end

    require("git-review").setup()
    vim.cmd("GitReview start")
    vim.cmd("GitReview refresh")
    vim.cmd("GitReview files")
    vim.cmd("GitReview panel")
    vim.cmd("GitReview panel-all")
    vim.cmd("GitReview info")
    vim.cmd("GitReview comment")
    vim.cmd("GitReview reply")
    vim.cmd("GitReview toggle-resolved")
    vim.cmd("GitReview toggle-deletion-block")
    vim.cmd("GitReview toggle-deletions")
    vim.cmd("GitReview expand-deletion-blocks")
    vim.cmd("GitReview collapse-deletion-blocks")
    vim.cmd("GitReview stop")

    vim.fn.input = original_input
  ]=])

  local start_calls = child.lua_get([[vim.g.git_review_setup_dispatcher_start_calls or 0]])
  local stop_calls = child.lua_get([[vim.g.git_review_setup_dispatcher_stop_calls or 0]])
  local refresh_calls = child.lua_get([[vim.g.git_review_setup_dispatcher_refresh_calls or 0]])
  local files_calls = child.lua_get([[vim.g.git_review_setup_dispatcher_files_calls or 0]])
  local panel_calls = child.lua_get([[vim.g.git_review_setup_dispatcher_panel_calls or 0]])
  local panel_all_calls = child.lua_get([[vim.g.git_review_setup_dispatcher_panel_all_calls or 0]])
  local info_calls = child.lua_get([[vim.g.git_review_setup_dispatcher_info_calls or 0]])
  local comment_calls = child.lua_get([[vim.g.git_review_setup_dispatcher_comment_calls or 0]])
  local comment_opts = child.lua_get([[vim.g.git_review_setup_dispatcher_comment_opts]])
  local reply_calls = child.lua_get([[vim.g.git_review_setup_dispatcher_reply_calls or 0]])
  local toggle_resolved_calls = child.lua_get([[vim.g.git_review_setup_dispatcher_toggle_resolved_calls or 0]])
  local toggle_block_calls = child.lua_get([[vim.g.git_review_setup_dispatcher_toggle_block_calls or 0]])
  local toggle_deletions_calls = child.lua_get([[vim.g.git_review_setup_dispatcher_toggle_deletions_calls or 0]])
  local expand_deletions_calls = child.lua_get([[vim.g.git_review_setup_dispatcher_expand_deletions_calls or 0]])
  local collapse_deletions_calls = child.lua_get([[vim.g.git_review_setup_dispatcher_collapse_deletions_calls or 0]])

  assert(start_calls == 1, "Expected :GitReview start to call session.start")
  assert(stop_calls == 1, "Expected :GitReview stop to call session.stop")
  assert(refresh_calls == 1, "Expected :GitReview refresh to call session.refresh")
  assert(files_calls == 1, "Expected :GitReview files to call session.populate_files_quickfix")
  assert(panel_calls == 1, "Expected :GitReview panel to call session.open_panel_toggle(current)")
  assert(panel_all_calls == 1, "Expected :GitReview panel-all to call session.open_panel_toggle(all)")
  assert(info_calls == 1, "Expected :GitReview info to call session.open_pr_info")
  assert(comment_calls == 1, "Expected :GitReview comment to call session.create_comment")
  assert(type(comment_opts) == "table" and comment_opts.body == "dispatcher comment body", "Expected :GitReview comment to pass prompt body")
  assert(reply_calls == 1, "Expected :GitReview reply to call session.reply_to_selected_thread")
  assert(
    toggle_resolved_calls == 1,
    "Expected :GitReview toggle-resolved to call session.toggle_resolved_thread_visibility"
  )
  assert(toggle_block_calls == 1, "Expected :GitReview toggle-deletion-block to call session.toggle_current_deletion_block")
  assert(toggle_deletions_calls == 1, "Expected :GitReview toggle-deletions to call session.toggle_deletion_blocks")
  assert(expand_deletions_calls == 1, "Expected :GitReview expand-deletion-blocks to call session.expand_deletion_blocks")
  assert(collapse_deletions_calls == 1, "Expected :GitReview collapse-deletion-blocks to call session.collapse_deletion_blocks")
end

set["GitReview dispatcher routes submit through prompt helper"] = function()
  child.lua([=[
    package.loaded["git-review.session"] = {
      is_active = function()
        return true
      end,
      start = function()
        return { state = "ok" }
      end,
      submit_review = function(opts)
        vim.g.git_review_setup_dispatcher_submit_calls = (vim.g.git_review_setup_dispatcher_submit_calls or 0) + 1
        vim.g.git_review_setup_dispatcher_submit_opts = opts
        return { state = "ok" }
      end,
    }

    vim.ui = {
      select = function(_, _, on_choice)
        on_choice("APPROVE")
      end,
    }

    local original_input = vim.fn.input
    vim.fn.input = function(_)
      return "ship it"
    end

    require("git-review").setup()
    vim.cmd("GitReview submit")
    vim.fn.input = original_input
  ]=])

  local submit_calls = child.lua_get([[vim.g.git_review_setup_dispatcher_submit_calls or 0]])
  local submit_opts = child.lua_get([[vim.g.git_review_setup_dispatcher_submit_opts]])

  assert(submit_calls == 1, "Expected :GitReview submit to call session.submit_review")
  assert(type(submit_opts) == "table" and submit_opts.event == "APPROVE", "Expected submit event from prompt helper")
  assert(type(submit_opts) == "table" and submit_opts.body == "ship it", "Expected submit body from prompt helper")
end

set["GitReview dispatcher handles session require failures without crashing"] = function()
  local result = child.lua_get([=[(function()
    package.loaded["git-review.session"] = nil
    package.preload["git-review.session"] = function()
      error("simulated session load failure")
    end

    local notifications = {}
    local original_notify = vim.notify
    vim.notify = function(message, level)
      table.insert(notifications, {
        message = message,
        level = level,
      })
    end

    require("git-review").setup()

    local ok_refresh, err_refresh = pcall(vim.cmd, "GitReview refresh")
    local ok_completion, err_completion = pcall(vim.fn.getcompletion, "GitReview ", "cmdline")

    vim.notify = original_notify
    package.preload["git-review.session"] = nil

    return {
      ok_refresh = ok_refresh,
      err_refresh = err_refresh,
      ok_completion = ok_completion,
      err_completion = err_completion,
      notifications = notifications,
    }
  end)()]=])

  assert(result.ok_refresh == true, "Expected dispatcher to avoid crashing when session require fails")
  assert(result.ok_completion == true, "Expected completion to avoid crashing when session require fails")
  assert(type(result.notifications[1]) == "table", "Expected actionable dispatcher/completion error notification")
  assert(
    string.find(result.notifications[1].message or "", "could not load git-review.session", 1, true),
    "Expected actionable session load failure message"
  )
end

set["GitReview dispatcher completion is session-state aware"] = function()
  local completion_state = child.lua_get([=[(function()
    package.loaded["git-review.session"] = {
      is_active = function()
        return vim.g.git_review_setup_dispatcher_active == true
      end,
      start = function()
        return { state = "ok" }
      end,
      stop = function()
        return { state = "ok" }
      end,
    }

    require("git-review").setup()

    vim.g.git_review_setup_dispatcher_active = false
    local inactive = vim.fn.getcompletion("GitReview ", "cmdline")

    vim.g.git_review_setup_dispatcher_active = true
    local active = vim.fn.getcompletion("GitReview ", "cmdline")

    local function has(items, expected)
      for _, item in ipairs(items or {}) do
        if item == expected then
          return true
        end
      end

      return false
    end

    return {
      inactive = inactive,
      active = active,
      inactive_has_start = has(inactive, "start"),
      inactive_has_range = has(inactive, "range"),
      active_has_stop = has(active, "stop"),
      active_has_comment = has(active, "comment"),
      active_has_reply = has(active, "reply"),
      active_has_toggle_deletions = has(active, "toggle-deletions"),
    }
  end)()]=])

  assert(type(completion_state.inactive) == "table" and #completion_state.inactive == 2, "Expected inactive completion to suggest start and range")
  assert(completion_state.inactive_has_start == true, "Expected inactive completion to include start")
  assert(completion_state.inactive_has_range == true, "Expected inactive completion to include range")
  assert(completion_state.active_has_stop == true, "Expected active completion to include stop")
  assert(completion_state.active_has_comment == true, "Expected active completion to include comment")
  assert(completion_state.active_has_reply == true, "Expected active completion to include reply")
  assert(completion_state.active_has_toggle_deletions == true, "Expected active completion to include toggle-deletions")
end

set["GitReview dispatcher completion matches partial first argument"] = function()
  local completion_state = child.lua_get([=[(function()
    package.loaded["git-review.session"] = {
      is_active = function()
        return vim.g.git_review_setup_dispatcher_active == true
      end,
      start = function()
        return { state = "ok" }
      end,
      stop = function()
        return { state = "ok" }
      end,
    }

    require("git-review").setup()

    vim.g.git_review_setup_dispatcher_active = false
    local inactive = vim.fn.getcompletion("GitReview st", "cmdline")

    vim.g.git_review_setup_dispatcher_active = true
    local active_stop = vim.fn.getcompletion("GitReview st", "cmdline")
    local active_toggle = vim.fn.getcompletion("GitReview toggle-d", "cmdline")

    local function has(items, expected)
      for _, item in ipairs(items or {}) do
        if item == expected then
          return true
        end
      end

      return false
    end

    return {
      inactive_has_start = has(inactive, "start"),
      active_has_stop = has(active_stop, "stop"),
      active_has_toggle_deletion_block = has(active_toggle, "toggle-deletion-block"),
      active_has_toggle_deletions = has(active_toggle, "toggle-deletions"),
    }
  end)()]=])

  assert(completion_state.inactive_has_start == true, "Expected partial completion to include start when inactive")
  assert(completion_state.active_has_stop == true, "Expected partial completion to include stop when active")
  assert(
    completion_state.active_has_toggle_deletion_block == true,
    "Expected partial completion to include toggle-deletion-block when active"
  )
  assert(completion_state.active_has_toggle_deletions == true, "Expected partial completion to include toggle-deletions when active")
end

set["GitReview dispatcher gates inactive commands and reports actionable errors"] = function()
  local result = child.lua_get([=[(function()
    package.loaded["git-review.session"] = {
      is_active = function()
        return vim.g.git_review_setup_dispatcher_active == true
      end,
      start = function()
        vim.g.git_review_setup_dispatcher_active = true
        return { state = "ok" }
      end,
      refresh = function()
        vim.g.git_review_setup_dispatcher_refresh_calls = (vim.g.git_review_setup_dispatcher_refresh_calls or 0) + 1
        return { state = "ok" }
      end,
    }

    local notifications = {}
    local original_notify = vim.notify
    vim.notify = function(message, level)
      table.insert(notifications, {
        message = message,
        level = level,
      })
    end

    require("git-review").setup()

    vim.g.git_review_setup_dispatcher_active = false
    vim.cmd("GitReview refresh")
    vim.cmd("GitReview")
    vim.cmd("GitReview nope")

    vim.cmd("GitReview start")
    vim.cmd("GitReview nope")

    vim.notify = original_notify

    return {
      refresh_calls = vim.g.git_review_setup_dispatcher_refresh_calls or 0,
      notifications = notifications,
    }
  end)()]=])

  local notifications = result.notifications or {}
  assert(result.refresh_calls == 0, "Expected inactive gating to block :GitReview refresh")
  assert(type(notifications[1]) == "table", "Expected inactive refresh notification")
  assert(notifications[1].message == "Review not active. Run :GitReview start", "Expected actionable inactive review message")
  assert(type(notifications[2]) == "table", "Expected missing subcommand notification")
  assert(
    string.find(notifications[2].message or "", "Valid subcommands: start|range", 1, true),
    "Expected missing subcommand message to list inactive valid subcommands"
  )
  assert(type(notifications[3]) == "table", "Expected unknown inactive subcommand notification")
  assert(
    string.find(notifications[3].message or "", "Valid subcommands: start|range", 1, true),
    "Expected unknown inactive subcommand message to list inactive valid subcommands"
  )
  assert(type(notifications[4]) == "table", "Expected unknown active subcommand notification")
  assert(
    string.find(notifications[4].message or "", "Valid subcommands: stop", 1, true),
    "Expected unknown active subcommand message to list active valid subcommands"
  )
end

set["GitReview dispatcher routes range subcommand variants while inactive"] = function()
  local result = child.lua_get([=[(function()
    package.loaded["git-review.session"] = {
      is_active = function()
        return vim.g.git_review_setup_dispatcher_active == true
      end,
      start = function()
        vim.g.git_review_setup_dispatcher_active = true
        return { state = "ok" }
      end,
      start_range = function(opts)
        vim.g.git_review_setup_dispatcher_range_calls = (vim.g.git_review_setup_dispatcher_range_calls or 0) + 1
        vim.g.git_review_setup_dispatcher_range_opts = opts
        return { hunks = {} }
      end,
      start_range_picker = function(opts)
        vim.g.git_review_setup_dispatcher_range_picker_calls = (vim.g.git_review_setup_dispatcher_range_picker_calls or 0) + 1
        vim.g.git_review_setup_dispatcher_range_picker_has_on_complete =
          type(opts) == "table" and type(opts.on_complete) == "function"
        vim.g.git_review_setup_dispatcher_range_picker_opts = {
          command_opts = type(opts) == "table" and opts.command_opts or nil,
        }
        return { hunks = {} }
      end,
    }

    local notifications = {}
    local original_notify = vim.notify
    vim.notify = function(message, level)
      table.insert(notifications, {
        message = message,
        level = level,
      })
    end

    require("git-review").setup()

    vim.g.git_review_setup_dispatcher_active = false
    vim.cmd("GitReview range")
    vim.cmd("GitReview range base/head feature/head")

    vim.notify = original_notify

    local active_map = vim.fn.maparg("\\grs", "n", false, true)

    return {
      range_calls = vim.g.git_review_setup_dispatcher_range_calls or 0,
      range_opts = vim.g.git_review_setup_dispatcher_range_opts,
      range_picker_calls = vim.g.git_review_setup_dispatcher_range_picker_calls or 0,
      range_picker_opts = vim.g.git_review_setup_dispatcher_range_picker_opts,
      range_picker_has_on_complete = vim.g.git_review_setup_dispatcher_range_picker_has_on_complete == true,
      has_active_map = type(active_map) == "table" and active_map.lhs == "\\grs",
      notifications = notifications,
    }
  end)()]=])

  assert(result.range_picker_calls == 1, "Expected :GitReview range to call session.start_range_picker")
  assert(type(result.range_picker_opts) == "table", "Expected picker path to receive opts table")
  assert(result.range_picker_has_on_complete == true, "Expected picker path to receive async completion callback")
  assert(result.range_calls == 1, "Expected :GitReview range <start> <end> to call session.start_range")
  assert(type(result.range_opts) == "table", "Expected range path to receive opts table")
  assert(result.range_opts.start_ref == "base/head", "Expected start_ref to be forwarded")
  assert(result.range_opts.end_ref == "feature/head", "Expected end_ref to be forwarded")
  assert(result.has_active_map == true, "Expected successful range path to register active keymaps")
  assert(type(result.notifications) == "table" and #result.notifications == 0, "Expected no dispatcher notifications for valid range commands")
end

set["GitReview dispatcher handles range picker cancel without activating session"] = function()
  local result = child.lua_get([=[(function()
    package.loaded["git-review.session"] = {
      is_active = function()
        return false
      end,
      start = function()
        return { state = "ok" }
      end,
      start_range_picker = function(_)
        vim.g.git_review_setup_dispatcher_cancel_picker_calls =
          (vim.g.git_review_setup_dispatcher_cancel_picker_calls or 0) + 1
        return { state = "cancelled" }
      end,
    }

    local notifications = {}
    local original_notify = vim.notify
    vim.notify = function(message, level)
      table.insert(notifications, {
        message = message,
        level = level,
      })
    end

    require("git-review").setup()
    vim.cmd("GitReview range")

    vim.notify = original_notify

    local active_map = vim.fn.maparg("\\grs", "n", false, true)

    return {
      picker_calls = vim.g.git_review_setup_dispatcher_cancel_picker_calls or 0,
      has_active_map = type(active_map) == "table" and active_map.lhs == "\\grs",
      notifications = notifications,
    }
  end)()]=])

  assert(result.picker_calls == 1, "Expected :GitReview range to call session.start_range_picker")
  assert(result.has_active_map == false, "Expected cancelled picker flow to avoid active keymap registration")
  assert(type(result.notifications) == "table" and #result.notifications == 0, "Expected cancelled picker flow to be silent")
end

set["GitReview dispatcher activates session after async range picker completion"] = function()
  local result = child.lua_get([=[(function()
    package.loaded["git-review.session"] = {
      is_active = function()
        return false
      end,
      start = function()
        return { state = "ok" }
      end,
      start_range_picker = function(opts)
        vim.g.git_review_setup_dispatcher_async_picker_calls =
          (vim.g.git_review_setup_dispatcher_async_picker_calls or 0) + 1
        if type(opts) == "table" and type(opts.on_complete) == "function" then
          vim.schedule(function()
            opts.on_complete({
              hunks = {},
            })
          end)
        end

        return { state = "pending" }
      end,
    }

    local notifications = {}
    local original_notify = vim.notify
    vim.notify = function(message, level)
      table.insert(notifications, {
        message = message,
        level = level,
      })
    end

    local scheduled = {}
    local original_schedule = vim.schedule
    vim.schedule = function(fn)
      table.insert(scheduled, fn)
    end

    require("git-review").setup()
    vim.cmd("GitReview range")

    local active_map_before = vim.fn.maparg("\\grs", "n", false, true)
    for _, callback in ipairs(scheduled) do
      callback()
    end
    local active_map_after = vim.fn.maparg("\\grs", "n", false, true)

    vim.notify = original_notify
    vim.schedule = original_schedule

    return {
      picker_calls = vim.g.git_review_setup_dispatcher_async_picker_calls or 0,
      has_active_map_before = type(active_map_before) == "table" and active_map_before.lhs == "\\grs",
      has_active_map_after = type(active_map_after) == "table" and active_map_after.lhs == "\\grs",
      notifications = notifications,
    }
  end)()]=])

  assert(result.picker_calls == 1, "Expected :GitReview range to call async start_range_picker once")
  assert(result.has_active_map_before == false, "Expected pending picker flow to defer keymap registration")
  assert(result.has_active_map_after == true, "Expected async picker completion to register active keymaps")
  assert(type(result.notifications) == "table" and #result.notifications == 0, "Expected async picker flow to be silent")
end

set["GitReview dispatcher async range lifecycle wires picker activation and stop cleanup"] = function()
  local result = child.lua_get([=[(function()
    vim.g.git_review_setup_dispatcher_lifecycle_active = false

    package.loaded["git-review.session"] = {
      is_active = function()
        return vim.g.git_review_setup_dispatcher_lifecycle_active == true
      end,
      start = function()
        return { state = "ok" }
      end,
      start_range_picker = function(opts)
        vim.g.git_review_setup_dispatcher_lifecycle_picker_calls =
          (vim.g.git_review_setup_dispatcher_lifecycle_picker_calls or 0) + 1
        if type(opts) == "table" and type(opts.on_complete) == "function" then
          vim.schedule(function()
            vim.g.git_review_setup_dispatcher_lifecycle_active = true
            opts.on_complete({
              hunks = {},
            })
          end)
        end

        return { state = "pending" }
      end,
      stop = function()
        vim.g.git_review_setup_dispatcher_lifecycle_stop_calls =
          (vim.g.git_review_setup_dispatcher_lifecycle_stop_calls or 0) + 1
        vim.g.git_review_setup_dispatcher_lifecycle_cleanup_calls =
          (vim.g.git_review_setup_dispatcher_lifecycle_cleanup_calls or 0) + 1
        vim.g.git_review_setup_dispatcher_lifecycle_active = false
        return { state = "ok" }
      end,
    }

    local notifications = {}
    local original_notify = vim.notify
    vim.notify = function(message, level)
      table.insert(notifications, {
        message = message,
        level = level,
      })
    end

    local scheduled = {}
    local original_schedule = vim.schedule
    vim.schedule = function(fn)
      table.insert(scheduled, fn)
    end

    require("git-review").setup()
    vim.cmd("GitReview range")

    local active_map_before = vim.fn.maparg("\\grs", "n", false, true)
    for _, callback in ipairs(scheduled) do
      callback()
    end
    local active_map_after_picker = vim.fn.maparg("\\grs", "n", false, true)

    vim.cmd("GitReview stop")
    local active_map_after_stop = vim.fn.maparg("\\grs", "n", false, true)

    vim.notify = original_notify
    vim.schedule = original_schedule

    return {
      picker_calls = vim.g.git_review_setup_dispatcher_lifecycle_picker_calls or 0,
      stop_calls = vim.g.git_review_setup_dispatcher_lifecycle_stop_calls or 0,
      cleanup_calls = vim.g.git_review_setup_dispatcher_lifecycle_cleanup_calls or 0,
      has_active_map_before = type(active_map_before) == "table" and active_map_before.lhs == "\\grs",
      has_active_map_after_picker = type(active_map_after_picker) == "table" and active_map_after_picker.lhs == "\\grs",
      has_active_map_after_stop = type(active_map_after_stop) == "table" and active_map_after_stop.lhs == "\\grs",
      notifications = notifications,
    }
  end)()]=])

  assert(result.picker_calls == 1, "Expected :GitReview range picker flow to run once")
  assert(result.has_active_map_before == false, "Expected pending picker flow to defer active keymaps")
  assert(result.has_active_map_after_picker == true, "Expected async picker completion to activate keymaps")
  assert(result.stop_calls == 1, "Expected :GitReview stop to be routed once after activation")
  assert(result.cleanup_calls == 1, "Expected stop cleanup hook to run once")
  assert(result.has_active_map_after_stop == false, "Expected stop to unregister active keymaps")
  assert(type(result.notifications) == "table" and #result.notifications == 0, "Expected lifecycle flow to remain silent")
end

set["GitReview dispatcher treats range as inactive-only"] = function()
  local result = child.lua_get([=[(function()
    package.loaded["git-review.session"] = {
      is_active = function()
        return true
      end,
      start = function()
        return { state = "ok" }
      end,
      start_range = function(_)
        vim.g.git_review_setup_dispatcher_range_calls = (vim.g.git_review_setup_dispatcher_range_calls or 0) + 1
        return { hunks = {} }
      end,
      start_range_picker = function(_)
        vim.g.git_review_setup_dispatcher_range_picker_calls = (vim.g.git_review_setup_dispatcher_range_picker_calls or 0) + 1
        return { hunks = {} }
      end,
    }

    local notifications = {}
    local original_notify = vim.notify
    vim.notify = function(message, level)
      table.insert(notifications, {
        message = message,
        level = level,
      })
    end

    require("git-review").setup()
    vim.cmd("GitReview range")
    vim.cmd("GitReview range base/head feature/head")

    vim.notify = original_notify

    return {
      range_calls = vim.g.git_review_setup_dispatcher_range_calls or 0,
      range_picker_calls = vim.g.git_review_setup_dispatcher_range_picker_calls or 0,
      notifications = notifications,
    }
  end)()]=])

  local notifications = result.notifications or {}
  assert(result.range_calls == 0, "Expected active dispatcher state to reject :GitReview range <start> <end>")
  assert(result.range_picker_calls == 0, "Expected active dispatcher state to reject :GitReview range")
  assert(type(notifications[1]) == "table", "Expected active range without refs to report unknown subcommand")
  assert(
    string.find(notifications[1].message or "", "unknown subcommand 'range'", 1, true),
    "Expected active range without refs to be unknown"
  )
  assert(
    string.find(notifications[1].message or "", "Valid subcommands: stop", 1, true),
    "Expected active unknown message to list active subcommands"
  )
  assert(type(notifications[2]) == "table", "Expected active range with refs to report unknown subcommand")
  assert(
    string.find(notifications[2].message or "", "unknown subcommand 'range'", 1, true),
    "Expected active range with refs to be unknown"
  )
end

set["GitReview dispatcher accepts real start_range success contract"] = function()
  local result = child.lua_get([=[(function()
    package.loaded["git-review.session"] = nil
    local session = require("git-review.session")

    local original_start = session.start
    local original_is_active = session.is_active
    local original_system = package.loaded["git-review.system"]

    package.loaded["git-review.system"] = {
      run = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--show-toplevel"
        then
          return {
            code = 0,
            stdout = vim.fn.getcwd() .. "\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--verify"
          and (command[4] == "base/head^{commit}" or command[4] == "feature/head^{commit}")
        then
          return {
            code = 0,
            stdout = "validated\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "worktree"
          and command[3] == "add"
          and command[4] == "--detach"
          and type(command[5]) == "string"
          and command[6] == "feature/head"
        then
          return {
            code = 0,
            stdout = "",
            stderr = "",
          }
        end

        return {
          code = 1,
          stdout = "",
          stderr = "unexpected command",
        }
      end,
    }

    session.start = function(opts)
      vim.g.git_review_setup_dispatcher_real_range_calls =
        (vim.g.git_review_setup_dispatcher_real_range_calls or 0) + 1
      vim.g.git_review_setup_dispatcher_real_range_opts = opts
      vim.g.git_review_setup_dispatcher_active = true
      return { hunks = {} }
    end

    session.is_active = function()
      return vim.g.git_review_setup_dispatcher_active == true
    end

    local notifications = {}
    local original_notify = vim.notify
    vim.notify = function(message, level)
      table.insert(notifications, {
        message = message,
        level = level,
      })
    end

    require("git-review").setup()

    vim.g.git_review_setup_dispatcher_active = false
    vim.cmd("GitReview range base/head feature/head")

    vim.notify = original_notify
    session.start = original_start
    session.is_active = original_is_active
    package.loaded["git-review.system"] = original_system

    local active_map = vim.fn.maparg("\\grs", "n", false, true)

    return {
      range_calls = vim.g.git_review_setup_dispatcher_real_range_calls or 0,
      range_opts = vim.g.git_review_setup_dispatcher_real_range_opts,
      has_active_map = type(active_map) == "table" and active_map.lhs == "\\grs",
      notifications = notifications,
    }
  end)()]=])

  assert(result.range_calls == 1, "Expected real session.start_range path to call session.start once")
  assert(type(result.range_opts) == "table", "Expected real session.start to receive options")
  assert(type(result.range_opts.diff_command) == "table", "Expected real session.start_range to build diff_command")
  assert(result.range_opts.diff_command[1] == "git", "Expected start_range diff command to remain git-based")
  assert(result.range_opts.diff_command[2] == "-C", "Expected start_range diff command to execute in detached worktree")
  assert(type(result.range_opts.diff_command[3]) == "string" and result.range_opts.diff_command[3] ~= "", "Expected worktree path in diff command")
  assert(result.range_opts.diff_command[4] == "diff", "Expected diff subcommand in range diff command")
  assert(result.range_opts.diff_command[6] == "base/head...feature/head", "Expected start_range diff_command refs")
  assert(result.range_opts.start_ref == nil, "Expected start_range to strip start_ref before start")
  assert(result.range_opts.end_ref == nil, "Expected start_range to strip end_ref before start")
  assert(result.has_active_map == true, "Expected successful real range path to register active keymaps")
  assert(type(result.notifications) == "table" and #result.notifications == 0, "Expected no unknown-error notifications for real range success")
end

set["GitReview dispatcher rejects extra subcommand arguments"] = function()
  local result = child.lua_get([=[(function()
    package.loaded["git-review.session"] = {
      is_active = function()
        return vim.g.git_review_setup_dispatcher_active == true
      end,
      start = function()
        vim.g.git_review_setup_dispatcher_active = true
        vim.g.git_review_setup_dispatcher_start_calls = (vim.g.git_review_setup_dispatcher_start_calls or 0) + 1
        return { state = "ok" }
      end,
      refresh = function()
        vim.g.git_review_setup_dispatcher_refresh_calls = (vim.g.git_review_setup_dispatcher_refresh_calls or 0) + 1
        return { state = "ok" }
      end,
    }

    local notifications = {}
    local original_notify = vim.notify
    vim.notify = function(message, level)
      table.insert(notifications, {
        message = message,
        level = level,
      })
    end

    require("git-review").setup()

    vim.cmd("GitReview start")
    vim.cmd("GitReview refresh extra")

    vim.notify = original_notify

    return {
      start_calls = vim.g.git_review_setup_dispatcher_start_calls or 0,
      refresh_calls = vim.g.git_review_setup_dispatcher_refresh_calls or 0,
      notifications = notifications,
    }
  end)()]=])

  local notifications = result.notifications or {}
  assert(result.start_calls == 1, "Expected :GitReview start to run once")
  assert(result.refresh_calls == 0, "Expected :GitReview refresh extra to be rejected")
  assert(type(notifications[1]) == "table", "Expected extra-args validation notification")
  assert(
    notifications[1].message
      == "GitReview: subcommand 'refresh' does not accept arguments. Usage: :GitReview refresh",
    "Expected actionable extra-args dispatcher error"
  )
end

set["GitReview comment forwards Ex range context"] = function()
  child.lua([=[
    package.loaded["git-review.session"] = {
      is_active = function()
        return true
      end,
      start = function()
        return { state = "ok" }
      end,
      create_comment = function(opts)
        vim.g.git_review_setup_dispatcher_comment_range_calls =
          (vim.g.git_review_setup_dispatcher_comment_range_calls or 0) + 1
        vim.g.git_review_setup_dispatcher_comment_range_opts = opts
        return { state = "ok" }
      end,
    }

    local original_input = vim.fn.input
    vim.fn.input = function(_)
      return "ranged comment"
    end

    require("git-review").setup()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a", "b", "c", "d", "e" })
    vim.cmd("2,4GitReview comment")

    vim.fn.input = original_input
  ]=])

  local calls = child.lua_get([[vim.g.git_review_setup_dispatcher_comment_range_calls or 0]])
  local opts = child.lua_get([[vim.g.git_review_setup_dispatcher_comment_range_opts]])

  assert(calls == 1, "Expected ranged :GitReview comment to call session.create_comment")
  assert(type(opts) == "table" and opts.body == "ranged comment", "Expected ranged comment body to be forwarded")
  assert(type(opts.context) == "table" and opts.context.start_line == 2, "Expected range start line in comment context")
  assert(type(opts.context) == "table" and opts.context.end_line == 4, "Expected range end line in comment context")
end

set["setup merges options into config defaults"] = function()
  child.lua([[package.loaded["git-review.config"] = nil]])
  child.lua([[require("git-review").setup({ open_comments_panel_on_start = true })]])

  local panel_on_start = child.lua_get([[require("git-review.config").get_open_comments_panel_on_start()]])
  local pr_info_on_start = child.lua_get([[require("git-review.config").get_open_pr_info_on_start()]])
  local cfg = child.lua_get([[require("git-review.config").get()]])

  assert(panel_on_start == true, "Expected open_comments_panel_on_start to be true")
  assert(pr_info_on_start == false, "Expected open_pr_info_on_start default to remain false")
  assert(type(cfg) == "table", "Expected config getter to return a table")
end

set["setup exposes default highlight config"] = function()
  child.lua([[package.loaded["git-review.config"] = nil]])
  child.lua([[require("git-review").setup()]])

  local cfg = child.lua_get([[require("git-review.config").get()]])
  assert(type(cfg.highlights) == "table", "Expected highlights config table")
  assert(cfg.highlights.add == "DiffAdd", "Expected default add highlight group")
  assert(cfg.highlights.change == "DiffChange", "Expected default change highlight group")
end

set["setup merges partial highlight overrides"] = function()
  child.lua([[package.loaded["git-review.config"] = nil]])
  child.lua([[require("git-review").setup({ highlights = { add = "MyAdd" } })]])

  local cfg = child.lua_get([[require("git-review.config").get()]])
  assert(type(cfg.highlights) == "table", "Expected highlights config table")
  assert(cfg.highlights.add == "MyAdd", "Expected add highlight override")
  assert(cfg.highlights.change == "DiffChange", "Expected change highlight default to remain")
end

set["setup exposes default deletion config"] = function()
  child.lua([[package.loaded["git-review.config"] = nil]])
  child.lua([[require("git-review").setup()]])

  local cfg = child.lua_get([[require("git-review.config").get()]])
  assert(type(cfg.highlights) == "table", "Expected highlights config table")
  assert(cfg.highlights.delete == "DiffDelete", "Expected default delete highlight group")
  assert(type(cfg.deletions) == "table", "Expected deletions config table")
  assert(cfg.deletions.enabled == true, "Expected deletions to be enabled by default")
  assert(cfg.deletions.max_preview_lines == 6, "Expected default max deletion preview lines")
  assert(cfg.deletions.default_expanded == false, "Expected default collapsed deletion previews")
end

set["setup merges partial deletion overrides"] = function()
  child.lua([[package.loaded["git-review.config"] = nil]])
  child.lua([[require("git-review").setup({ deletions = { enabled = false } })]])

  local cfg = child.lua_get([[require("git-review.config").get()]])
  assert(type(cfg.deletions) == "table", "Expected deletions config table")
  assert(cfg.deletions.enabled == false, "Expected deletions enabled override")
  assert(cfg.deletions.max_preview_lines == 6, "Expected default max deletion preview lines to remain")
  assert(cfg.deletions.default_expanded == false, "Expected default deletion expansion setting to remain")
end

set["setup exposes default keymap config"] = function()
  child.lua([[package.loaded["git-review.config"] = nil]])
  child.lua([[require("git-review").setup()]])

  local cfg = child.lua_get([[require("git-review.config").get()]])
  assert(type(cfg.keymaps) == "table", "Expected keymaps config table")
  assert(type(cfg.keymaps.normal) == "table", "Expected normal mode keymaps table")
  assert(type(cfg.keymaps.visual) == "table", "Expected visual mode keymaps table")
  assert(cfg.keymaps.enabled == true, "Expected keymaps to be enabled by default")
  assert(cfg.keymaps.prefix == "<leader>gr", "Expected default keymap prefix")
  assert(cfg.keymaps.normal.start == "o", "Expected default normal mode start key")
  assert(cfg.keymaps.normal.stop == "O", "Expected default normal mode stop key")
  assert(cfg.keymaps.normal.submit == "s", "Expected default normal mode submit key")
  assert(cfg.keymaps.normal.action == "c", "Expected default normal mode action key")
  assert(cfg.keymaps.normal.panel == "p", "Expected default normal mode panel key")
  assert(cfg.keymaps.normal.panel_all == "P", "Expected default normal mode panel all key")
  assert(cfg.keymaps.normal.toggle_deletion_block == "b", "Expected default normal mode toggle_deletion_block key")
  assert(cfg.keymaps.normal.toggle_deletions == "d", "Expected default normal mode toggle_deletions key")
  assert(cfg.keymaps.visual.comment == "c", "Expected default visual mode comment key")
end

set["setup merges keymap overrides and supports disable"] = function()
  child.lua([[package.loaded["git-review.config"] = nil]])
  child.lua([[require("git-review").setup({ keymaps = { enabled = false, normal = { stop = "x", panel = false } } })]])

  local cfg = child.lua_get([[require("git-review.config").get()]])
  assert(type(cfg.keymaps) == "table", "Expected keymaps config table")
  assert(type(cfg.keymaps.normal) == "table", "Expected normal mode keymaps table")
  assert(cfg.keymaps.enabled == false, "Expected keymaps enabled override")
  assert(cfg.keymaps.normal.stop == "x", "Expected normal mode stop key override")
  assert(cfg.keymaps.normal.panel == false, "Expected normal mode panel key override")
  assert(cfg.keymaps.normal.start == "o", "Expected default normal mode start key to remain")
end

set["setup keymaps follow active-only lifecycle"] = function()
  child.lua([=[
    package.loaded["git-review.config"] = nil
    package.loaded["git-review.session"] = {
      is_active = function()
        return vim.g.git_review_setup_keymaps_active == true
      end,
      start = function()
        vim.g.git_review_setup_keymaps_active = true
        return { state = "ok" }
      end,
      stop = function()
        vim.g.git_review_setup_keymaps_active = false
        return { state = "ok" }
      end,
    }

    require("git-review").setup()
  ]=])

  local before_start = child.lua_get([[(function()
    local function has_lhs(lhs, mode)
      local map = vim.fn.maparg(lhs, mode, false, true)
      return type(map) == "table" and map.lhs == lhs
    end

    return {
      start = has_lhs("\\gro", "n"),
      stop = has_lhs("\\grO", "n"),
      submit = has_lhs("\\grs", "n"),
      action = has_lhs("\\grc", "n"),
      panel_all = has_lhs("\\grP", "n"),
      toggle_block = has_lhs("\\grb", "n"),
      toggle_all = has_lhs("\\grd", "n"),
      visual_comment = has_lhs("\\grc", "x"),
    }
  end)()]])

  assert(before_start.start == true, "Expected always-on start/toggle mapping")
  assert(before_start.stop == false, "Expected stop mapping to be inactive before start")
  assert(before_start.submit == false, "Expected submit mapping to be inactive before start")
  assert(before_start.action == false, "Expected action mapping to be inactive before start")
  assert(before_start.panel_all == false, "Expected panel-all mapping to be inactive before start")
  assert(before_start.toggle_block == false, "Expected toggle block mapping to be inactive before start")
  assert(before_start.toggle_all == false, "Expected toggle deletions mapping to be inactive before start")
  assert(before_start.visual_comment == false, "Expected visual comment mapping to be inactive before start")

  child.lua([[vim.cmd("GitReview start")]])

  local after_start = child.lua_get([[(function()
    local function has_lhs(lhs, mode)
      local map = vim.fn.maparg(lhs, mode, false, true)
      return type(map) == "table" and map.lhs == lhs
    end

    return {
      stop = has_lhs("\\grO", "n"),
      submit = has_lhs("\\grs", "n"),
      action = has_lhs("\\grc", "n"),
      panel_all = has_lhs("\\grP", "n"),
      toggle_block = has_lhs("\\grb", "n"),
      toggle_all = has_lhs("\\grd", "n"),
      visual_comment = has_lhs("\\grc", "x"),
    }
  end)()]])

  assert(after_start.stop == true, "Expected stop mapping to register after start")
  assert(after_start.submit == true, "Expected submit mapping to register after start")
  assert(after_start.action == true, "Expected action mapping to register after start")
  assert(after_start.panel_all == true, "Expected panel-all mapping to register after start")
  assert(after_start.toggle_block == true, "Expected toggle block mapping to register after start")
  assert(after_start.toggle_all == true, "Expected toggle deletions mapping to register after start")
  assert(after_start.visual_comment == true, "Expected visual comment mapping to register after start")

  child.lua([[vim.cmd("GitReview stop")]])

  local after_stop = child.lua_get([[(function()
    local function has_lhs(lhs, mode)
      local map = vim.fn.maparg(lhs, mode, false, true)
      return type(map) == "table" and map.lhs == lhs
    end

    return {
      start = has_lhs("\\gro", "n"),
      stop = has_lhs("\\grO", "n"),
      submit = has_lhs("\\grs", "n"),
      action = has_lhs("\\grc", "n"),
      panel_all = has_lhs("\\grP", "n"),
      toggle_block = has_lhs("\\grb", "n"),
      toggle_all = has_lhs("\\grd", "n"),
      visual_comment = has_lhs("\\grc", "x"),
    }
  end)()]])

  assert(after_stop.start == true, "Expected always-on start/toggle mapping to remain")
  assert(after_stop.stop == false, "Expected stop mapping removed on stop")
  assert(after_stop.submit == false, "Expected submit mapping removed on stop")
  assert(after_stop.action == false, "Expected action mapping removed on stop")
  assert(after_stop.panel_all == false, "Expected panel-all mapping removed on stop")
  assert(after_stop.toggle_block == false, "Expected toggle block mapping removed on stop")
  assert(after_stop.toggle_all == false, "Expected toggle deletions mapping removed on stop")
  assert(after_stop.visual_comment == false, "Expected visual comment mapping removed on stop")
end

set["setup registers active keymaps when start succeeds without state field"] = function()
  child.lua([=[
    package.loaded["git-review.config"] = nil
    package.loaded["git-review.session"] = {
      is_active = function()
        return vim.g.git_review_setup_keymaps_active == true
      end,
      start = function()
        vim.g.git_review_setup_keymaps_active = true
        return { hunks = {} }
      end,
      stop = function()
        vim.g.git_review_setup_keymaps_active = false
        return { state = "ok" }
      end,
    }

    require("git-review").setup()
    vim.cmd("GitReview start")
  ]=])

  local has_active_map = child.lua_get([[(function()
    local map = vim.fn.maparg("\\grs", "n", false, true)
    return type(map) == "table" and map.lhs == "\\grs"
  end)()]])

  assert(has_active_map == true, "Expected submit keymap to register after successful start")
end

set["setup restores pre-existing user mapping after active lifecycle"] = function()
  child.lua([=[
    package.loaded["git-review.config"] = nil
    vim.keymap.set("n", "\\grO", "<cmd>echo 'user-stop'<cr>", { desc = "User stop mapping" })

    package.loaded["git-review.session"] = {
      is_active = function()
        return vim.g.git_review_setup_keymaps_active == true
      end,
      start = function()
        vim.g.git_review_setup_keymaps_active = true
        return { state = "ok" }
      end,
      stop = function()
        vim.g.git_review_setup_keymaps_active = false
        return { state = "ok" }
      end,
    }

    require("git-review").setup()
    vim.cmd("GitReview start")
    vim.cmd("GitReview stop")
  ]=])

  local restored = child.lua_get([[(function()
    local map = vim.fn.maparg("\\grO", "n", false, true)
    return {
      lhs = type(map) == "table" and map.lhs or nil,
      rhs = type(map) == "table" and map.rhs or nil,
      desc = type(map) == "table" and map.desc or nil,
    }
  end)()]])

  assert(restored.lhs == "\\grO", "Expected pre-existing stop lhs to be restored after stop")
  assert(restored.rhs == "<cmd>echo 'user-stop'<cr>", "Expected pre-existing stop rhs to be restored after stop")
  assert(restored.desc == "User stop mapping", "Expected pre-existing stop desc to be restored after stop")
end

set["setup preserves buffer-local keymap scope after active lifecycle"] = function()
  local restored = child.lua_get([=[(function()
    package.loaded["git-review.config"] = nil

    local review_buf = vim.api.nvim_create_buf(false, true)
    local other_buf = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_set_current_buf(review_buf)
    vim.keymap.set("n", "\\grO", "<cmd>echo 'buffer-stop'<cr>", {
      buffer = review_buf,
      desc = "Buffer stop mapping",
    })

    package.loaded["git-review.session"] = {
      is_active = function()
        return vim.g.git_review_setup_keymaps_active == true
      end,
      start = function()
        vim.g.git_review_setup_keymaps_active = true
        return { state = "ok" }
      end,
      stop = function()
        vim.g.git_review_setup_keymaps_active = false
        return { state = "ok" }
      end,
    }

    require("git-review").setup()
    vim.cmd("GitReview start")
    vim.cmd("GitReview stop")

    vim.api.nvim_set_current_buf(review_buf)
    local local_map = vim.fn.maparg("\\grO", "n", false, true)

    vim.api.nvim_set_current_buf(other_buf)
    local leaked_map = vim.fn.maparg("\\grO", "n", false, true)

    return {
      local_lhs = type(local_map) == "table" and local_map.lhs or nil,
      local_rhs = type(local_map) == "table" and local_map.rhs or nil,
      local_desc = type(local_map) == "table" and local_map.desc or nil,
      local_buffer = type(local_map) == "table" and local_map.buffer or nil,
      leaked_lhs = type(leaked_map) == "table" and leaked_map.lhs or nil,
    }
  end)()]=])

  assert(restored.local_lhs == "\\grO", "Expected buffer-local mapping lhs to remain in original buffer")
  assert(restored.local_rhs == "<cmd>echo 'buffer-stop'<cr>", "Expected buffer-local mapping rhs to remain in original buffer")
  assert(restored.local_desc == "Buffer stop mapping", "Expected buffer-local mapping desc to remain in original buffer")
  assert(restored.local_buffer == 1, "Expected mapping to remain buffer-local")
  assert(restored.leaked_lhs == nil, "Expected no leaked global mapping in other buffers")
end

set["setup reconciles active keymaps when session becomes inactive"] = function()
  child.lua([=[
    package.loaded["git-review.config"] = nil
    package.loaded["git-review.session"] = {
      is_active = function()
        return vim.g.git_review_setup_keymaps_active == true
      end,
      start = function()
        vim.g.git_review_setup_keymaps_active = true
        return { state = "ok" }
      end,
      refresh = function()
        vim.g.git_review_setup_reconcile_refresh_calls = (vim.g.git_review_setup_reconcile_refresh_calls or 0) + 1
        return { state = "ok" }
      end,
    }

    require("git-review").setup()
    vim.cmd("GitReview start")
    vim.g.git_review_setup_keymaps_active = false
    local ok = pcall(vim.cmd, "GitReview refresh")
    vim.g.git_review_setup_reconcile_refresh_ok = ok
  ]=])

  local state = child.lua_get([[(function()
    local map = vim.fn.maparg("\\grs", "n", false, true)
    return {
      submit_present = type(map) == "table" and map.lhs == "\\grs",
      refresh_calls = vim.g.git_review_setup_reconcile_refresh_calls or 0,
      refresh_ok = vim.g.git_review_setup_reconcile_refresh_ok,
    }
  end)()]])

  assert(state.submit_present == false, "Expected active submit mapping to be removed after inactive reconciliation")
  assert(state.refresh_calls == 0, "Expected inactive reconciliation path to block session.refresh")
  assert(state.refresh_ok == false, "Expected inactive refresh command to report non-active session")
end

set["setup skips keymaps with false suffix and disabled keymaps"] = function()
  child.lua([[package.loaded["git-review.config"] = nil]])
  child.lua([[pcall(vim.keymap.del, "n", "\\gro")]])
  child.lua([[pcall(vim.keymap.del, "n", "\\grp")]])
  child.lua([[pcall(vim.keymap.del, "x", "\\grc")]])
  child.lua([=[
    package.loaded["git-review.session"] = {
      is_active = function()
        return vim.g.git_review_setup_keymaps_active == true
      end,
      start = function()
        vim.g.git_review_setup_keymaps_active = true
        return { state = "ok" }
      end,
    }

    require("git-review").setup({ keymaps = { normal = { panel = false }, visual = { comment = false } } })
    vim.cmd("GitReview start")
  ]=])

  local panel_map = child.lua_get([[vim.fn.mapcheck("\\grp", "n")]])
  local visual_comment_map = child.lua_get([[vim.fn.mapcheck("\\grc", "x")]])
  assert(panel_map == "", "Expected false panel suffix to skip mapping")
  assert(visual_comment_map == "", "Expected false visual comment suffix to skip mapping")

  child.restart({ "-u", "tests/minimal_init.lua" })
  child.lua([[package.loaded["git-review.config"] = nil]])
  child.lua([[pcall(vim.keymap.del, "n", "\\gro")]])
  child.lua([[require("git-review").setup({ keymaps = { enabled = false } })]])
  local start_map = child.lua_get([[vim.fn.mapcheck("\\gro", "n")]])
  assert(start_map == "", "Expected disabled keymaps to skip start mapping")
end

set["setup wires action and deletion keymaps to session behavior"] = function()
  child.lua([=[
    package.loaded["git-review.session"] = {
      is_active = function()
        return vim.g.git_review_setup_active == true
      end,
      start = function()
        vim.g.git_review_setup_active = true
        return { state = "ok" }
      end,
      reply_to_selected_thread = function(opts)
        vim.g.git_review_setup_reply_calls = (vim.g.git_review_setup_reply_calls or 0) + 1
        vim.g.git_review_setup_reply_thread_id = type(opts) == "table" and opts.thread_id or nil
        return { state = "ok" }
      end,
      create_comment = function(opts)
        vim.g.git_review_setup_comment_calls = (vim.g.git_review_setup_comment_calls or 0) + 1
        vim.g.git_review_setup_comment_opts = opts
        return { state = "ok" }
      end,
      toggle_current_deletion_block = function()
        vim.g.git_review_setup_toggle_block_calls = (vim.g.git_review_setup_toggle_block_calls or 0) + 1
        return { state = "ok" }
      end,
      toggle_deletion_blocks = function()
        vim.g.git_review_setup_toggle_all_calls = (vim.g.git_review_setup_toggle_all_calls or 0) + 1
        return { state = "ok" }
      end,
    }

    package.loaded["git-review.ui.panel"] = {
      get_selected_thread_id = function(opts)
        vim.g.git_review_setup_panel_bufnr = type(opts) == "table" and opts.bufnr or nil
        vim.g.git_review_setup_panel_line = type(opts) == "table" and opts.cursor_line or nil
        return vim.g.git_review_setup_selected_thread_id
      end,
    }

    local original_input = vim.fn.input
    vim.fn.input = function(_)
      return vim.g.git_review_setup_input_body or ""
    end

    require("git-review").setup()
    vim.cmd("GitReview start")

    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a", "b", "c" })
    vim.api.nvim_win_set_cursor(0, { 3, 0 })

    local function press(mode, lhs)
      local map = vim.fn.maparg(lhs, mode, false, true)
      if type(map) == "table" and type(map.callback) == "function" then
        map.callback()
        return
      end

      local keys = vim.api.nvim_replace_termcodes(lhs, true, false, true)
      vim.api.nvim_feedkeys(keys, "mxt", false)
    end

    vim.g.git_review_setup_selected_thread_id = "thread-9"
    vim.g.git_review_setup_input_body = "unused"
    press("n", "\\grc")

    vim.g.git_review_setup_selected_thread_id = nil
    vim.g.git_review_setup_input_body = "new comment"
    press("n", "\\grc")
    press("n", "\\grb")
    press("n", "\\grd")

    vim.fn.input = original_input
  ]=])

  local reply_calls = child.lua_get([[vim.g.git_review_setup_reply_calls or 0]])
  local reply_thread_id = child.lua_get([[vim.g.git_review_setup_reply_thread_id]])
  local panel_bufnr = child.lua_get([[vim.g.git_review_setup_panel_bufnr]])
  local panel_line = child.lua_get([[vim.g.git_review_setup_panel_line]])
  local comment_calls = child.lua_get([[vim.g.git_review_setup_comment_calls or 0]])
  local comment_opts = child.lua_get([[vim.g.git_review_setup_comment_opts]])
  local toggle_block_calls = child.lua_get([[vim.g.git_review_setup_toggle_block_calls or 0]])
  local toggle_all_calls = child.lua_get([[vim.g.git_review_setup_toggle_all_calls or 0]])

  assert(reply_calls == 1, "Expected action mapping to reply when thread is selected")
  assert(reply_thread_id == "thread-9", "Expected selected thread id to be forwarded to reply")
  assert(type(panel_bufnr) == "number" and panel_bufnr > 0, "Expected action mapping to pass current bufnr to panel lookup")
  assert(panel_line == 3, "Expected action mapping to pass cursor line to panel lookup")
  assert(comment_calls == 1, "Expected action mapping to create comment when no thread is selected")
  assert(type(comment_opts) == "table" and comment_opts.body == "new comment", "Expected prompted comment body to be forwarded")
  assert(type(comment_opts.context) == "table" and comment_opts.context.start_line == 3, "Expected comment context start line")
  assert(type(comment_opts.context) == "table" and comment_opts.context.end_line == 3, "Expected comment context end line")
  assert(toggle_block_calls == 1, "Expected b mapping to call toggle_current_deletion_block")
  assert(toggle_all_calls == 1, "Expected d mapping to call toggle_deletion_blocks")
end

set["setup merges deletion max_preview_lines override"] = function()
  child.lua([[package.loaded["git-review.config"] = nil]])
  child.lua([[require("git-review").setup({ deletions = { max_preview_lines = 12 } })]])

  local cfg = child.lua_get([[require("git-review.config").get()]])
  assert(type(cfg.deletions) == "table", "Expected deletions config table")
  assert(cfg.deletions.enabled == true, "Expected default deletions enabled setting to remain")
  assert(cfg.deletions.max_preview_lines == 12, "Expected max deletion preview lines override")
  assert(cfg.deletions.default_expanded == false, "Expected default deletion expansion setting to remain")
end

set["setup rejects deletion max_preview_lines of zero"] = function()
  child.lua([[package.loaded["git-review.config"] = nil]])

  local result = child.lua_get([[(function()
    local ok, err = pcall(require("git-review").setup, { deletions = { max_preview_lines = 0 } })
    return { ok = ok, err = err }
  end)()]])

  assert(result.ok == false, "Expected setup to reject zero max_preview_lines")
  assert(type(result.err) == "string", "Expected setup error message for zero max_preview_lines")
  assert(string.find(result.err, "deletions_max_preview_lines", 1, true), "Expected max_preview_lines validation error")
end

set["setup rejects negative deletion max_preview_lines"] = function()
  child.lua([[package.loaded["git-review.config"] = nil]])

  local result = child.lua_get([[(function()
    local ok, err = pcall(require("git-review").setup, { deletions = { max_preview_lines = -3 } })
    return { ok = ok, err = err }
  end)()]])

  assert(result.ok == false, "Expected setup to reject negative max_preview_lines")
  assert(type(result.err) == "string", "Expected setup error message for negative max_preview_lines")
  assert(string.find(result.err, "deletions_max_preview_lines", 1, true), "Expected max_preview_lines validation error")
end

set["setup rejects non-integer deletion max_preview_lines"] = function()
  child.lua([[package.loaded["git-review.config"] = nil]])

  local result = child.lua_get([[(function()
    local ok, err = pcall(require("git-review").setup, { deletions = { max_preview_lines = 1.5 } })
    return { ok = ok, err = err }
  end)()]])

  assert(result.ok == false, "Expected setup to reject non-integer max_preview_lines")
  assert(type(result.err) == "string", "Expected setup error message for non-integer max_preview_lines")
  assert(string.find(result.err, "deletions_max_preview_lines", 1, true), "Expected max_preview_lines validation error")
end

set["setup rejects empty-string keymap action values"] = function()
  child.lua([[package.loaded["git-review.config"] = nil]])

  local result = child.lua_get([[(function()
    local ok, err = pcall(require("git-review").setup, { keymaps = { normal = { action = "" } } })
    return { ok = ok, err = err }
  end)()]])

  assert(result.ok == false, "Expected setup to reject empty-string keymap actions")
  assert(type(result.err) == "string", "Expected setup error message for empty-string keymap action")
  assert(string.find(result.err, "keymaps_normal_action", 1, true), "Expected keymaps_normal_action validation error")
end

set["setup rejects invalid keymap action value types"] = function()
  child.lua([[package.loaded["git-review.config"] = nil]])

  local number_result = child.lua_get([[(function()
    local ok, err = pcall(require("git-review").setup, { keymaps = { normal = { action = 1 } } })
    return { ok = ok, err = err }
  end)()]])

  assert(number_result.ok == false, "Expected setup to reject numeric keymap action values")
  assert(type(number_result.err) == "string", "Expected setup error message for numeric keymap action")
  assert(string.find(number_result.err, "keymaps_normal_action", 1, true), "Expected keymaps_normal_action validation error")

  local table_result = child.lua_get([[(function()
    local ok, err = pcall(require("git-review").setup, { keymaps = { visual = { comment = {} } } })
    return { ok = ok, err = err }
  end)()]])

  assert(table_result.ok == false, "Expected setup to reject table keymap action values")
  assert(type(table_result.err) == "string", "Expected setup error message for table keymap action")
  assert(string.find(table_result.err, "keymaps_visual_comment", 1, true), "Expected keymaps_visual_comment validation error")
end

set["setup rejects invalid keymaps container types"] = function()
  child.lua([[package.loaded["git-review.config"] = nil]])

  local normal_result = child.lua_get([[(function()
    local ok, err = pcall(require("git-review").setup, { keymaps = { normal = "bad" } })
    return { ok = ok, err = err }
  end)()]])

  assert(normal_result.ok == false, "Expected setup to reject non-table keymaps.normal")
  assert(type(normal_result.err) == "string", "Expected setup error message for invalid keymaps.normal")
  assert(string.find(normal_result.err, "keymaps_normal", 1, true), "Expected keymaps_normal validation error")

  local visual_result = child.lua_get([[(function()
    local ok, err = pcall(require("git-review").setup, { keymaps = { visual = 2 } })
    return { ok = ok, err = err }
  end)()]])

  assert(visual_result.ok == false, "Expected setup to reject non-table keymaps.visual")
  assert(type(visual_result.err) == "string", "Expected setup error message for invalid keymaps.visual")
  assert(string.find(visual_result.err, "keymaps_visual", 1, true), "Expected keymaps_visual validation error")
end

set["repo fixture helper make_repo returns normalized repo table"] = function()
  local fixture = require("tests.helpers.repo_fixture")
  assert(type(fixture.make_repo) == "function", "Expected repo_fixture.make_repo to be a function")

  local repo = fixture.make_repo({ path = "tests/../tests" })

  assert(type(repo) == "table", "Expected make_repo to return a table")
  assert(type(repo.path) == "string", "Expected repo.path to be a string")
  assert(repo.path == vim.fs.normalize("tests/../tests"), "Expected repo.path to be normalized")
end

set["repo fixture helper make_repo validates input"] = function()
  local fixture = require("tests.helpers.repo_fixture")

  local ok_opts_type, err_opts_type = pcall(fixture.make_repo, "bad")
  assert(not ok_opts_type, "Expected make_repo to reject non-table opts")
  assert(string.find(err_opts_type, "opts must be a table", 1, true), "Expected opts type validation error")

  local ok_missing_path, err_missing_path = pcall(fixture.make_repo, {})
  assert(not ok_missing_path, "Expected make_repo to require opts.path")
  assert(string.find(err_missing_path, "opts.path must be a non-empty string", 1, true), "Expected missing path validation error")

  local ok_empty_path, err_empty_path = pcall(fixture.make_repo, { path = "" })
  assert(not ok_empty_path, "Expected make_repo to reject empty opts.path")
  assert(string.find(err_empty_path, "opts.path must be a non-empty string", 1, true), "Expected empty path validation error")
end

return set
