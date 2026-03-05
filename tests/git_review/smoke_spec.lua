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

set["bootstrap registers user commands on startup"] = function()
  local dispatcher_exists = child.lua_get([[vim.fn.exists(":GitReview")]])
  local legacy_start_exists = child.lua_get([[vim.fn.exists(":GitReviewStart")]])
  local legacy_refresh_exists = child.lua_get([[vim.fn.exists(":GitReviewRefresh")]])
  local legacy_comment_exists = child.lua_get([[vim.fn.exists(":GitReviewComment")]])
  local legacy_reply_exists = child.lua_get([[vim.fn.exists(":GitReviewReply")]])
  local legacy_diff_exists = child.lua_get([[vim.fn.exists(":GitReviewDiff")]])
  local legacy_stop_exists = child.lua_get([[vim.fn.exists(":GitReviewStop")]])

  assert(dispatcher_exists == 2, "Expected :GitReview command")
  assert(legacy_start_exists == 0, "Expected no :GitReviewStart command")
  assert(legacy_refresh_exists == 0, "Expected no :GitReviewRefresh command")
  assert(legacy_comment_exists == 0, "Expected no :GitReviewComment command")
  assert(legacy_reply_exists == 0, "Expected no :GitReviewReply command")
  assert(legacy_diff_exists == 0, "Expected no :GitReviewDiff command")
  assert(legacy_stop_exists == 0, "Expected no :GitReviewStop command")
end

set["commands are wired to session module"] = function()
  child.lua([[
    package.loaded["git-review.session"] = {
      is_active = function()
        return vim.g.git_review_smoke_active == true
      end,
      start = function()
        vim.g.git_review_smoke_start_calls = (vim.g.git_review_smoke_start_calls or 0) + 1
        vim.g.git_review_smoke_active = true
        return { state = "ok", hunks = {}, thread_state = "ok" }
      end,
      stop = function()
        vim.g.git_review_smoke_stop_calls = (vim.g.git_review_smoke_stop_calls or 0) + 1
        vim.g.git_review_smoke_active = false
        return { state = "ok" }
      end,
      refresh = function()
        vim.g.git_review_smoke_refresh_calls = (vim.g.git_review_smoke_refresh_calls or 0) + 1
        return { state = "ok", hunks = {} }
      end,
      reply_to_selected_thread = function()
        vim.g.git_review_smoke_reply_calls = (vim.g.git_review_smoke_reply_calls or 0) + 1
        return { state = "ok" }
      end,
      create_comment = function(opts)
        vim.g.git_review_smoke_comment_calls = (vim.g.git_review_smoke_comment_calls or 0) + 1
        vim.g.git_review_smoke_comment_opts = opts
        return { state = "ok" }
      end,
      open_panel = function()
        vim.g.git_review_smoke_panel_calls = (vim.g.git_review_smoke_panel_calls or 0) + 1
        return { state = "ok" }
      end,
      open_panel_toggle = function(opts)
        local scope = type(opts) == "table" and opts.scope or ""
        if scope == "all" then
          vim.g.git_review_smoke_panel_all_calls = (vim.g.git_review_smoke_panel_all_calls or 0) + 1
        else
          vim.g.git_review_smoke_panel_calls = (vim.g.git_review_smoke_panel_calls or 0) + 1
        end
        return { state = "ok" }
      end,
      toggle_current_deletion_block = function()
        vim.g.git_review_smoke_toggle_deletion_calls = (vim.g.git_review_smoke_toggle_deletion_calls or 0) + 1
        return { state = "ok" }
      end,
      expand_deletion_blocks = function()
        vim.g.git_review_smoke_expand_deletions_calls = (vim.g.git_review_smoke_expand_deletions_calls or 0) + 1
        return { state = "ok" }
      end,
      collapse_deletion_blocks = function()
        vim.g.git_review_smoke_collapse_deletions_calls = (vim.g.git_review_smoke_collapse_deletions_calls or 0) + 1
        return { state = "ok" }
      end,
      open_pr_info = function()
        vim.g.git_review_smoke_info_calls = (vim.g.git_review_smoke_info_calls or 0) + 1
        return { state = "ok" }
      end,
    }

    local original_input = vim.fn.input
    vim.fn.input = function(_)
      return "dispatcher comment body"
    end

    vim.cmd("GitReview start")
    vim.cmd("GitReview refresh")
    vim.cmd("GitReview reply")
    vim.cmd("GitReview comment")
    vim.cmd("GitReview panel")
    vim.cmd("GitReview panel-all")
    vim.cmd("GitReview toggle-deletion-block")
    vim.cmd("GitReview expand-deletion-blocks")
    vim.cmd("GitReview collapse-deletion-blocks")
    vim.cmd("GitReview info")
    vim.cmd("GitReview stop")

    vim.fn.input = original_input
  ]])

  local start_calls = child.lua_get([[vim.g.git_review_smoke_start_calls or 0]])
  local stop_calls = child.lua_get([[vim.g.git_review_smoke_stop_calls or 0]])
  local refresh_calls = child.lua_get([[vim.g.git_review_smoke_refresh_calls or 0]])
  local reply_calls = child.lua_get([[vim.g.git_review_smoke_reply_calls or 0]])
  local comment_calls = child.lua_get([[vim.g.git_review_smoke_comment_calls or 0]])
  local comment_opts = child.lua_get([[vim.g.git_review_smoke_comment_opts]])
  local panel_calls = child.lua_get([[vim.g.git_review_smoke_panel_calls or 0]])
  local panel_all_calls = child.lua_get([[vim.g.git_review_smoke_panel_all_calls or 0]])
  local toggle_deletion_calls = child.lua_get([[vim.g.git_review_smoke_toggle_deletion_calls or 0]])
  local expand_deletions_calls = child.lua_get([[vim.g.git_review_smoke_expand_deletions_calls or 0]])
  local collapse_deletions_calls = child.lua_get([[vim.g.git_review_smoke_collapse_deletions_calls or 0]])
  local info_calls = child.lua_get([[vim.g.git_review_smoke_info_calls or 0]])

  assert(start_calls == 1, "Expected :GitReview start to call session.start")
  assert(stop_calls == 1, "Expected :GitReview stop to call session.stop")
  assert(refresh_calls == 1, "Expected :GitReview refresh to call session.refresh")
  assert(reply_calls == 1, "Expected :GitReview reply to call session.reply_to_selected_thread")
  assert(comment_calls == 1, "Expected :GitReview comment to call session.create_comment")
  assert(type(comment_opts) == "table" and comment_opts.body == "dispatcher comment body", "Expected :GitReview comment to pass prompt body")
  assert(panel_calls == 1, "Expected :GitReview panel to call session.open_panel_toggle(current)")
  assert(panel_all_calls == 1, "Expected :GitReview panel-all to call session.open_panel_toggle(all)")
  assert(toggle_deletion_calls == 1, "Expected :GitReview toggle-deletion-block to call session.toggle_current_deletion_block")
  assert(expand_deletions_calls == 1, "Expected :GitReview expand-deletion-blocks to call session.expand_deletion_blocks")
  assert(collapse_deletions_calls == 1, "Expected :GitReview collapse-deletion-blocks to call session.collapse_deletion_blocks")
  assert(info_calls == 1, "Expected :GitReview info to call session.open_pr_info")
end

return set
