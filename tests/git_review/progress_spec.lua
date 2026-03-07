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

set["session progress commands return context_error without active session"] = function()
  child.lua([=[
    local session = require("git-review.session")

    vim.g.git_review_progress_mark_without_session = session.toggle_current_file_reviewed()
    vim.g.git_review_progress_next_without_session = session.goto_next_unreviewed_file()
    vim.g.git_review_progress_summary_without_session = session.review_progress()
  ]=])

  local mark_result = child.lua_get([[vim.g.git_review_progress_mark_without_session]])
  local next_result = child.lua_get([[vim.g.git_review_progress_next_without_session]])
  local progress_result = child.lua_get([[vim.g.git_review_progress_summary_without_session]])

  assert(type(mark_result) == "table" and mark_result.state == "context_error", "Expected mark-reviewed context_error without session")
  assert(type(next_result) == "table" and next_result.state == "context_error", "Expected next-unreviewed context_error without session")
  assert(type(progress_result) == "table" and progress_result.state == "context_error", "Expected progress context_error without session")
end

set["session toggles reviewed state for current file and updates progress"] = function()
  child.lua([=[
    local session = require("git-review.session")
    local repo_root = vim.fs.normalize(vim.fn.getcwd())
    local readme = vim.fs.normalize(repo_root .. "/README.md")
    local init_lua = vim.fs.normalize(repo_root .. "/lua/git-review/init.lua")

    vim.cmd("edit README.md")

    session.start({
      run_command = function(_)
        return {
          code = 0,
          stdout = "diff ignored by parse_diff",
          stderr = "",
        }
      end,
      parse_diff = function(_)
        return {
          { filename = readme, lnum = 1, end_lnum = 2, text = "README hunk" },
          { filename = init_lua, lnum = 10, end_lnum = 12, text = "init hunk" },
        }
      end,
      panel = {
        render = function(_) end,
      },
      fetch_review_threads = function(_)
        return { state = "ok", threads = {} }
      end,
      diff_command = "git diff --no-color HEAD~1...HEAD",
      repo_root = repo_root,
      repo = "acme/repo",
      commit_id = "head-commit",
      defer_thread_refresh = true,
    })

    local first_toggle = session.toggle_current_file_reviewed()
    local first_progress = session.review_progress()
    local second_toggle = session.toggle_current_file_reviewed()
    local second_progress = session.review_progress()

    vim.g.git_review_progress_first_toggle = first_toggle
    vim.g.git_review_progress_first_summary = first_progress
    vim.g.git_review_progress_second_toggle = second_toggle
    vim.g.git_review_progress_second_summary = second_progress
  ]=])

  local first_toggle = child.lua_get([[vim.g.git_review_progress_first_toggle]])
  local first_summary = child.lua_get([[vim.g.git_review_progress_first_summary]])
  local second_toggle = child.lua_get([[vim.g.git_review_progress_second_toggle]])
  local second_summary = child.lua_get([[vim.g.git_review_progress_second_summary]])

  assert(type(first_toggle) == "table" and first_toggle.state == "ok", "Expected first mark toggle success")
  assert(first_toggle.reviewed == true, "Expected first toggle to mark file reviewed")
  assert(type(first_summary) == "table" and first_summary.reviewed == 1 and first_summary.total == 2 and first_summary.remaining == 1,
    "Expected first progress summary after marking reviewed")

  assert(type(second_toggle) == "table" and second_toggle.state == "ok", "Expected second mark toggle success")
  assert(second_toggle.reviewed == false, "Expected second toggle to unmark file")
  assert(type(second_summary) == "table" and second_summary.reviewed == 0 and second_summary.total == 2 and second_summary.remaining == 2,
    "Expected second progress summary after unmarking")
end

set["session next-unreviewed advances until done without wrap"] = function()
  child.lua([=[
    local session = require("git-review.session")
    local repo_root = vim.fs.normalize(vim.fn.getcwd())
    local readme = vim.fs.normalize(repo_root .. "/README.md")
    local init_lua = vim.fs.normalize(repo_root .. "/lua/git-review/init.lua")

    vim.cmd("edit README.md")

    session.start({
      run_command = function(_)
        return {
          code = 0,
          stdout = "diff ignored by parse_diff",
          stderr = "",
        }
      end,
      parse_diff = function(_)
        return {
          { filename = readme, lnum = 1, end_lnum = 2, text = "README hunk" },
          { filename = init_lua, lnum = 10, end_lnum = 12, text = "init hunk" },
        }
      end,
      panel = {
        render = function(_) end,
      },
      fetch_review_threads = function(_)
        return { state = "ok", threads = {} }
      end,
      diff_command = "git diff --no-color HEAD~1...HEAD",
      repo_root = repo_root,
      repo = "acme/repo",
      commit_id = "head-commit",
      defer_thread_refresh = true,
    })

    local mark_first = session.toggle_current_file_reviewed()
    local next_result = session.goto_next_unreviewed_file()
    local mark_second = session.toggle_current_file_reviewed()
    local done_result = session.goto_next_unreviewed_file()

    vim.g.git_review_progress_next_mark_first = mark_first
    vim.g.git_review_progress_next_result = next_result
    vim.g.git_review_progress_next_mark_second = mark_second
    vim.g.git_review_progress_done_result = done_result
    vim.g.git_review_progress_current_buffer = vim.api.nvim_buf_get_name(0)
  ]=])

  local mark_first = child.lua_get([[vim.g.git_review_progress_next_mark_first]])
  local next_result = child.lua_get([[vim.g.git_review_progress_next_result]])
  local mark_second = child.lua_get([[vim.g.git_review_progress_next_mark_second]])
  local done_result = child.lua_get([[vim.g.git_review_progress_done_result]])
  local current_buffer = child.lua_get([[vim.g.git_review_progress_current_buffer]])

  assert(type(mark_first) == "table" and mark_first.state == "ok" and mark_first.reviewed == true,
    "Expected first file mark to succeed")
  assert(type(next_result) == "table" and next_result.state == "ok" and next_result.done == false,
    "Expected next-unreviewed to advance to next file")
  assert(type(current_buffer) == "string" and string.find(current_buffer, "lua/git-review/init.lua", 1, true),
    "Expected next-unreviewed to navigate to second file")
  assert(type(mark_second) == "table" and mark_second.state == "ok" and mark_second.reviewed == true,
    "Expected second file mark to succeed")
  assert(type(done_result) == "table" and done_result.state == "ok" and done_result.done == true,
    "Expected next-unreviewed to report done when all files are reviewed")
end

set["session mark-reviewed syncs viewed/unviewed when enabled"] = function()
  child.lua([=[
    local session = require("git-review.session")
    local repo_root = vim.fs.normalize(vim.fn.getcwd())
    local readme = vim.fs.normalize(repo_root .. "/README.md")

    require("git-review.config").setup({
      progress = {
        github_sync = true,
      },
    })

    local mark_calls = 0
    local unmark_calls = 0

    vim.cmd("edit README.md")

    session.start({
      run_command = function(_)
        return {
          code = 0,
          stdout = "diff ignored by parse_diff",
          stderr = "",
        }
      end,
      parse_diff = function(_)
        return {
          { filename = readme, lnum = 1, end_lnum = 2, text = "README hunk" },
        }
      end,
      resolve_branch = function(_)
        return "feature/progress-sync"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = {
            number = 42,
            id = "PR_kwDOAA",
            baseRefName = "main",
          },
        }
      end,
      panel = {
        render = function(_) end,
      },
      fetch_review_threads = function(_)
        return { state = "ok", threads = {} }
      end,
      diff_command = "git diff --no-color HEAD~1...HEAD",
      repo_root = repo_root,
      repo = "acme/repo",
      commit_id = "head-commit",
      defer_thread_refresh = true,
    })

    local first_toggle = session.toggle_current_file_reviewed({
      mark_file_viewed = function(pr_id, path)
        mark_calls = mark_calls + 1
        vim.g.git_review_progress_sync_mark_pr_id = pr_id
        vim.g.git_review_progress_sync_mark_path = path
        return { state = "ok" }
      end,
      unmark_file_viewed = function(_, _)
        unmark_calls = unmark_calls + 1
        return { state = "ok" }
      end,
    })

    local second_toggle = session.toggle_current_file_reviewed({
      mark_file_viewed = function(_, _)
        mark_calls = mark_calls + 1
        return { state = "ok" }
      end,
      unmark_file_viewed = function(pr_id, path)
        unmark_calls = unmark_calls + 1
        vim.g.git_review_progress_sync_unmark_pr_id = pr_id
        vim.g.git_review_progress_sync_unmark_path = path
        return { state = "ok" }
      end,
    })

    vim.g.git_review_progress_sync_first_toggle = first_toggle
    vim.g.git_review_progress_sync_second_toggle = second_toggle
    vim.g.git_review_progress_sync_mark_calls = mark_calls
    vim.g.git_review_progress_sync_unmark_calls = unmark_calls
  ]=])

  local first_toggle = child.lua_get([[vim.g.git_review_progress_sync_first_toggle]])
  local second_toggle = child.lua_get([[vim.g.git_review_progress_sync_second_toggle]])
  local mark_calls = child.lua_get([[vim.g.git_review_progress_sync_mark_calls]])
  local unmark_calls = child.lua_get([[vim.g.git_review_progress_sync_unmark_calls]])
  local mark_pr_id = child.lua_get([[vim.g.git_review_progress_sync_mark_pr_id]])
  local unmark_pr_id = child.lua_get([[vim.g.git_review_progress_sync_unmark_pr_id]])

  assert(type(first_toggle) == "table" and first_toggle.state == "ok", "Expected first synced toggle success")
  assert(type(second_toggle) == "table" and second_toggle.state == "ok", "Expected second synced toggle success")
  assert(mark_calls == 1, "Expected mark sync transport once")
  assert(unmark_calls == 1, "Expected unmark sync transport once")
  assert(mark_pr_id == "PR_kwDOAA", "Expected mark sync to use pull request node id")
  assert(unmark_pr_id == "PR_kwDOAA", "Expected unmark sync to use pull request node id")
end

set["session mark-reviewed updates review quickfix marker prefix"] = function()
  child.lua([=[
    local session = require("git-review.session")
    local repo_root = vim.fs.normalize(vim.fn.getcwd())
    local readme = vim.fs.normalize(repo_root .. "/README.md")

    vim.cmd("edit README.md")

    session.start({
      run_command = function(_)
        return {
          code = 0,
          stdout = "diff ignored by parse_diff",
          stderr = "",
        }
      end,
      parse_diff = function(_)
        return {
          { filename = readme, lnum = 1, end_lnum = 2, text = "README hunk" },
        }
      end,
      panel = {
        render = function(_) end,
      },
      fetch_review_threads = function(_)
        return { state = "ok", threads = {} }
      end,
      diff_command = "git diff --no-color HEAD~1...HEAD",
      repo_root = repo_root,
      repo = "acme/repo",
      commit_id = "head-commit",
      defer_thread_refresh = true,
    })

    session.populate_files_quickfix()
    local before_items = vim.fn.getqflist()

    session.toggle_current_file_reviewed()
    local after_items = vim.fn.getqflist()

    vim.g.git_review_progress_qf_before = before_items
    vim.g.git_review_progress_qf_after = after_items
  ]=])

  local before_items = child.lua_get([[vim.g.git_review_progress_qf_before]])
  local after_items = child.lua_get([[vim.g.git_review_progress_qf_after]])

  assert(type(before_items) == "table" and #before_items == 1, "Expected one review quickfix entry")
  assert(type(after_items) == "table" and #after_items == 1, "Expected one review quickfix entry after toggle")
  assert(string.find(before_items[1].text or "", "^%[ %]"), "Expected unreviewed quickfix prefix before toggle")
  assert(string.find(after_items[1].text or "", "^%[x%]"), "Expected reviewed quickfix prefix after toggle")
end

set["session refresh preserves reviewed state for surviving files"] = function()
  child.lua([=[
    local session = require("git-review.session")
    local repo_root = vim.fs.normalize(vim.fn.getcwd())
    local readme = vim.fs.normalize(repo_root .. "/README.md")
    local init_lua = vim.fs.normalize(repo_root .. "/lua/git-review/init.lua")

    vim.cmd("edit README.md")

    local parse_pass = 1
    local function parse_diff(_)
      if parse_pass == 1 then
        return {
          { filename = readme, lnum = 1, end_lnum = 2, text = "README hunk" },
          { filename = init_lua, lnum = 10, end_lnum = 12, text = "init hunk" },
        }
      end

      return {
        { filename = readme, lnum = 1, end_lnum = 2, text = "README hunk" },
      }
    end

    session.start({
      run_command = function(_)
        return {
          code = 0,
          stdout = "diff ignored by parse_diff",
          stderr = "",
        }
      end,
      parse_diff = parse_diff,
      resolve_branch = function(_)
        return "feature/progress-refresh"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = {
            number = 42,
            id = "PR_kwDOAA",
            baseRefName = "main",
          },
        }
      end,
      panel = {
        render = function(_) end,
      },
      fetch_review_threads = function(_)
        return { state = "ok", threads = {} }
      end,
      diff_command = "git diff --no-color HEAD~1...HEAD",
      repo_root = repo_root,
      repo = "acme/repo",
      commit_id = "head-commit",
      defer_thread_refresh = false,
    })

    session.toggle_current_file_reviewed()
    parse_pass = 2
    local refresh_result = session.refresh()
    local progress_result = session.review_progress()

    vim.g.git_review_progress_refresh_result = refresh_result
    vim.g.git_review_progress_refresh_summary = progress_result
  ]=])

  local refresh_result = child.lua_get([[vim.g.git_review_progress_refresh_result]])
  local progress_result = child.lua_get([[vim.g.git_review_progress_refresh_summary]])

  assert(type(refresh_result) == "table" and refresh_result.state == "ok", "Expected refresh success")
  assert(type(progress_result) == "table" and progress_result.reviewed == 1 and progress_result.total == 1,
    "Expected refresh to preserve reviewed state only for surviving files")
end

set["session mark-reviewed skips sync in range mode even when enabled"] = function()
  child.lua([=[
    local session = require("git-review.session")

    require("git-review.config").setup({
      progress = {
        github_sync = true,
      },
    })

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
        return {
          {
            filename = vim.fs.normalize(vim.fn.getcwd() .. "/README.md"),
            lnum = 1,
            end_lnum = 2,
            text = "README hunk",
          },
        }
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

    vim.cmd("edit README.md")
    local result = session.toggle_current_file_reviewed({
      mark_file_viewed = function(_, _)
        calls = calls + 1
        return { state = "ok" }
      end,
      unmark_file_viewed = function(_, _)
        calls = calls + 1
        return { state = "ok" }
      end,
    })

    vim.g.git_review_progress_range_sync_result = result
    vim.g.git_review_progress_range_sync_calls = calls
  ]=])

  local result = child.lua_get([[vim.g.git_review_progress_range_sync_result]])
  local calls = child.lua_get([[vim.g.git_review_progress_range_sync_calls]])

  assert(type(result) == "table" and result.state == "ok", "Expected range mark-reviewed success")
  assert(calls == 0, "Expected range mode to skip GitHub viewed sync")
end

return set
