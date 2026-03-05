local T = require("mini.test")

local child = T.new_child_neovim()

local set = T.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "tests/minimal_init.lua" })
      child.lua([[package.loaded["git-review.session"] = nil]])
    end,
    post_once = function()
      child.stop()
    end,
  },
})

set["session.submit_review submits APPROVE with optional body"] = function()
  child.lua([=[
    local session = require("git-review.session")
    local payload

    local result = session.submit_review({
      repo = "acme/repo",
      pr_number = 42,
      event = "APPROVE",
      body = "Looks good",
      submit_review = function(review_payload)
        payload = review_payload
        return { state = "ok", review = { id = 1 } }
      end,
    })

    vim.g.git_review_submit_approve_result = result
    vim.g.git_review_submit_approve_payload = payload
  ]=])

  local result = child.lua_get([[vim.g.git_review_submit_approve_result]])
  local payload = child.lua_get([[vim.g.git_review_submit_approve_payload]])

  assert(type(result) == "table" and result.state == "ok", "Expected successful submit")
  assert(type(payload) == "table", "Expected submit payload table")
  assert(payload.repo == "acme/repo", "Expected repo in payload")
  assert(payload.pr_number == 42, "Expected pr_number in payload")
  assert(payload.event == "APPROVE", "Expected APPROVE event in payload")
  assert(payload.body == "Looks good", "Expected body in payload")
end

set["session.submit_review submits REQUEST_CHANGES with empty body allowed"] = function()
  child.lua([=[
    local session = require("git-review.session")
    local payload

    local result = session.submit_review({
      repo = "acme/repo",
      pr_number = 42,
      event = "REQUEST_CHANGES",
      body = "",
      submit_review = function(review_payload)
        payload = review_payload
        return { state = "ok", review = { id = 2 } }
      end,
    })

    vim.g.git_review_submit_request_changes_result = result
    vim.g.git_review_submit_request_changes_payload = payload
  ]=])

  local result = child.lua_get([[vim.g.git_review_submit_request_changes_result]])
  local payload = child.lua_get([[vim.g.git_review_submit_request_changes_payload]])

  assert(type(result) == "table" and result.state == "ok", "Expected successful submit")
  assert(type(payload) == "table", "Expected submit payload table")
  assert(payload.event == "REQUEST_CHANGES", "Expected REQUEST_CHANGES event in payload")
  assert(payload.body == "", "Expected empty body to pass through")
end

set["session.submit_review returns context_error when PR context cannot be resolved"] = function()
  local session = require("git-review.session")

  local result = session.submit_review({
    event = "APPROVE",
  })

  assert(type(result) == "table", "Expected submit result table")
  assert(result.state == "context_error", "Expected context_error state")
end

set["session.submit_review rejects invalid event"] = function()
  local session = require("git-review.session")

  local result = session.submit_review({
    repo = "acme/repo",
    pr_number = 42,
    event = "COMMENT",
  })

  assert(type(result) == "table", "Expected submit result table")
  assert(result.state == "context_error", "Expected context_error state")
  assert(result.message == "event must be APPROVE or REQUEST_CHANGES", "Expected invalid event message")
end

set["session.submit_review returns context_error when event is missing"] = function()
  local session = require("git-review.session")

  local ok, result = pcall(session.submit_review, {})

  assert(ok, "Expected submit_review to return result instead of throwing")
  assert(type(result) == "table", "Expected submit result table")
  assert(result.state == "context_error", "Expected context_error state")
  assert(result.message == "event must be APPROVE or REQUEST_CHANGES", "Expected missing event message")
end

set["session.submit_review uses fallback PR resolution from current_session when pr_number absent"] = function()
  child.lua([=[
    local session = require("git-review.session")
    local resolve_pr_calls = 0
    local first_payload
    local second_payload

    session.start({
      diff_command = { "git", "diff", "--no-color", "origin/main...HEAD" },
      repo = "acme/repo",
      run_command = function(command)
        if type(command) == "table" and command[1] == "git" and command[2] == "diff" then
          return {
            code = 0,
            stdout = "",
            stderr = "",
          }
        end

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
          and command[3] == "HEAD"
        then
          return {
            code = 0,
            stdout = "abc123\n",
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
        return "feature/task-4"
      end,
      resolve_pr_for_branch = function(_, _)
        resolve_pr_calls = resolve_pr_calls + 1
        return {
          state = "single_pr",
          pr = {
            number = 77,
            baseRefName = "main",
          },
        }
      end,
      fetch_review_threads = function(_, _)
        return {
          state = "ok",
          threads = {},
        }
      end,
      panel = {
        render = function(_, _)
          return
        end,
      },
      hunk_highlight = {
        render_current_hunk = function(_)
          return
        end,
      },
      defer_thread_refresh = false,
    })

    local first_result = session.submit_review({
      event = "APPROVE",
      submit_review = function(payload)
        first_payload = payload
        return { state = "ok", review = { id = 3 } }
      end,
    })

    local second_result = session.submit_review({
      event = "REQUEST_CHANGES",
      submit_review = function(payload)
        second_payload = payload
        return { state = "ok", review = { id = 4 } }
      end,
    })

    vim.g.git_review_submit_fallback_first_result = first_result
    vim.g.git_review_submit_fallback_second_result = second_result
    vim.g.git_review_submit_fallback_first_payload = first_payload
    vim.g.git_review_submit_fallback_second_payload = second_payload
    vim.g.git_review_submit_fallback_resolve_pr_calls = resolve_pr_calls
  ]=])

  local first_result = child.lua_get([[vim.g.git_review_submit_fallback_first_result]])
  local second_result = child.lua_get([[vim.g.git_review_submit_fallback_second_result]])
  local first_payload = child.lua_get([[vim.g.git_review_submit_fallback_first_payload]])
  local second_payload = child.lua_get([[vim.g.git_review_submit_fallback_second_payload]])
  local resolve_pr_calls = child.lua_get([[vim.g.git_review_submit_fallback_resolve_pr_calls]])

  assert(type(first_result) == "table" and first_result.state == "ok", "Expected first submit to succeed")
  assert(type(second_result) == "table" and second_result.state == "ok", "Expected second submit to succeed")
  assert(type(first_payload) == "table", "Expected first payload table")
  assert(type(second_payload) == "table", "Expected second payload table")
  assert(first_payload.repo == "acme/repo", "Expected fallback to use current session repo")
  assert(first_payload.pr_number == 77, "Expected fallback to resolve PR number")
  assert(second_payload.pr_number == 77, "Expected cached PR number on second submit")
  assert(resolve_pr_calls == 1, "Expected fallback PR lookup to happen once")
end

set["session.submit_review propagates fallback PR resolution no_pr state and message"] = function()
  child.lua([=[
    local session = require("git-review.session")

    session.start({
      diff_command = { "git", "diff", "--no-color", "origin/main...HEAD" },
      repo = "acme/repo",
      run_command = function(command)
        if type(command) == "table" and command[1] == "git" and command[2] == "diff" then
          return {
            code = 0,
            stdout = "",
            stderr = "",
          }
        end

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
          and command[3] == "HEAD"
        then
          return {
            code = 0,
            stdout = "abc123\n",
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
        return "feature/task-4"
      end,
      resolve_pr_for_branch = function(_, _)
        return {
          state = "no_pr",
          message = "No pull request found for branch feature/task-4",
        }
      end,
      fetch_review_threads = function(_, _)
        return {
          state = "ok",
          threads = {},
        }
      end,
      panel = {
        render = function(_, _)
          return
        end,
      },
      hunk_highlight = {
        render_current_hunk = function(_)
          return
        end,
      },
      defer_thread_refresh = false,
    })

    vim.g.git_review_submit_fallback_no_pr_result = session.submit_review({
      event = "APPROVE",
    })
  ]=])

  local result = child.lua_get([[vim.g.git_review_submit_fallback_no_pr_result]])

  assert(type(result) == "table", "Expected submit result table")
  assert(result.state == "no_pr", "Expected no_pr state")
  assert(
    result.message == "No pull request found for branch feature/task-4",
    "Expected fallback PR resolution message to be propagated"
  )
end

set["session.submit_review is blocked in range mode"] = function()
  child.lua([=[
    local session = require("git-review.session")
    local calls = 0

    session.start_range({
      start_ref = "base/head",
      end_ref = "feature/head",
      run_command = function(command)
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

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "-C"
          and type(command[3]) == "string"
          and command[4] == "diff"
          and command[5] == "--no-color"
          and command[6] == "base/head...feature/head"
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
      parse_diff = function(_)
        return {}
      end,
      fetch_review_threads = function(_)
        return {
          state = "ok",
          threads = {},
        }
      end,
      panel = {
        render = function(_) end,
      },
      repo_root = vim.fs.normalize(vim.fn.getcwd()),
      repo = "acme/repo",
      commit_id = "head-commit",
      defer_thread_refresh = true,
    })

    local result = session.submit_review({
      event = "APPROVE",
      body = "Looks good",
      submit_review = function(_)
        calls = calls + 1
        return {
          state = "ok",
        }
      end,
    })

    vim.g.git_review_range_submit_review_result = result
    vim.g.git_review_range_submit_review_calls = calls
  ]=])

  local result = child.lua_get([[vim.g.git_review_range_submit_review_result]])
  local calls = child.lua_get([[vim.g.git_review_range_submit_review_calls]])

  assert(type(result) == "table", "Expected submit_review range-mode result table")
  assert(result.state == "unsupported_in_range_mode", "Expected range mode to block submit_review")
  assert(result.message == "submit_review is unsupported in range mode", "Expected deterministic range mode message")
  assert(calls == 0, "Expected blocked submit action to skip submit transport")
end

set["session.submit_review remains blocked in range mode after refresh"] = function()
  child.lua([=[
    local session = require("git-review.session")
    local calls = 0

    session.start_range({
      start_ref = "base/head",
      end_ref = "feature/head",
      run_command = function(command)
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

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "-C"
          and type(command[3]) == "string"
          and command[4] == "diff"
          and command[5] == "--no-color"
          and command[6] == "base/head...feature/head"
        then
          return {
            code = 0,
            stdout = "",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "HEAD"
        then
          return {
            code = 0,
            stdout = "feature/range\n",
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
        return "feature/range"
      end,
      resolve_pr_for_branch = function(_, _)
        return {
          state = "single_pr",
          pr = {
            number = 42,
            baseRefName = "main",
          },
        }
      end,
      parse_diff = function(_)
        return {}
      end,
      fetch_review_threads = function(_)
        return {
          state = "ok",
          threads = {},
        }
      end,
      panel = {
        render = function(_) end,
      },
      repo_root = vim.fs.normalize(vim.fn.getcwd()),
      repo = "acme/repo",
      commit_id = "head-commit",
      defer_thread_refresh = true,
    })

    session.refresh()

    local result = session.submit_review({
      event = "APPROVE",
      body = "Looks good",
      submit_review = function(_)
        calls = calls + 1
        return {
          state = "ok",
        }
      end,
    })

    vim.g.git_review_range_submit_review_refresh_result = result
    vim.g.git_review_range_submit_review_refresh_calls = calls
  ]=])

  local result = child.lua_get([[vim.g.git_review_range_submit_review_refresh_result]])
  local calls = child.lua_get([[vim.g.git_review_range_submit_review_refresh_calls]])

  assert(type(result) == "table", "Expected submit_review range-mode result table after refresh")
  assert(result.state == "unsupported_in_range_mode", "Expected range mode to block submit_review after refresh")
  assert(result.message == "submit_review is unsupported in range mode", "Expected deterministic range mode message")
  assert(calls == 0, "Expected blocked submit action to skip submit transport after refresh")
end

return set
