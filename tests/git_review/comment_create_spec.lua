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

set["github.create_review_comment assembles line comment request"] = function()
  local github = require("git-review.github")
  local captured_request

  local result = github.create_review_comment({
    repo = "acme/repo",
    pr_number = 42,
    body = "Looks good",
    commit_id = "abc123",
    path = "lua/git-review/init.lua",
    position = 7,
  }, function(request)
    captured_request = request
    return {
      code = 0,
      stdout = [[{"id":99}]],
      stderr = "",
    }
  end)

  assert(type(captured_request) == "table", "Expected request table")
  assert(captured_request.method == "POST", "Expected POST request")
  assert(captured_request.path == "repos/acme/repo/pulls/42/comments", "Expected review comments API path")
  assert(type(captured_request.body) == "table", "Expected request body")
  assert(captured_request.body.position == 7, "Expected line position in payload")
  assert(captured_request.body.start_position == nil, "Expected no start_position for line comments")
  assert(result.state == "ok", "Expected ok state")
end

set["github.create_review_comment assembles range comment request"] = function()
  local github = require("git-review.github")
  local captured_request

  local result = github.create_review_comment({
    repo = "acme/repo",
    pr_number = 42,
    body = "Needs follow-up",
    commit_id = "abc123",
    path = "lua/git-review/init.lua",
    position = 8,
    start_position = 5,
  }, function(request)
    captured_request = request
    return {
      code = 0,
      stdout = [[{"id":100}]],
      stderr = "",
    }
  end)

  assert(type(captured_request) == "table", "Expected request table")
  assert(captured_request.body.position == 8, "Expected range end position")
  assert(captured_request.body.start_position == 5, "Expected range start position")
  assert(result.state == "ok", "Expected ok state")
end

set["session.create_comment maps cursor line and creates comment"] = function()
  child.lua([=[
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

    local calls = 0
    local payload
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, vim.fn.getcwd() .. "/lua/git-review/init.lua")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
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
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, { 11, 0 })

    local result = session.create_comment({
      body = "line-level note",
      diff_text = diff,
      repo = "acme/repo",
      pr_number = 42,
      commit_id = "abc123",
      create_review_comment = function(comment)
        calls = calls + 1
        payload = comment
        return {
          state = "ok",
          comment = { id = 200 },
        }
      end,
    })

    vim.g.git_review_comment_result_state = result.state
    vim.g.git_review_comment_calls = calls
    vim.g.git_review_comment_payload = payload
  ]=])

  local result_state = child.lua_get([[vim.g.git_review_comment_result_state]])
  local calls = child.lua_get([[vim.g.git_review_comment_calls]])
  local payload = child.lua_get([[vim.g.git_review_comment_payload]])

  assert(result_state == "ok", "Expected successful comment creation")
  assert(calls == 1, "Expected one create_review_comment call")
  assert(type(payload) == "table", "Expected comment payload table")
  assert(payload.path == "lua/git-review/init.lua", "Expected repo-relative path")
  assert(payload.position == 2, "Expected mapped line position")
  assert(payload.start_position == nil, "Expected line comment payload")
end

set["session.create_comment maps provided range context"] = function()
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

  local payload
  local result = session.create_comment({
    body = "range note",
    diff_text = diff,
    repo = "acme/repo",
    pr_number = 42,
    commit_id = "abc123",
    context = {
      path = "lua/git-review/init.lua",
      start_line = 10,
      end_line = 12,
    },
    create_review_comment = function(comment)
      payload = comment
      return {
        state = "ok",
      }
    end,
  })

  assert(result.state == "ok", "Expected successful range comment creation")
  assert(type(payload) == "table", "Expected mapped payload")
  assert(payload.position == 3, "Expected mapped range end position")
  assert(payload.start_position == 1, "Expected mapped range start position")
end

set["session.create_comment preserves buffer path inference errors for context tables"] = function()
  child.lua([=[
    local session = require("git-review.session")
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(bufnr)

    local result = session.create_comment({
      body = "line-level note",
      diff_text = "diff --git a/a b/a",
      repo = "acme/repo",
      pr_number = 42,
      commit_id = "abc123",
      context = {
        start_line = 1,
      },
    })

    vim.g.git_review_context_path_error_result = result
  ]=])

  local result = child.lua_get([[vim.g.git_review_context_path_error_result]])

  assert(type(result) == "table", "Expected create_comment result table")
  assert(result.state == "context_error", "Expected context_error state")
  assert(result.message == "Current buffer has no file path", "Expected specific path inference failure")
end

set["session.create_comment maps file path relative to session repo root when cwd is nested"] = function()
  child.lua([=[
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

    local calls = 0
    local payload
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, "/tmp/git-review-repo/lua/git-review/init.lua")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
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
    vim.api.nvim_set_current_buf(buf)
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
        return nil
      end,
    })

    local result = session.create_comment({
      body = "line-level note",
      repo = "acme/repo",
      pr_number = 42,
      commit_id = "abc123",
      cwd = "/tmp/git-review-repo/lua/git-review",
      create_review_comment = function(comment)
        calls = calls + 1
        payload = comment
        return {
          state = "ok",
          comment = { id = 201 },
        }
      end,
    })

    vim.g.git_review_nested_cwd_result_state = result.state
    vim.g.git_review_nested_cwd_calls = calls
    vim.g.git_review_nested_cwd_payload = payload
  ]=])

  local result_state = child.lua_get([[vim.g.git_review_nested_cwd_result_state]])
  local calls = child.lua_get([[vim.g.git_review_nested_cwd_calls]])
  local payload = child.lua_get([[vim.g.git_review_nested_cwd_payload]])

  assert(result_state == "ok", "Expected successful comment creation")
  assert(calls == 1, "Expected one create_review_comment call")
  assert(type(payload) == "table", "Expected comment payload table")
  assert(payload.path == "lua/git-review/init.lua", "Expected repo-root-relative path")
  assert(payload.position == 2, "Expected mapped line position")
end

set["session.create_comment is blocked in range mode"] = function()
  child.lua([=[
    local session = require("git-review.session")

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

    vim.g.git_review_range_create_comment_result = session.create_comment({
      body = "range mode blocked",
      context = {
        path = "README.md",
        start_line = 1,
        end_line = 1,
      },
      diff_text = "diff --git a/README.md b/README.md",
      repo = "acme/repo",
      pr_number = 42,
      commit_id = "abc123",
      create_review_comment = function(_)
        return {
          state = "ok",
        }
      end,
    })
  ]=])

  local result = child.lua_get([[vim.g.git_review_range_create_comment_result]])

  assert(type(result) == "table", "Expected create_comment range-mode result table")
  assert(result.state == "unsupported_in_range_mode", "Expected range mode to block create_comment")
  assert(result.message == "create_comment is unsupported in range mode", "Expected deterministic range mode message")
end

set["session.create_comment is blocked in local mode"] = function()
  child.lua([=[
    local session = require("git-review.session")

    session.start_local({
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
          and command[2] == "config"
          and command[3] == "--get"
          and command[4] == "remote.origin.url"
        then
          return {
            code = 1,
            stdout = "",
            stderr = "no remote",
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
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "HEAD"
        then
          return {
            code = 0,
            stdout = "",
            stderr = "",
          }
        end

        return {
          code = 0,
          stdout = "",
          stderr = "",
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
      defer_thread_refresh = true,
    })

    vim.g.git_review_local_create_comment_result = session.create_comment({
      body = "local mode blocked",
      context = {
        path = "README.md",
        start_line = 1,
        end_line = 1,
      },
      diff_text = "diff --git a/README.md b/README.md",
      repo = "acme/repo",
      pr_number = 42,
      commit_id = "abc123",
      create_review_comment = function(_)
        return {
          state = "ok",
        }
      end,
    })
  ]=])

  local result = child.lua_get([[vim.g.git_review_local_create_comment_result]])

  assert(type(result) == "table", "Expected create_comment local-mode result table")
  assert(result.state == "unsupported_in_range_mode", "Expected local mode to block create_comment")
  assert(result.message == "create_comment is unsupported in local mode", "Expected deterministic local mode message")
end

set["session.create_comment remains blocked in range mode after refresh"] = function()
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

    vim.g.git_review_range_create_comment_refresh_result = session.create_comment({
      body = "range mode blocked",
      context = {
        path = "README.md",
        start_line = 1,
        end_line = 1,
      },
      diff_text = "diff --git a/README.md b/README.md",
      repo = "acme/repo",
      pr_number = 42,
      commit_id = "abc123",
      create_review_comment = function(_)
        calls = calls + 1
        return {
          state = "ok",
        }
      end,
    })
    vim.g.git_review_range_create_comment_refresh_calls = calls
  ]=])

  local result = child.lua_get([[vim.g.git_review_range_create_comment_refresh_result]])
  local calls = child.lua_get([[vim.g.git_review_range_create_comment_refresh_calls]])

  assert(type(result) == "table", "Expected create_comment range-mode result table after refresh")
  assert(result.state == "unsupported_in_range_mode", "Expected range mode to block create_comment after refresh")
  assert(result.message == "create_comment is unsupported in range mode", "Expected deterministic range mode message")
  assert(calls == 0, "Expected blocked comment action to skip transport after refresh")
end

return set
