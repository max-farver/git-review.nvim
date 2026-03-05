local T = require("mini.test")

local child = T.new_child_neovim()

local set = T.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "tests/minimal_init.lua" })
      child.lua([[package.loaded["git-review"] = nil]])
      child.lua([[package.loaded["git-review.session"] = nil]])
    end,
    post_once = function()
      child.stop()
    end,
  },
})

set["setup registers dispatcher command only"] = function()
  child.lua([[
    pcall(vim.api.nvim_del_user_command, "GitReview")
    require("git-review").setup()
  ]])

  local dispatcher_exists = child.lua_get([[vim.fn.exists(":GitReview")]])
  local refresh_exists = child.lua_get([[vim.fn.exists(":GitReviewRefresh")]])
  local comment_exists = child.lua_get([[vim.fn.exists(":GitReviewComment")]])
  local reply_exists = child.lua_get([[vim.fn.exists(":GitReviewReply")]])

  assert(dispatcher_exists == 2, "Expected :GitReview command")
  assert(refresh_exists == 0, "Expected no :GitReviewRefresh command")
  assert(comment_exists == 0, "Expected no :GitReviewComment command")
  assert(reply_exists == 0, "Expected no :GitReviewReply command")
end

set[":GitReview refresh surfaces no_pr with actionable message"] = function()
  child.lua([[
    local original_notify = vim.notify
    vim.g.git_review_notify_message = nil

    vim.notify = function(message, _)
      vim.g.git_review_notify_message = message
    end

    package.loaded["git-review.session"] = {
      is_active = function()
        return true
      end,
      refresh = function()
        return {
          state = "no_pr",
          message = "No pull request is associated with this branch",
        }
      end,
    }

    require("git-review").setup()
    vim.cmd("GitReview refresh")

    vim.notify = original_notify
  ]])

  local notify_message = child.lua_get([[vim.g.git_review_notify_message]])
  assert(type(notify_message) == "string", "Expected notify message")
  assert(
    notify_message
      == "GitReviewRefresh failed: No pull request is associated with this branch. Push your branch and open a pull request, then run :GitReview refresh.",
    "Expected explicit no_pr guidance"
  )
end

set[":GitReview comment passes command range to session context"] = function()
  child.lua([=[
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.getcwd() .. "/lua/git-review/init.lua")
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "one",
      "two",
      "three",
      "four",
      "five",
    })

    vim.g.git_review_comment_context = nil
    vim.g.git_review_comment_body = nil

    local original_input = vim.fn.input
    vim.fn.input = function(_)
      return "new comment"
    end

    package.loaded["git-review.session"] = {
      is_active = function()
        return true
      end,
      create_comment = function(opts)
        vim.g.git_review_comment_context = opts.context
        vim.g.git_review_comment_body = opts.body
        return { state = "ok" }
      end,
    }

    require("git-review").setup()
    vim.cmd("2,4GitReview comment")

    vim.fn.input = original_input
  ]=])

  local context = child.lua_get([[vim.g.git_review_comment_context]])
  local body = child.lua_get([[vim.g.git_review_comment_body]])

  assert(type(context) == "table", "Expected context table")
  assert(context.start_line == 2, "Expected start line from command range")
  assert(context.end_line == 4, "Expected end line from command range")
  assert(body == "new comment", "Expected prompted comment body")
end

set[":GitReview comment surfaces missing context guidance"] = function()
  child.lua([[
    local original_notify = vim.notify
    vim.g.git_review_notify_message = nil

    vim.notify = function(message, _)
      vim.g.git_review_notify_message = message
    end

    local original_input = vim.fn.input
    vim.fn.input = function(_)
      return "new comment"
    end

    package.loaded["git-review.session"] = {
      is_active = function()
        return true
      end,
      create_comment = function(_)
        return {
          state = "context_error",
          message = "No diff text available for position mapping",
        }
      end,
    }

    require("git-review").setup()
    vim.cmd("GitReview comment")

    vim.fn.input = original_input
    vim.notify = original_notify
  ]])

  local notify_message = child.lua_get([[vim.g.git_review_notify_message]])
  assert(type(notify_message) == "string", "Expected notify message")
  assert(
    notify_message
      == "GitReviewComment failed: No diff text available for position mapping. Run :GitReview start on a pull request branch, then run :GitReview refresh.",
    "Expected explicit missing context guidance"
  )
end

set[":GitReview reply surfaces gh auth failures with recovery guidance"] = function()
  child.lua([[
    local original_notify = vim.notify
    vim.g.git_review_notify_message = nil

    vim.notify = function(message, _)
      vim.g.git_review_notify_message = message
    end

    package.loaded["git-review.session"] = {
      is_active = function()
        return true
      end,
      reply_to_selected_thread = function()
        return {
          state = "command_error",
          message = "gh: To authenticate, run: gh auth login",
        }
      end,
    }

    require("git-review").setup()
    vim.cmd("GitReview reply")

    vim.notify = original_notify
  ]])

  local notify_message = child.lua_get([[vim.g.git_review_notify_message]])
  assert(type(notify_message) == "string", "Expected notify message")
  assert(string.find(notify_message, "gh auth login", 1, true), "Expected auth guidance in message")
end

set[":GitReview comment creates comment through session.create_comment and adapter"] = function()
  child.lua([=[
    package.loaded["git-review"] = nil
    package.loaded["git-review.session"] = nil
    package.loaded["git-review.github"] = nil

    local session = require("git-review.session")
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -10,2 +10,3 @@
 local M = {}
+local x = 1
 return M
]]

    local adapter_calls = 0
    local adapter_payload

    package.loaded["git-review.github"] = {
      create_review_comment = function(comment)
        adapter_calls = adapter_calls + 1
        adapter_payload = comment
        return {
          state = "ok",
          comment = { id = 123 },
        }
      end,
    }

    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, "/tmp/git-review-repo/lua/git-review/init.lua")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "line 1",
      "line 2",
      "line 3",
      "line 4",
      "line 5",
      "line 6",
      "line 7",
      "line 8",
      "line 9",
      "local M = {}",
      "local x = 1",
      "return M",
    })
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 11, 0 })

    session.start({
      diff_command = { "git", "diff", "--no-color", "origin/main...HEAD" },
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--show-toplevel"
        then
          return {
            code = 0,
            stdout = "/tmp/git-review-repo\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "HEAD"
        then
          return {
            code = 0,
            stdout = "abc123\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "config"
          and command[3] == "--get"
          and command[4] == "remote.origin.url"
        then
          return {
            code = 0,
            stdout = "git@github.com:acme/repo.git\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
        then
          return {
            code = 0,
            stdout = diff,
            stderr = "",
          }
        end

        return {
          code = 1,
          stdout = "",
          stderr = "unexpected command",
        }
      end,
      resolve_branch = function(_)
        return "feature/task-9"
      end,
      resolve_pr_for_branch = function(_, _)
        return {
          state = "single_pr",
          pr = { number = 42 },
        }
      end,
      fetch_review_threads = function(_, _)
        return {
          state = "ok",
          threads = {},
        }
      end,
      panel = {
        render = function(_) end,
      },
    })

    local original_input = vim.fn.input
    vim.fn.input = function(_)
      return "new comment"
    end

    require("git-review").setup()
    vim.cmd("GitReview comment")

    vim.fn.input = original_input

    vim.g.git_review_comment_adapter_calls = adapter_calls
    vim.g.git_review_comment_adapter_payload = adapter_payload
  ]=])

  local calls = child.lua_get([[vim.g.git_review_comment_adapter_calls]])
  local payload = child.lua_get([[vim.g.git_review_comment_adapter_payload]])

  assert(calls == 1, "Expected adapter create_review_comment call")
  assert(type(payload) == "table", "Expected adapter payload")
  assert(payload.repo == "acme/repo", "Expected repo in adapter payload")
  assert(payload.pr_number == 42, "Expected pr_number in adapter payload")
  assert(payload.commit_id == "abc123", "Expected commit_id in adapter payload")
  assert(payload.path == "lua/git-review/init.lua", "Expected path in adapter payload")
  assert(payload.body == "new comment", "Expected body in adapter payload")
  assert(payload.position == 2, "Expected mapped position in adapter payload")
end

return set
