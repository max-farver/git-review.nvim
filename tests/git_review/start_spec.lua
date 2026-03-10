local T = require("mini.test")

local child = T.new_child_neovim()

local set = T.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "tests/minimal_init.lua" })
      child.lua([[
        vim.g.git_review_original_ui_select = vim.ui.select

        _G.git_review_test_auto_select = function(items, _, on_choice)
          if type(on_choice) ~= "function" then
            return
          end

          local function same_path(left, right)
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

          local current_buffer_path = vim.api.nvim_buf_get_name(0)
          if type(current_buffer_path) ~= "string" then
            current_buffer_path = ""
          end

          if type(items) == "table" then
            for idx, item in ipairs(items) do
              if type(item) == "table" and type(item.filename) == "string" and item.filename ~= "" then
                if same_path(item.filename, current_buffer_path) then
                  on_choice(item, idx)
                  return
                end
              end
            end
          end

          local first_item = type(items) == "table" and items[1] or nil
          on_choice(first_item, first_item and 1 or nil)
        end
      ]])
    end,
    post_once = function()
      child.stop()
    end,
  },
})

set["session.start returns hunks without mutating quickfix on picker selection"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local x = 1
@@ -10,2 +11,3 @@
 return M
+local y = 2
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+x
 ]]

    vim.fn.setqflist({}, " ", {
      title = "Before Quickfix",
      items = {
        {
          filename = vim.fs.normalize(vim.fn.getcwd() .. "/README.md"),
          lnum = 7,
          text = "keep-quickfix",
        },
      },
    })

    vim.g.git_review_start_state = session.start({
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

        return {
          code = 0,
          stdout = diff,
          stderr = "",
        }
      end,
      diff_command = "git diff --no-color HEAD~1...HEAD",
    })
  ]=])

  local state = child.lua_get([[vim.g.git_review_start_state]])

  assert(type(state) == "table", "Expected state table")
  assert(type(state.hunks) == "table", "Expected state.hunks list")
  assert(#state.hunks == 3, "Expected all parsed hunks to be returned")

  local qf = child.lua_get([[vim.fn.getqflist()]])
  local qf_title = child.lua_get([[vim.fn.getqflist({ title = 1 }).title]])
  assert(type(qf) == "table" and #qf == 1, "Expected quickfix items to remain unchanged")
  assert(qf_title == "Before Quickfix", "Expected quickfix title to remain unchanged")
  assert(qf[1].lnum == 7, "Expected existing quickfix entry to remain unchanged")
end

set["session.start opens selected file from picker"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")

    vim.ui.select = function(items, opts, on_choice)
      _G.git_review_picker_items = items
      return _G.git_review_test_auto_select(items, opts, function(choice, idx)
        _G.git_review_picker_selected = choice
        if type(on_choice) == "function" then
          on_choice(choice, idx)
        end
      end)
    end

    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -10,2 +10,3 @@
 return M
+local x = 1
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+x
]]

    vim.cmd("edit tests/minimal_init.lua")

    session.start({
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

        return {
          code = 0,
          stdout = diff,
          stderr = "",
        }
      end,
      diff_command = "git diff --no-color HEAD~1...HEAD",
    })

    local selected = _G.git_review_picker_selected
    local current_buf = vim.api.nvim_buf_get_name(0)
    local cursor = vim.api.nvim_win_get_cursor(0)

    vim.g.git_review_picker_selected_filename = type(selected) == "table" and selected.filename or nil
    vim.g.git_review_picker_current_buffer = current_buf
    vim.g.git_review_picker_cursor_line = type(cursor) == "table" and cursor[1] or nil
  ]=])

  local selected_filename = child.lua_get([[vim.g.git_review_picker_selected_filename]])
  local current_buffer = child.lua_get([[vim.g.git_review_picker_current_buffer]])
  local cursor_line = child.lua_get([[vim.g.git_review_picker_cursor_line]])

  assert(type(selected_filename) == "string" and selected_filename ~= "", "Expected picker to select a file")
  assert(current_buffer == selected_filename, "Expected picker selection to open the selected file")
  assert(cursor_line == 10, "Expected cursor to move to first hunk line")
end

set["session.start_range validates refs before worktree creation"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = nil

    local commands = {}
    local range_result = session.start_range({
      start_ref = "base/head",
      end_ref = "feature/head",
      run_command = function(command)
        table.insert(commands, command)

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
          and command[4] == "base/head^{commit}"
        then
          return {
            code = 0,
            stdout = "base-commit\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--verify"
          and command[4] == "feature/head^{commit}"
        then
          return {
            code = 1,
            stdout = "",
            stderr = "unknown revision",
          }
        end

        if type(command) == "table" and command[1] == "git" and command[2] == "worktree" and command[3] == "add" then
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
      defer_thread_refresh = true,
    })

    vim.g.git_review_start_range_ref_validation_result = range_result
    vim.g.git_review_start_range_ref_validation_commands = commands
  ]=])

  local result = child.lua_get([[vim.g.git_review_start_range_ref_validation_result]])
  local commands = child.lua_get([[vim.g.git_review_start_range_ref_validation_commands]])

  assert(type(result) == "table" and result.state == "command_error", "Expected invalid end ref to fail start_range")
  assert(
    type(result.message) == "string" and string.find(result.message, "feature/head", 1, true),
    "Expected invalid end ref error to include ref name"
  )
  assert(
    type(result.message) == "string"
      and string.find(result.message, "git rev-parse --verify feature/head^{commit}", 1, true),
    "Expected invalid end ref error to include actionable git rev-parse guidance"
  )

  local validated_start = false
  local validated_end = false
  local worktree_add_seen = false
  for _, command in ipairs(commands or {}) do
    if type(command) == "table" and command[1] == "git" and command[2] == "rev-parse" and command[3] == "--verify" then
      if command[4] == "base/head^{commit}" then
        validated_start = true
      elseif command[4] == "feature/head^{commit}" then
        validated_end = true
      end
    end

    if type(command) == "table" and command[1] == "git" and command[2] == "worktree" and command[3] == "add" then
      worktree_add_seen = true
    end
  end

  assert(validated_start == true, "Expected start ref validation before worktree creation")
  assert(validated_end == true, "Expected end ref validation before worktree creation")
  assert(worktree_add_seen == false, "Expected invalid refs to prevent worktree creation")
end

set["session.start_range cleans up owned worktree when start fails after creation"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = nil

    local commands = {}
    local worktree_add_path = nil
    local worktree_remove_path = nil

    local ok_start, start_result = pcall(session.start_range, {
      start_ref = "base/head",
      end_ref = "feature/head",
      run_command = function(command)
        table.insert(commands, command)

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
        then
          worktree_add_path = command[5]
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
        then
          return {
            code = 1,
            stdout = "",
            stderr = "diff failed",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "worktree"
          and command[3] == "remove"
          and command[4] == "--force"
        then
          worktree_remove_path = command[5]
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
      defer_thread_refresh = true,
    })

    vim.g.git_review_start_range_cleanup_ok = ok_start
    vim.g.git_review_start_range_cleanup_result = start_result
    vim.g.git_review_start_range_cleanup_commands = commands
    vim.g.git_review_start_range_cleanup_worktree_add_path = worktree_add_path
    vim.g.git_review_start_range_cleanup_worktree_remove_path = worktree_remove_path
  ]=])

  local ok_start = child.lua_get([[vim.g.git_review_start_range_cleanup_ok]])
  local result = child.lua_get([[vim.g.git_review_start_range_cleanup_result]])
  local commands = child.lua_get([[vim.g.git_review_start_range_cleanup_commands]])
  local add_path = child.lua_get([[vim.g.git_review_start_range_cleanup_worktree_add_path]])
  local remove_path = child.lua_get([[vim.g.git_review_start_range_cleanup_worktree_remove_path]])

  assert(ok_start == true, "Expected start_range failure path to return an error table")
  assert(type(result) == "table" and result.state == "command_error", "Expected start failure to return command_error")
  assert(type(result.message) == "string" and string.find(result.message, "diff failed", 1, true), "Expected start failure detail")
  assert(type(add_path) == "string" and add_path ~= "", "Expected detached worktree path from add command")
  assert(remove_path == add_path, "Expected start_range failure cleanup to remove the created worktree")

  local remove_seen = false
  for _, command in ipairs(commands or {}) do
    if type(command) == "table" and command[1] == "git" and command[2] == "worktree" and command[3] == "remove" then
      remove_seen = true
      break
    end
  end

  assert(remove_seen == true, "Expected start_range failure path to attempt worktree cleanup")
end

set["session.start_range creates detached worktree and runs diff there"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = nil

    local commands = {}
    local worktree_add_path = nil
    local diff_cwd = nil

    local range_result = session.start_range({
      start_ref = "base/head",
      end_ref = "feature/head",
      run_command = function(command)
        table.insert(commands, command)

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
        then
          worktree_add_path = command[5]
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
          diff_cwd = command[3]
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
      repo = "acme/repo",
      commit_id = "head-commit",
      defer_thread_refresh = true,
    })

    local active_session = nil
    for idx = 1, 40 do
      local upvalue_name, upvalue_value = debug.getupvalue(session.start, idx)
      if upvalue_name == nil then
        break
      end

      if upvalue_name == "current_session" then
        active_session = upvalue_value
        break
      end
    end

    vim.g.git_review_start_range_result = range_result
    vim.g.git_review_start_range_commands = commands
    vim.g.git_review_start_range_worktree_add_path = worktree_add_path
    vim.g.git_review_start_range_diff_cwd = diff_cwd
    vim.g.git_review_start_range_mode = type(active_session) == "table" and active_session.mode or nil
    vim.g.git_review_start_range_start = type(active_session) == "table" and active_session.range_start or nil
    vim.g.git_review_start_range_end = type(active_session) == "table" and active_session.range_end or nil
    vim.g.git_review_start_range_review_commit_id =
      type(active_session) == "table" and active_session.review_commit_id or nil
    vim.g.git_review_start_range_worktree_path = type(active_session) == "table" and active_session.worktree_path or nil
    vim.g.git_review_start_range_worktree_owned = type(active_session) == "table" and active_session.worktree_owned or nil
    vim.g.git_review_start_range_review_repo_root = type(active_session) == "table" and active_session.review_repo_root or nil
  ]=])

  local result = child.lua_get([[vim.g.git_review_start_range_result]])
  local commands = child.lua_get([[vim.g.git_review_start_range_commands]])
  local worktree_add_path = child.lua_get([[vim.g.git_review_start_range_worktree_add_path]])
  local diff_cwd = child.lua_get([[vim.g.git_review_start_range_diff_cwd]])
  local mode = child.lua_get([[vim.g.git_review_start_range_mode]])
  local range_start = child.lua_get([[vim.g.git_review_start_range_start]])
  local range_end = child.lua_get([[vim.g.git_review_start_range_end]])
  local review_commit_id = child.lua_get([[vim.g.git_review_start_range_review_commit_id]])
  local session_worktree_path = child.lua_get([[vim.g.git_review_start_range_worktree_path]])
  local session_worktree_owned = child.lua_get([[vim.g.git_review_start_range_worktree_owned]])
  local review_repo_root = child.lua_get([[vim.g.git_review_start_range_review_repo_root]])

  assert(type(result) == "table" and type(result.hunks) == "table", "Expected start_range to return start result")
  assert(mode == "range", "Expected active session mode to be range")
  assert(range_start == "base/head", "Expected active session range_start context")
  assert(range_end == "feature/head", "Expected active session range_end context")
  assert(review_commit_id == "feature/head", "Expected active session review_commit_id to match range end")

  local worktree_add_seen = false
  local detached_seen = false
  for _, command in ipairs(commands or {}) do
    if type(command) == "table" and command[1] == "git" and command[2] == "worktree" and command[3] == "add" then
      worktree_add_seen = true
      detached_seen = command[4] == "--detach"
      break
    end
  end

  assert(worktree_add_seen == true, "Expected start_range to call git worktree add")
  assert(detached_seen == true, "Expected start_range to create detached worktree")
  assert(type(worktree_add_path) == "string" and worktree_add_path ~= "", "Expected detached worktree path argument")
  assert(diff_cwd == worktree_add_path, "Expected git diff to run in detached worktree context")
  assert(session_worktree_path == worktree_add_path, "Expected session worktree_path to match created worktree")
  assert(session_worktree_owned == true, "Expected session to mark worktree ownership")
  assert(type(review_repo_root) == "string" and review_repo_root ~= "", "Expected session review_repo_root metadata")
end

set["session.start_range_picker selects range refs and delegates to start_range"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    local original_start_range = session.start_range

    local commands = {}
    session.start_range = function(opts)
      vim.g.git_review_range_picker_forwarded_start_ref = type(opts) == "table" and opts.start_ref or nil
      vim.g.git_review_range_picker_forwarded_end_ref = type(opts) == "table" and opts.end_ref or nil
      local command_opts = type(opts) == "table" and opts.command_opts or nil
      vim.g.git_review_range_picker_forwarded_line1 = type(command_opts) == "table" and command_opts.line1 or nil
      return {
        hunks = {},
      }
    end

    local picker_prompts = {}
    local picker_defaults = {}
    local picker_labels = {}
    vim.ui.select = function(items, select_opts, on_choice)
      table.insert(picker_prompts, select_opts.prompt)
      table.insert(picker_defaults, select_opts.default)

      local format_item = type(select_opts) == "table" and select_opts.format_item or nil
      if type(format_item) == "function" and type(items) == "table" and type(items[1]) == "table" then
        table.insert(picker_labels, format_item(items[1]))
      end

      if #picker_prompts == 1 then
        on_choice(items[1], 1)
      else
        on_choice(items[2], 2)
      end
    end

    local picker_result = session.start_range_picker({
      command_opts = {
        line1 = 3,
      },
      run_command = function(command)
        table.insert(commands, command)

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "log"
          and command[3] == "--format=%H%x09%s"
          and command[4] == "HEAD"
        then
          return {
            code = 0,
            stdout = "ccccccc3\tnewest\nbbbbbbb2\tmiddle\naaaaaaa1\toldest\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "log"
          and command[3] == "--format=%H%x09%s"
          and command[4] == "ccccccc3"
        then
          return {
            code = 0,
            stdout = "ccccccc3\tnewest\nbbbbbbb2\tmiddle\naaaaaaa1\toldest\n",
            stderr = "",
          }
        end

        return {
          code = 1,
          stdout = "",
          stderr = "unexpected command",
        }
      end,
    })

    session.start_range = original_start_range
    vim.g.git_review_range_picker_result = picker_result
    vim.g.git_review_range_picker_prompts = picker_prompts
    vim.g.git_review_range_picker_defaults = picker_defaults
    vim.g.git_review_range_picker_labels = picker_labels
    vim.g.git_review_range_picker_commands = commands
  ]=])

  local picker_result = child.lua_get([[vim.g.git_review_range_picker_result]])
  local forwarded_start_ref = child.lua_get([[vim.g.git_review_range_picker_forwarded_start_ref]])
  local forwarded_end_ref = child.lua_get([[vim.g.git_review_range_picker_forwarded_end_ref]])
  local forwarded_line1 = child.lua_get([[vim.g.git_review_range_picker_forwarded_line1]])
  local prompts = child.lua_get([[vim.g.git_review_range_picker_prompts]])
  local defaults = child.lua_get([[vim.g.git_review_range_picker_defaults]])
  local labels = child.lua_get([[vim.g.git_review_range_picker_labels]])
  local commands = child.lua_get([[vim.g.git_review_range_picker_commands]])

  assert(type(picker_result) == "table" and type(picker_result.hunks) == "table", "Expected picker to return delegated start_range result")
  assert(forwarded_start_ref == "bbbbbbb2", "Expected picker-selected start_ref to be forwarded")
  assert(forwarded_end_ref == "ccccccc3", "Expected picker-selected end_ref to be forwarded")
  assert(forwarded_line1 == 3, "Expected picker to preserve passthrough options")

  assert(type(prompts) == "table" and #prompts == 2, "Expected two-step commit picker flow")
  assert(type(defaults) == "table" and defaults[1] == 1, "Expected range_end picker default to HEAD")
  assert(type(defaults) == "table" and defaults[2] == 2, "Expected range_start picker default to parent of selected end")
  assert(type(labels) == "table" and string.find(labels[1], "ccccccc", 1, true), "Expected picker labels to include short SHA")
  assert(type(labels) == "table" and string.find(labels[1], "newest", 1, true), "Expected picker labels to include commit subject")

  assert(type(commands) == "table" and #commands == 2, "Expected picker to resolve commits twice (HEAD then selected end)")
  assert(commands[1][4] == "HEAD", "Expected first commit set to use HEAD ancestry")
  assert(commands[2][4] == "ccccccc3", "Expected second commit set limited to selected end ancestry")
end

set["session.start_range_picker supports delayed async selections"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    local original_start_range = session.start_range

    session.start_range = function(opts)
      vim.g.git_review_range_picker_async_start_ref = type(opts) == "table" and opts.start_ref or nil
      vim.g.git_review_range_picker_async_end_ref = type(opts) == "table" and opts.end_ref or nil
      return {
        hunks = {},
      }
    end

    local select_calls = 0
    vim.ui.select = function(items, _, on_choice)
      select_calls = select_calls + 1
      local call_index = select_calls
      vim.defer_fn(function()
        if call_index == 1 then
          on_choice(items[1], 1)
          return
        end

        on_choice(items[2], 2)
      end, 120)
    end

    local picker_result = session.start_range_picker({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "log"
          and command[3] == "--format=%H%x09%s"
          and command[4] == "HEAD"
        then
          return {
            code = 0,
            stdout = "ccccccc3\tnewest\nbbbbbbb2\tmiddle\naaaaaaa1\toldest\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "log"
          and command[3] == "--format=%H%x09%s"
          and command[4] == "ccccccc3"
        then
          return {
            code = 0,
            stdout = "ccccccc3\tnewest\nbbbbbbb2\tmiddle\naaaaaaa1\toldest\n",
            stderr = "",
          }
        end

        return {
          code = 1,
          stdout = "",
          stderr = "unexpected command",
        }
      end,
      on_complete = function(result)
        vim.g.git_review_range_picker_async_result = result
      end,
    })

    vim.wait(500, function()
      return vim.g.git_review_range_picker_async_result ~= nil
    end, 10)

    session.start_range = original_start_range
    vim.g.git_review_range_picker_async_initial_result = picker_result
  ]=])

  local initial_result = child.lua_get([[vim.g.git_review_range_picker_async_initial_result]])
  local async_result = child.lua_get([[vim.g.git_review_range_picker_async_result]])
  local forwarded_start_ref = child.lua_get([[vim.g.git_review_range_picker_async_start_ref]])
  local forwarded_end_ref = child.lua_get([[vim.g.git_review_range_picker_async_end_ref]])

  assert(type(initial_result) == "table" and initial_result.state == "pending", "Expected delayed picker to return pending")
  assert(type(async_result) == "table" and type(async_result.hunks) == "table", "Expected delayed picker completion to succeed")
  assert(forwarded_start_ref == "bbbbbbb2", "Expected delayed picker-selected start_ref to be forwarded")
  assert(forwarded_end_ref == "ccccccc3", "Expected delayed picker-selected end_ref to be forwarded")
end

set["session.start_range_picker exits cleanly when picker is cancelled"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    local original_start_range = session.start_range

    session.start_range = function(_)
      vim.g.git_review_range_picker_cancel_start_called = true
      return {
        hunks = {},
      }
    end

    vim.ui.select = function(_, _, on_choice)
      on_choice(nil, nil)
    end

    local picker_result = session.start_range_picker({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "log"
          and command[3] == "--format=%H%x09%s"
          and command[4] == "HEAD"
        then
          return {
            code = 0,
            stdout = "ccccccc3\tnewest\n",
            stderr = "",
          }
        end

        return {
          code = 1,
          stdout = "",
          stderr = "unexpected command",
        }
      end,
    })

    session.start_range = original_start_range
    vim.g.git_review_range_picker_cancel_result = picker_result
    vim.g.git_review_range_picker_cancel_active = session.is_active()
  ]=])

  local picker_result = child.lua_get([[vim.g.git_review_range_picker_cancel_result]])
  local start_called = child.lua_get([[vim.g.git_review_range_picker_cancel_start_called == true]])
  local is_active = child.lua_get([[vim.g.git_review_range_picker_cancel_active]])

  assert(type(picker_result) == "table", "Expected cancel path result table")
  assert(picker_result.state == "cancelled", "Expected cancel path to report cancelled state")
  assert(start_called == false, "Expected cancel path to avoid start_range invocation")
  assert(is_active == false, "Expected cancel path to keep session inactive")
end

set["session.start scheduled picker refresh does not target a newer session"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    local repo_root = vim.fs.normalize(vim.fn.getcwd())
    local abs_readme = vim.fs.normalize(repo_root .. "/README.md")
    local abs_init = vim.fs.normalize(repo_root .. "/lua/git-review/init.lua")

    local scheduled = {}
    local original_schedule = vim.schedule
    vim.schedule = function(fn)
      table.insert(scheduled, fn)
    end

    local function start_with_hunks(hunks, call_counter_name)
      session.start({
        run_command = function(_)
          return {
            code = 0,
            stdout = "diff ignored by parse_diff",
            stderr = "",
          }
        end,
        parse_diff = function(_)
          return hunks
        end,
        diff_command = "git diff --no-color HEAD~1...HEAD",
        fetch_review_threads = function(_)
          return {
            state = "ok",
            threads = {},
          }
        end,
        panel = {
          render = function(_) end,
        },
        hunk_highlight = {
          render_current_hunk = function(_)
            _G[call_counter_name] = (_G[call_counter_name] or 0) + 1
          end,
        },
        repo_root = repo_root,
      })
    end

    vim.ui.select = function(items, _, on_choice)
      on_choice(items[1], 1)
    end

    start_with_hunks({
      {
        filename = abs_readme,
        lnum = 5,
        end_lnum = 6,
        text = "first session",
      },
    }, "git_review_first_session_highlight_calls")

    start_with_hunks({
      {
        filename = abs_init,
        lnum = 7,
        end_lnum = 8,
        text = "second session one",
      },
      {
        filename = abs_init,
        lnum = 17,
        end_lnum = 18,
        text = "second session two",
      },
    }, "git_review_second_session_highlight_calls")

    local current = nil
    for idx = 1, 30 do
      local upvalue_name, upvalue_value = debug.getupvalue(session.start, idx)
      if upvalue_name == nil then
        break
      end

      if upvalue_name == "current_session" and type(upvalue_value) == "table" then
        current = upvalue_value
        break
      end
    end

    if type(current) == "table" then
      current.navigation_state = nil
    end

    local second_before = _G.git_review_second_session_highlight_calls or 0
    if type(scheduled[1]) == "function" then
      scheduled[1]()
    end
    local second_after = _G.git_review_second_session_highlight_calls or 0

    vim.schedule = original_schedule

    vim.g.git_review_scheduled_refresh_count = #scheduled
    vim.g.git_review_scheduled_refresh_second_before = second_before
    vim.g.git_review_scheduled_refresh_second_after = second_after
  ]=])

  local scheduled_count = child.lua_get([[vim.g.git_review_scheduled_refresh_count]])
  local second_before = child.lua_get([[vim.g.git_review_scheduled_refresh_second_before]])
  local second_after = child.lua_get([[vim.g.git_review_scheduled_refresh_second_after]])

  assert(type(scheduled_count) == "number" and scheduled_count >= 2, "Expected both starts to enqueue picker refresh callbacks")
  assert(second_after == second_before, "Expected stale scheduled refresh to no-op after a newer session starts")
end

set["session.start delayed picker callback no-ops after session is stopped"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    local repo_root = vim.fs.normalize(vim.fn.getcwd())
    local abs_readme = vim.fs.normalize(repo_root .. "/README.md")
    local delayed_items = nil
    local delayed_on_choice = nil

    vim.ui.select = function(items, _, on_choice)
      delayed_items = items
      delayed_on_choice = on_choice
    end

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
          {
            filename = abs_readme,
            lnum = 9,
            end_lnum = 10,
            text = "delayed picker callback",
          },
        }
      end,
      diff_command = "git diff --no-color HEAD~1...HEAD",
      fetch_review_threads = function(_)
        return {
          state = "ok",
          threads = {},
        }
      end,
      panel = {
        render = function(_) end,
      },
      repo_root = repo_root,
    })

    local stop_result = session.stop()
    local callback_ok, callback_err = pcall(function()
      if type(delayed_on_choice) == "function" then
        delayed_on_choice(delayed_items[1], 1)
      end
    end)

    vim.g.git_review_delayed_picker_stop_result = stop_result
    vim.g.git_review_delayed_picker_callback_ok = callback_ok
    vim.g.git_review_delayed_picker_callback_err = callback_err
    vim.g.git_review_delayed_picker_loclist_count = #vim.fn.getloclist(0)
  ]=])

  local stop_result = child.lua_get([[vim.g.git_review_delayed_picker_stop_result]])
  local callback_ok = child.lua_get([[vim.g.git_review_delayed_picker_callback_ok]])
  local callback_err = child.lua_get([[vim.g.git_review_delayed_picker_callback_err]])
  local loclist_count = child.lua_get([[vim.g.git_review_delayed_picker_loclist_count]])

  assert(type(stop_result) == "table" and stop_result.state == "ok", "Expected session.stop to succeed before delayed picker callback")
  assert(callback_ok == true, "Expected delayed stale picker callback to no-op instead of crashing: " .. tostring(callback_err))
  assert(loclist_count == 0, "Expected delayed stale picker callback to keep stopped-session loclist empty")
end

set["session.start picker selection uses startup-cached loclist and first hunk"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    local repo_root = vim.fs.normalize(vim.fn.getcwd())
    local abs_readme = vim.fs.normalize(repo_root .. "/README.md")
    local parsed_hunks = {
      {
        filename = abs_readme,
        lnum = 11,
        end_lnum = 12,
        deleted_blocks = {
          {
            anchor_lnum = 11,
            lines = { "old one", "old two" },
          },
        },
        text = "first readme hunk",
      },
      {
        filename = abs_readme,
        lnum = 31,
        end_lnum = 33,
        deleted_blocks = {
          {
            anchor_lnum = 31,
            lines = { "old three" },
          },
        },
        text = "second readme hunk",
      },
    }

    local mutated_cache = false

    vim.ui.select = function(items, _, on_choice)
      local selected = nil
      for _, item in ipairs(items) do
        if type(item) == "table" and type(item.filename) == "string" and string.find(item.filename, "README.md", 1, true) then
          selected = item
          break
        end
      end
      selected = selected or items[1]

      for idx = 1, 30 do
        local upvalue_name, upvalue_value = debug.getupvalue(session.start, idx)
        if upvalue_name == nil then
          break
        end

        if upvalue_name == "current_session" and type(upvalue_value) == "table" then
          local by_file = upvalue_value.hunks_by_file
          if type(by_file) == "table" and type(selected) == "table" and type(selected.filename) == "string" then
            local chosen_file = selected.filename
            for _, key in ipairs({ chosen_file, vim.fs.normalize(chosen_file), vim.loop.fs_realpath(chosen_file) }) do
              if type(key) == "string" and key ~= "" then
                by_file[key] = {
                  {
                    lnum = 777,
                    end_lnum = 778,
                  },
                }
              end
            end
            mutated_cache = true
          end
          break
        end
      end

      on_choice(selected, 1)
    end

    session.start({
      run_command = function(_)
        return {
          code = 0,
          stdout = "diff ignored by parse_diff",
          stderr = "",
        }
      end,
      parse_diff = function(_)
        return parsed_hunks
      end,
      diff_command = "git diff --no-color HEAD~1...HEAD",
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

    local session_cache_loclist_item = nil
    local session_cache_first_hunk = nil
    for idx = 1, 30 do
      local upvalue_name, upvalue_value = debug.getupvalue(session.start, idx)
      if upvalue_name == nil then
        break
      end

      if upvalue_name == "current_session" and type(upvalue_value) == "table" then
        local loclist_cache = upvalue_value.picker_file_loclist_cache
        local first_hunk_cache = upvalue_value.picker_file_first_hunk_cache

        if type(loclist_cache) == "table" then
          local cached_items = loclist_cache[abs_readme] or loclist_cache[vim.fs.normalize(abs_readme)]
          if type(cached_items) == "table" and type(cached_items[1]) == "table" then
            session_cache_loclist_item = cached_items[1]
          end
        end

        if type(first_hunk_cache) == "table" then
          session_cache_first_hunk = first_hunk_cache[abs_readme] or first_hunk_cache[vim.fs.normalize(abs_readme)]
        end

        break
      end
    end

    vim.g.git_review_startup_cache_mutated = mutated_cache
    vim.g.git_review_startup_cache_loclist_items = vim.fn.getloclist(0)
    vim.g.git_review_startup_cache_cursor_line = vim.api.nvim_win_get_cursor(0)[1]
    vim.g.git_review_startup_cache_loclist_item_metadata = session_cache_loclist_item
    vim.g.git_review_startup_cache_first_hunk_metadata = session_cache_first_hunk
  ]=])

  local mutated_cache = child.lua_get([[vim.g.git_review_startup_cache_mutated]])
  local loclist_items = child.lua_get([[vim.g.git_review_startup_cache_loclist_items]])
  local cursor_line = child.lua_get([[vim.g.git_review_startup_cache_cursor_line]])
  local cached_loclist_item = child.lua_get([[vim.g.git_review_startup_cache_loclist_item_metadata]])
  local cached_first_hunk = child.lua_get([[vim.g.git_review_startup_cache_first_hunk_metadata]])

  assert(mutated_cache == true, "Expected test to mutate live session cache before picker choice")
  assert(type(loclist_items) == "table" and #loclist_items == 2, "Expected startup-cached loclist hunks for selected file")
  assert(loclist_items[1].lnum == 11, "Expected selected loclist to use startup-cached first hunk")
  assert(type(cached_loclist_item) == "table", "Expected startup loclist cache metadata for selected file")
  assert(type(cached_loclist_item.deleted_blocks) == "table", "Expected startup loclist cache to preserve deleted_blocks metadata")
  assert(#cached_loclist_item.deleted_blocks == 1, "Expected startup loclist cache to preserve deleted block count")
  assert(cached_loclist_item.deleted_blocks[1].anchor_lnum == 11, "Expected startup loclist cache deleted block anchor")
  assert(cached_loclist_item.deleted_blocks[1].lines[1] == "old one", "Expected startup loclist cache deleted block payload")
  assert(type(cached_first_hunk) == "table", "Expected startup first-hunk cache metadata for selected file")
  assert(type(cached_first_hunk.deleted_blocks) == "table", "Expected startup first-hunk cache to preserve deleted_blocks metadata")
  assert(cached_first_hunk.deleted_blocks[1].anchor_lnum == 11, "Expected startup first-hunk cache deleted block anchor")
  assert(cursor_line == 11, "Expected cursor to use startup-cached first hunk")
end

set["session.start startup cache outputs stay stable and equivalent"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    local repo_root = vim.fs.normalize(vim.fn.getcwd())
    local abs_readme = vim.fs.normalize(repo_root .. "/README.md")
    local parsed_hunks = {
      {
        filename = abs_readme,
        lnum = 9,
        end_lnum = 10,
        text = "first stable hunk",
      },
      {
        filename = abs_readme,
        lnum = 19,
        end_lnum = 21,
        text = "second stable hunk",
      },
    }

    local function run_start(mutate_before_choice)
      vim.fn.setloclist(0, {}, "r")

      local did_mutate = false
      vim.ui.select = function(items, _, on_choice)
        local selected = items[1]

        if mutate_before_choice then
          for idx = 1, 30 do
            local upvalue_name, upvalue_value = debug.getupvalue(session.start, idx)
            if upvalue_name == nil then
              break
            end

            if upvalue_name == "current_session" and type(upvalue_value) == "table" then
              local by_file = upvalue_value.hunks_by_file
              if type(by_file) == "table" and type(selected) == "table" and type(selected.filename) == "string" then
                local chosen_file = selected.filename
                for _, key in ipairs({ chosen_file, vim.fs.normalize(chosen_file), vim.loop.fs_realpath(chosen_file) }) do
                  if type(key) == "string" and key ~= "" then
                    by_file[key] = {
                      {
                        lnum = 909,
                        end_lnum = 910,
                      },
                    }
                  end
                end
                did_mutate = true
              end
              break
            end
          end
        end

        on_choice(selected, 1)
      end

      session.start({
        run_command = function(_)
          return {
            code = 0,
            stdout = "diff ignored by parse_diff",
            stderr = "",
          }
        end,
        parse_diff = function(_)
          return parsed_hunks
        end,
        diff_command = "git diff --no-color HEAD~1...HEAD",
        fetch_review_threads = function(_)
          return {
            state = "ok",
            threads = {},
          }
        end,
        panel = {
          render = function(_) end,
        },
      })

      return {
        mutated = did_mutate,
        loclist = vim.fn.getloclist(0),
        cursor_line = vim.api.nvim_win_get_cursor(0)[1],
      }
    end

    local baseline = run_start(false)
    package.loaded["git-review.session"] = nil
    session = require("git-review.session")
    local mutated = run_start(true)

    vim.g.git_review_startup_cache_baseline = baseline
    vim.g.git_review_startup_cache_mutated_run = mutated
  ]=])

  local baseline = child.lua_get([[vim.g.git_review_startup_cache_baseline]])
  local mutated_run = child.lua_get([[vim.g.git_review_startup_cache_mutated_run]])

  assert(type(baseline) == "table" and type(mutated_run) == "table", "Expected captured startup outputs")
  assert(mutated_run.mutated == true, "Expected mutation setup during second start")
  assert(type(baseline.loclist) == "table" and type(mutated_run.loclist) == "table", "Expected loclist output snapshots")
  assert(#baseline.loclist == #mutated_run.loclist, "Expected equivalent startup loclist output sizes")
  assert(mutated_run.loclist[1].lnum == baseline.loclist[1].lnum, "Expected equivalent startup loclist first hunk")
  assert(mutated_run.cursor_line == baseline.cursor_line, "Expected equivalent startup first hunk cursor")
end

set["session.populate_files_quickfix returns context error without session"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.g.git_review_files_error = session.populate_files_quickfix()
  ]=])

  local result = child.lua_get([[vim.g.git_review_files_error]])
  assert(type(result) == "table", "Expected result table")
  assert(result.state == "context_error", "Expected context_error state")
  assert(result.message == "No active review session. Run :GitReview start first.", "Expected explicit context error message")
end

set["deletion block session commands return context_error without session"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.g.git_review_toggle_deletion_without_session = session.toggle_current_deletion_block()
    vim.g.git_review_toggle_deletions_without_session = session.toggle_deletion_blocks()
    vim.g.git_review_expand_deletions_without_session = session.expand_deletion_blocks()
    vim.g.git_review_collapse_deletions_without_session = session.collapse_deletion_blocks()
  ]=])

  local toggle_result = child.lua_get([[vim.g.git_review_toggle_deletion_without_session]])
  local toggle_all_result = child.lua_get([[vim.g.git_review_toggle_deletions_without_session]])
  local expand_result = child.lua_get([[vim.g.git_review_expand_deletions_without_session]])
  local collapse_result = child.lua_get([[vim.g.git_review_collapse_deletions_without_session]])

  assert(type(toggle_result) == "table", "Expected toggle deletion result table")
  assert(type(toggle_all_result) == "table", "Expected toggle deletions result table")
  assert(type(expand_result) == "table", "Expected expand deletions result table")
  assert(type(collapse_result) == "table", "Expected collapse deletions result table")
  assert(toggle_result.state == "context_error", "Expected toggle deletion context_error without session")
  assert(toggle_all_result.state == "context_error", "Expected toggle deletions context_error without session")
  assert(expand_result.state == "context_error", "Expected expand deletions context_error without session")
  assert(collapse_result.state == "context_error", "Expected collapse deletions context_error without session")
  assert(toggle_result.message == "No active review session. Run :GitReview start first.", "Expected explicit toggle deletion guidance")
  assert(toggle_all_result.message == "No active review session. Run :GitReview start first.", "Expected explicit toggle deletions guidance")
  assert(expand_result.message == "No active review session. Run :GitReview start first.", "Expected explicit expand deletions guidance")
  assert(collapse_result.message == "No active review session. Run :GitReview start first.", "Expected explicit collapse deletions guidance")
end

set["deletion block toggle helper chooses expand or collapse mode"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = nil

    vim.cmd("edit README.md")
    local target_file = vim.api.nvim_buf_get_name(0)
    local mode = "expand"
    local counts = {
      mode = 0,
      expand = 0,
      collapse = 0,
    }

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
          {
            filename = target_file,
            lnum = 1,
            end_lnum = 1,
            text = "README hunk",
            deleted_blocks = {
              {
                anchor_lnum = 1,
                lines = { "old line" },
              },
            },
          },
        }
      end,
      panel = {
        render = function(_) end,
      },
      fetch_review_threads = function(_)
        return {
          state = "ok",
          threads = {},
        }
      end,
      hunk_highlight = {
        get_deletion_toggle_mode = function(_)
          counts.mode = counts.mode + 1
          return mode
        end,
        expand_all_blocks = function(_)
          counts.expand = counts.expand + 1
          return true
        end,
        collapse_all_blocks = function(_)
          counts.collapse = counts.collapse + 1
          return true
        end,
      },
      diff_command = "git diff --no-color HEAD~1...HEAD",
      repo_root = vim.fs.normalize(vim.fn.getcwd()),
      defer_thread_refresh = true,
    })

    local expand_result = session.toggle_deletion_blocks()
    mode = "collapse"
    local collapse_result = session.toggle_deletion_blocks()

    vim.g.git_review_toggle_deletions_expand_result = expand_result
    vim.g.git_review_toggle_deletions_collapse_result = collapse_result
    vim.g.git_review_toggle_deletions_counts = counts
  ]=])

  local expand_result = child.lua_get([[vim.g.git_review_toggle_deletions_expand_result]])
  local collapse_result = child.lua_get([[vim.g.git_review_toggle_deletions_collapse_result]])
  local counts = child.lua_get([[vim.g.git_review_toggle_deletions_counts]])

  assert(type(expand_result) == "table" and expand_result.state == "ok", "Expected toggle_deletion_blocks expand mode success")
  assert(type(collapse_result) == "table" and collapse_result.state == "ok", "Expected toggle_deletion_blocks collapse mode success")
  assert(type(counts) == "table", "Expected toggle_deletion_blocks counters")
  assert(counts.mode == 2, "Expected toggle helper to query deletion toggle mode each call")
  assert(counts.expand == 1, "Expected expand mode to call expand_all_blocks")
  assert(counts.collapse == 1, "Expected collapse mode to call collapse_all_blocks")
end

set["deletion block toggle helper returns ok when resolver returns nil"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = nil

    vim.cmd("edit README.md")
    local target_file = vim.api.nvim_buf_get_name(0)
    local counts = {
      mode = 0,
      expand = 0,
      collapse = 0,
    }

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
          {
            filename = target_file,
            lnum = 1,
            end_lnum = 1,
            text = "README hunk",
            deleted_blocks = {
              {
                anchor_lnum = 1,
                lines = { "old line" },
              },
            },
          },
        }
      end,
      panel = {
        render = function(_) end,
      },
      fetch_review_threads = function(_)
        return {
          state = "ok",
          threads = {},
        }
      end,
      hunk_highlight = {
        get_deletion_toggle_mode = function(_)
          counts.mode = counts.mode + 1
          return nil
        end,
        expand_all_blocks = function(_)
          counts.expand = counts.expand + 1
          return true
        end,
        collapse_all_blocks = function(_)
          counts.collapse = counts.collapse + 1
          return true
        end,
      },
      diff_command = "git diff --no-color HEAD~1...HEAD",
      repo_root = vim.fs.normalize(vim.fn.getcwd()),
      defer_thread_refresh = true,
    })

    vim.g.git_review_toggle_deletions_nil_mode_result = session.toggle_deletion_blocks()
    vim.g.git_review_toggle_deletions_nil_mode_counts = counts
  ]=])

  local result = child.lua_get([[vim.g.git_review_toggle_deletions_nil_mode_result]])
  local counts = child.lua_get([[vim.g.git_review_toggle_deletions_nil_mode_counts]])

  assert(type(result) == "table" and result.state == "ok", "Expected nil mode to be treated as no-op success")
  assert(type(counts) == "table", "Expected nil mode counters")
  assert(counts.mode == 1, "Expected toggle helper to query mode once")
  assert(counts.expand == 0, "Expected nil mode to avoid expand_all_blocks")
  assert(counts.collapse == 0, "Expected nil mode to avoid collapse_all_blocks")
end

set["deletion block toggle helper returns command_error when resolver throws"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = nil

    vim.cmd("edit README.md")
    local target_file = vim.api.nvim_buf_get_name(0)

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
          {
            filename = target_file,
            lnum = 1,
            end_lnum = 1,
            text = "README hunk",
            deleted_blocks = {
              {
                anchor_lnum = 1,
                lines = { "old line" },
              },
            },
          },
        }
      end,
      panel = {
        render = function(_) end,
      },
      fetch_review_threads = function(_)
        return {
          state = "ok",
          threads = {},
        }
      end,
      hunk_highlight = {
        get_deletion_toggle_mode = function(_)
          error("resolver explosion")
        end,
      },
      diff_command = "git diff --no-color HEAD~1...HEAD",
      repo_root = vim.fs.normalize(vim.fn.getcwd()),
      defer_thread_refresh = true,
    })

    vim.g.git_review_toggle_deletions_throw_result = session.toggle_deletion_blocks()
  ]=])

  local result = child.lua_get([[vim.g.git_review_toggle_deletions_throw_result]])

  assert(type(result) == "table", "Expected throw mode result table")
  assert(result.state == "command_error", "Expected resolver throw to produce command_error")
  assert(
    type(result.message) == "string" and result.message:match("Failed to resolve deletion block toggle mode"),
    "Expected command_error resolver failure message"
  )
end

set["deletion block session commands call highlight API"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = nil

    vim.cmd("edit README.md")
    local target_file = vim.api.nvim_buf_get_name(0)
    local target_bufnr = vim.api.nvim_get_current_buf()

    local counters = {
      toggle = 0,
      expand = 0,
      collapse = 0,
      render_file_hunks = 0,
      render_current_hunk = 0,
      clear_file_hunks = 0,
    }

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
          {
            filename = target_file,
            lnum = 1,
            end_lnum = 1,
            text = "README hunk",
            deleted_blocks = {
              {
                anchor_lnum = 1,
                lines = { "old line" },
              },
            },
          },
        }
      end,
      panel = {
        render = function(_) end,
      },
      fetch_review_threads = function(_)
        return {
          state = "ok",
          threads = {},
        }
      end,
      hunk_highlight = {
        toggle_current_block = function(_)
          counters.toggle = counters.toggle + 1
          return true
        end,
        expand_all_blocks = function(_)
          counters.expand = counters.expand + 1
          return true
        end,
        collapse_all_blocks = function(_)
          counters.collapse = counters.collapse + 1
          return true
        end,
        render_current_hunk = function(_)
          counters.render_current_hunk = counters.render_current_hunk + 1
          return true
        end,
        render_file_hunks = function(opts)
          if type(opts) == "table" and opts.bufnr == target_bufnr then
            counters.render_file_hunks = counters.render_file_hunks + 1
          end
          return true
        end,
        clear_file_hunks = function(_)
          counters.clear_file_hunks = counters.clear_file_hunks + 1
          return true
        end,
      },
      diff_command = "git diff --no-color HEAD~1...HEAD",
      repo_root = vim.fs.normalize(vim.fn.getcwd()),
      defer_thread_refresh = true,
    })

    local toggle_result = session.toggle_current_deletion_block()
    local expand_result = session.expand_deletion_blocks()
    local collapse_result = session.collapse_deletion_blocks()

    vim.g.git_review_deletion_command_toggle_result = toggle_result
    vim.g.git_review_deletion_command_expand_result = expand_result
    vim.g.git_review_deletion_command_collapse_result = collapse_result
    vim.g.git_review_deletion_command_counts = counters
  ]=])

  local toggle_result = child.lua_get([[vim.g.git_review_deletion_command_toggle_result]])
  local expand_result = child.lua_get([[vim.g.git_review_deletion_command_expand_result]])
  local collapse_result = child.lua_get([[vim.g.git_review_deletion_command_collapse_result]])
  local counts = child.lua_get([[vim.g.git_review_deletion_command_counts]])
  assert(type(toggle_result) == "table" and toggle_result.state == "ok", "Expected toggle deletion command success")
  assert(type(expand_result) == "table" and expand_result.state == "ok", "Expected expand deletions command success")
  assert(type(collapse_result) == "table" and collapse_result.state == "ok", "Expected collapse deletions command success")

  assert(type(counts) == "table", "Expected command counter table")
  assert(counts.toggle == 1, "Expected toggle_current_block to be called once")
  assert(counts.expand == 1, "Expected expand_all_blocks to be called once")
  assert(counts.collapse == 1, "Expected collapse_all_blocks to be called once")
end

set["deletion block session toggle keeps expanded state with real renderer"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    package.loaded["git-review.ui.hunk_highlight"] = nil
    require("git-review").setup({
      deletions = {
        max_preview_lines = 1,
      },
    })

    local session = require("git-review.session")
    local hunk_highlight = require("git-review.ui.hunk_highlight")
    vim.ui.select = nil

    vim.cmd("edit README.md")
    local target_file = vim.api.nvim_buf_get_name(0)
    local bufnr = vim.api.nvim_get_current_buf()

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
          {
            filename = target_file,
            lnum = 1,
            end_lnum = 1,
            text = "README hunk",
            deleted_blocks = {
              {
                anchor_lnum = 1,
                lines = { "old one", "old two", "old three" },
              },
            },
          },
        }
      end,
      panel = {
        render = function(_) end,
      },
      fetch_review_threads = function(_)
        return {
          state = "ok",
          threads = {},
        }
      end,
      hunk_highlight = hunk_highlight,
      diff_command = "git diff --no-color HEAD~1...HEAD",
      repo_root = vim.fs.normalize(vim.fn.getcwd()),
      defer_thread_refresh = true,
    })

    local function current_virtual_line_count()
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, hunk_highlight.deletion_namespace_id(), 0, -1, { details = true })
      local details = type(marks[1]) == "table" and marks[1][4] or nil
      local virt_lines = type(details) == "table" and details.virt_lines or nil
      return type(virt_lines) == "table" and #virt_lines or 0
    end

    local before_count = current_virtual_line_count()
    local toggle_result = session.toggle_current_deletion_block({ bufnr = bufnr, lnum = 1 })
    local after_count = current_virtual_line_count()

    vim.g.git_review_session_toggle_before_count = before_count
    vim.g.git_review_session_toggle_after_count = after_count
    vim.g.git_review_session_toggle_result = toggle_result
  ]=])

  local before_count = child.lua_get([[vim.g.git_review_session_toggle_before_count or 0]])
  local after_count = child.lua_get([[vim.g.git_review_session_toggle_after_count or 0]])
  local toggle_result = child.lua_get([[vim.g.git_review_session_toggle_result]])

  assert(type(toggle_result) == "table" and toggle_result.state == "ok", "Expected toggle command success")
  assert(before_count == 2, "Expected collapsed preview to render one line plus summary")
  assert(after_count == 3, "Expected toggle command to expand deletion block")
end

set["GitReview files populates quickfix entries on demand without opening window"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    require("git-review").setup()

    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local x = 1
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+x
]]

    vim.fn.setqflist({}, " ", {
      title = "Before Quickfix",
      items = {
        {
          filename = vim.fs.normalize(vim.fn.getcwd() .. "/README.md"),
          lnum = 7,
          text = "keep-quickfix",
        },
      },
    })

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/quickfix-files"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
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
      defer_thread_refresh = true,
    })

    vim.cmd("cclose")

    local quickfix_open_before = false
    for _, info in ipairs(vim.fn.getwininfo()) do
      if info.quickfix == 1 then
        quickfix_open_before = true
      end
    end

    vim.cmd("GitReview files")

    local quickfix_open = false
    for _, info in ipairs(vim.fn.getwininfo()) do
      if info.quickfix == 1 then
        quickfix_open = true
      end
    end

    vim.g.git_review_files_items = vim.fn.getqflist()
    vim.g.git_review_files_title = vim.fn.getqflist({ title = 1 }).title
    vim.g.git_review_files_open = quickfix_open
    vim.g.git_review_files_open_before = quickfix_open_before
  ]=])

  local quickfix_items = child.lua_get([[vim.g.git_review_files_items]])
  local quickfix_title = child.lua_get([[vim.g.git_review_files_title]])
  local quickfix_open = child.lua_get([[vim.g.git_review_files_open]])
  local quickfix_open_before = child.lua_get([[vim.g.git_review_files_open_before]])

  assert(quickfix_open_before == false, "Expected quickfix window to be closed before :GitReview files")
  assert(quickfix_open == false, "Expected :GitReview files to avoid opening quickfix window")
  assert(quickfix_title == "Git Review Files", "Expected :GitReview files to set quickfix title")
  assert(type(quickfix_items) == "table" and #quickfix_items == 2, "Expected quickfix file entries")
  assert(quickfix_items[1].filename ~= "", "Expected first quickfix entry filename")
  assert(quickfix_items[2].filename ~= "", "Expected second quickfix entry filename")
end

set["GitReview files keeps loclist in sync with quickfix selection"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    require("git-review").setup()

    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local first = 1
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,1 @@
-old summary
+new summary
]]

    vim.cmd("edit README.md")

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/quickfix-sync"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
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
      defer_thread_refresh = true,
    })

    vim.cmd("GitReview files")

    local function item_path(item)
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

    local quickfix_items = vim.fn.getqflist()
    local target_idx = nil

    for idx, item in ipairs(quickfix_items) do
      local item_filename = item_path(item)
      if type(item_filename) == "string" and string.find(item_filename, "README.md", 1, true) then
        target_idx = idx
        break
      end
    end

    if target_idx ~= nil then
      vim.cmd("cc " .. target_idx)
    end

    local loclist_items = vim.fn.getloclist(0)
    local loclist_filename = type(loclist_items) == "table" and item_path(loclist_items[1]) or nil
    local target_filename = target_idx and item_path(quickfix_items[target_idx]) or nil
    local first_item = type(loclist_items) == "table" and loclist_items[1] or nil
    local first_deleted_blocks = type(first_item) == "table" and first_item.deleted_blocks or nil
    if first_deleted_blocks == nil and type(first_item) == "table" and type(first_item.user_data) == "table" then
      first_deleted_blocks = first_item.user_data.deleted_blocks
    end
    local first_deleted_block = type(first_deleted_blocks) == "table" and first_deleted_blocks[1] or nil

    vim.g.git_review_qf_item_count = #quickfix_items

    vim.g.git_review_loclist_filename = loclist_filename
    vim.g.git_review_qf_target_filename = target_filename
    vim.g.git_review_qf_loclist_deleted_block = first_deleted_block
  ]=])

  local loclist_filename = child.lua_get([[vim.g.git_review_loclist_filename]])
  local target_filename = child.lua_get([[vim.g.git_review_qf_target_filename]])
  local quickfix_count = child.lua_get([[vim.g.git_review_qf_item_count]])
  local deleted_block = child.lua_get([[vim.g.git_review_qf_loclist_deleted_block]])

  assert(type(quickfix_count) == "number" and quickfix_count >= 2, "Expected quickfix list to have multiple files")
  assert(type(target_filename) == "string" and target_filename ~= "", "Expected target quickfix filename")
  assert(loclist_filename == target_filename, "Expected loclist to sync with quickfix selection")
  assert(type(deleted_block) == "table", "Expected synced loclist hunk to preserve deleted_blocks metadata")
  assert(deleted_block.lines[1] == "old summary", "Expected synced loclist deleted block payload")
end

set["session.start keeps quickfix unchanged when picker UI is unavailable"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local x = 1
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+thread-refresh
 ]]

    vim.ui.select = nil

    vim.fn.setqflist({}, " ", {
      title = "Before Quickfix",
      items = {
        {
          filename = vim.fs.normalize(vim.fn.getcwd() .. "/README.md"),
          lnum = 7,
          text = "keep-quickfix",
        },
      },
    })

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/task-quickfix"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
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
      defer_thread_refresh = true,
    })

    local quickfix_open = false
    for _, info in ipairs(vim.fn.getwininfo()) do
      if info.quickfix == 1 then
        quickfix_open = true
      end
    end

    vim.g.git_review_quickfix_items = vim.fn.getqflist()
    vim.g.git_review_quickfix_title = vim.fn.getqflist({ title = 1 }).title
    vim.g.git_review_quickfix_open = quickfix_open
  ]=])

  local quickfix_items = child.lua_get([[vim.g.git_review_quickfix_items]])
  local quickfix_title = child.lua_get([[vim.g.git_review_quickfix_title]])
  local quickfix_open = child.lua_get([[vim.g.git_review_quickfix_open]])

  assert(quickfix_open == false, "Expected quickfix window to remain closed on session.start")
  assert(quickfix_title == "Before Quickfix", "Expected quickfix title to remain unchanged without picker")
  assert(type(quickfix_items) == "table" and #quickfix_items == 1, "Expected quickfix items to remain unchanged without picker")
  assert(quickfix_items[1].lnum == 7, "Expected existing quickfix entry to remain unchanged without picker")
end

set["session.start opens picker, avoids auto-opening quickfix, and seeds loclist after selection"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local first = 1
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+x
@@ -10,1 +11,2 @@
 text
+y
 ]]

    local function item_path(item)
      if type(item) ~= "table" then
        return ""
      end
      if type(item.filename) == "string" and item.filename ~= "" then
        return item.filename
      end
      if type(item.bufnr) == "number" and item.bufnr > 0 then
        return vim.api.nvim_buf_get_name(item.bufnr)
      end
      return ""
    end

    local function is_quickfix_open()
      for _, info in ipairs(vim.fn.getwininfo()) do
        if info.quickfix == 1 then
          return true
        end
      end

      return false
    end

    local picker_count = 0
    local picker_paths = {}
    local loclist_before_choice = -1
    local loclist_after_choice = -1

    vim.ui.select = function(items, _, on_choice)
      picker_count = picker_count + 1
      for _, item in ipairs(items) do
        table.insert(picker_paths, item_path(item))
      end

      loclist_before_choice = #vim.fn.getloclist(0)

      local choice = items[1]
      local choice_idx = 1
      for idx, item in ipairs(items) do
        local path = item_path(item)
        if string.find(path, "README.md", 1, true) then
          choice = item
          choice_idx = idx
          break
        end
      end

      on_choice(choice, choice_idx)
      loclist_after_choice = #vim.fn.getloclist(0)
    end

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "HEAD~1...HEAD"
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
      diff_command = "git diff --no-color HEAD~1...HEAD",
    })

    local quickfix_open = is_quickfix_open()

    vim.g.git_review_picker_count = picker_count
    vim.g.git_review_picker_paths = picker_paths
    vim.g.git_review_picker_loclist_before_choice = loclist_before_choice
    vim.g.git_review_picker_loclist_after_choice = loclist_after_choice
    vim.g.git_review_picker_loclist_items = vim.fn.getloclist(0)
    vim.g.git_review_picker_quickfix_open = quickfix_open
  ]=])

  local picker_count = child.lua_get([[vim.g.git_review_picker_count]])
  local picker_paths = child.lua_get([[vim.g.git_review_picker_paths]])
  local loclist_before_choice = child.lua_get([[vim.g.git_review_picker_loclist_before_choice]])
  local loclist_after_choice = child.lua_get([[vim.g.git_review_picker_loclist_after_choice]])
  local loclist_items = child.lua_get([[vim.g.git_review_picker_loclist_items]])
  local quickfix_open = child.lua_get([[vim.g.git_review_picker_quickfix_open]])

  assert(picker_count == 1, "Expected session.start to call vim.ui.select once")

  local saw_init = false
  local saw_readme = false
  for _, path in ipairs(picker_paths) do
    if type(path) == "string" and string.find(path, "lua/git-review/init.lua", 1, true) then
      saw_init = true
    end
    if type(path) == "string" and string.find(path, "README.md", 1, true) then
      saw_readme = true
    end
  end

  assert(saw_init, "Expected picker to include init.lua changed file")
  assert(saw_readme, "Expected picker to include README.md changed file")
  assert(quickfix_open == false, "Expected session.start to avoid opening quickfix")
  assert(loclist_before_choice == 0, "Expected loclist to remain empty before picker selection")
  assert(loclist_after_choice == 2, "Expected picker selection to seed selected file hunks into loclist")
  assert(type(loclist_items) == "table" and #loclist_items == 2, "Expected selected file hunks in loclist")
end

set["session.start picker cancel keeps loclist and quickfix unchanged"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local repo_root = vim.fs.normalize(vim.fn.getcwd())
    local abs_readme = vim.fs.normalize(repo_root .. "/README.md")
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local first = 1
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+x
 ]]

    local function is_quickfix_open()
      for _, info in ipairs(vim.fn.getwininfo()) do
        if info.quickfix == 1 then
          return true
        end
      end

      return false
    end

    vim.fn.setloclist(0, {}, " ", {
      title = "Before Loclist",
      items = {
        {
          filename = abs_readme,
          lnum = 3,
          end_lnum = 4,
          text = "keep-loclist",
        },
      },
      idx = 1,
    })

    vim.fn.setqflist({}, " ", {
      title = "Before Quickfix",
      items = {
        {
          filename = abs_readme,
          lnum = 7,
          text = "keep-quickfix",
        },
      },
      idx = 1,
    })

    local quickfix_open_before = is_quickfix_open()

    local picker_count = 0
    vim.ui.select = function(_, _, on_choice)
      picker_count = picker_count + 1
      on_choice(nil, nil)
    end

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "HEAD~1...HEAD"
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
      diff_command = "git diff --no-color HEAD~1...HEAD",
    })

    local quickfix_open_after = is_quickfix_open()

    vim.g.git_review_picker_cancel_count = picker_count
    vim.g.git_review_picker_cancel_loclist_items = vim.fn.getloclist(0)
    vim.g.git_review_picker_cancel_loclist_title = vim.fn.getloclist(0, { title = 1 }).title
    vim.g.git_review_picker_cancel_quickfix_items = vim.fn.getqflist()
    vim.g.git_review_picker_cancel_quickfix_title = vim.fn.getqflist({ title = 1 }).title
    vim.g.git_review_picker_cancel_quickfix_open_before = quickfix_open_before
    vim.g.git_review_picker_cancel_quickfix_open_after = quickfix_open_after
  ]=])

  local picker_count = child.lua_get([[vim.g.git_review_picker_cancel_count]])
  local loclist_items = child.lua_get([[vim.g.git_review_picker_cancel_loclist_items]])
  local loclist_title = child.lua_get([[vim.g.git_review_picker_cancel_loclist_title]])
  local quickfix_items = child.lua_get([[vim.g.git_review_picker_cancel_quickfix_items]])
  local quickfix_title = child.lua_get([[vim.g.git_review_picker_cancel_quickfix_title]])
  local quickfix_open_before = child.lua_get([[vim.g.git_review_picker_cancel_quickfix_open_before]])
  local quickfix_open_after = child.lua_get([[vim.g.git_review_picker_cancel_quickfix_open_after]])

  assert(picker_count == 1, "Expected picker to be shown once")
  assert(loclist_title == "Before Loclist", "Expected loclist title to stay unchanged on picker cancel")
  assert(type(loclist_items) == "table" and #loclist_items == 1, "Expected loclist items to stay unchanged on picker cancel")
  assert(loclist_items[1].lnum == 3, "Expected loclist entry to stay unchanged on picker cancel")
  assert(quickfix_title == "Before Quickfix", "Expected quickfix title to stay unchanged on picker cancel")
  assert(type(quickfix_items) == "table" and #quickfix_items == 1, "Expected quickfix items to stay unchanged on picker cancel")
  assert(quickfix_items[1].lnum == 7, "Expected quickfix entry to stay unchanged on picker cancel")
  assert(quickfix_open_before == false, "Expected no quickfix window before picker cancel")
  assert(quickfix_open_after == false, "Expected no quickfix window after picker cancel")
end

set["session.start picker cancel avoids loclist highlight without selection"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local repo_root = vim.fs.normalize(vim.fn.getcwd())
    local abs_readme = vim.fs.normalize(repo_root .. "/README.md")
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local first = 1
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+x
 ]]

    vim.fn.setloclist(0, {}, " ", {
      title = "Before Loclist",
      items = {
        {
          filename = abs_readme,
          lnum = 3,
          end_lnum = 4,
          text = "keep-loclist",
        },
      },
      idx = 1,
    })

    vim.cmd("lopen")
    vim.cmd("lfirst")
    vim.cmd("wincmd p")

    local highlight_entries = {}
    vim.ui.select = function(_, _, on_choice)
      if type(on_choice) == "function" then
        on_choice(nil, nil)
      end
    end

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "HEAD~1...HEAD"
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
      diff_command = "git diff --no-color HEAD~1...HEAD",
      hunk_highlight = {
        render_current_hunk = function(opts)
          local item = opts and opts.qf_item or nil
          local lnum = type(item) == "table" and item.lnum or nil
          table.insert(highlight_entries, lnum == nil and "none" or lnum)
        end,
      },
    })

    vim.g.git_review_picker_cancel_highlight_entries = highlight_entries
  ]=])

  local highlight_entries = child.lua_get([[vim.g.git_review_picker_cancel_highlight_entries]])
  assert(type(highlight_entries) == "table", "Expected highlight entries table")
  assert(highlight_entries[1] == "none", "Expected no active highlight before picker selection")
end

set["session.start applies hunk highlight in current buffer from nested cwd"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local hunk_highlight = require("git-review.ui.hunk_highlight")
    local repo_root = vim.fs.normalize(vim.fn.getcwd())
    local abs_readme = vim.fs.normalize(repo_root .. "/README.md")
    local diff = [[
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+x
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,1 +1,2 @@
 local M = {}
+local y = 2
 ]]

    vim.cmd("edit " .. abs_readme)
    local current_buf = vim.api.nvim_get_current_buf()
    vim.cmd("lcd lua")

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/highlight-cwd"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
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
      repo_root = repo_root,
    })

    local marks = vim.api.nvim_buf_get_extmarks(current_buf, hunk_highlight.namespace_id(), 0, -1, {})
    vim.g.git_review_nested_cwd_highlight_count = #marks
  ]=])

  local highlight_count = child.lua_get([[vim.g.git_review_nested_cwd_highlight_count or 0]])
  assert(highlight_count > 0, "Expected current buffer to receive hunk highlight from review quickfix")
end

set["session.start prefers current buffer hunk for initial highlight"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local hunk_highlight = require("git-review.ui.hunk_highlight")
    local repo_root = vim.fs.normalize(vim.fn.getcwd())
    local abs_readme = vim.fs.normalize(repo_root .. "/README.md")
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local first = 1
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+x
 ]]

    vim.cmd("edit " .. abs_readme)
    local current_buf = vim.api.nvim_get_current_buf()

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/highlight-current-buffer"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
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
      repo_root = repo_root,
    })

    local marks = vim.api.nvim_buf_get_extmarks(current_buf, hunk_highlight.namespace_id(), 0, -1, {})
    vim.g.git_review_current_buffer_highlight_count = #marks
  ]=])

  local highlight_count = child.lua_get([[vim.g.git_review_current_buffer_highlight_count or 0]])
  assert(highlight_count > 0, "Expected initial highlight to prefer current buffer hunk")
end

set["session.start renders all changed hunks for current file and syncs on BufEnter"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local repo_root = vim.fs.normalize(vim.fn.getcwd())
    local abs_readme = vim.fs.normalize(repo_root .. "/README.md")
    local abs_init = vim.fs.normalize(repo_root .. "/lua/git-review/init.lua")
    local diff = [[
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,1 @@
-old intro
+new intro
@@ -10,1 +11,2 @@
-text
+text
+y
 ]]

    local file_hunk_calls = 0
    local rendered_ranges = 0
    local clear_file_hunk_calls = 0

    vim.cmd("edit " .. abs_readme)

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/file-hunks"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
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
      hunk_highlight = {
        render_current_hunk = function(_) end,
        render_file_hunks = function(opts)
          file_hunk_calls = file_hunk_calls + 1
          rendered_ranges = type(opts.ranges) == "table" and #opts.ranges or 0
          return true
        end,
        clear_file_hunks = function(_)
          clear_file_hunk_calls = clear_file_hunk_calls + 1
        end,
      },
      repo_root = repo_root,
    })

    vim.cmd("edit " .. abs_init)

    vim.g.git_review_file_hunk_calls = file_hunk_calls
    vim.g.git_review_file_hunk_ranges = rendered_ranges
    vim.g.git_review_file_hunk_clear_calls = clear_file_hunk_calls
  ]=])

  local file_hunk_calls = child.lua_get([[vim.g.git_review_file_hunk_calls or 0]])
  local rendered_ranges = child.lua_get([[vim.g.git_review_file_hunk_ranges or 0]])
  local clear_calls = child.lua_get([[vim.g.git_review_file_hunk_clear_calls or 0]])

  assert(file_hunk_calls >= 1, "Expected current-file hunk rendering on start")
  assert(rendered_ranges == 2, "Expected all changed README hunks to be rendered")
  assert(clear_calls == 1, "Expected non-review buffer enter to clear passive highlights")
end

set["session.start refresh hook updates file hunk highlights"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local repo_root = vim.fs.normalize(vim.fn.getcwd())
    local abs_readme = vim.fs.normalize(repo_root .. "/README.md")
    local diff = [[
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+x
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,1 +1,2 @@
 local M = {}
+local y = 2
 ]]

    local file_hunk_calls = 0
    vim.cmd("edit " .. abs_readme)

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/file-hunks-refresh"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
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
      hunk_highlight = {
        render_current_hunk = function(_) end,
        render_file_hunks = function(_)
          file_hunk_calls = file_hunk_calls + 1
          return true
        end,
      },
      repo_root = repo_root,
    })

    local loc_items = vim.fn.getloclist(0)
    if #loc_items > 1 then
      vim.cmd("lfirst")
      vim.cmd("lnext")
    end
    vim.g.git_review_file_hunks_refresh_calls = file_hunk_calls
  ]=])

  local calls = child.lua_get([[vim.g.git_review_file_hunks_refresh_calls or 0]])
  assert(calls >= 2, "Expected file hunk highlights on start and quickfix refresh")
end

set["session.start seeds loclist with hunks for selected quickfix file"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local repo_root = vim.fs.normalize(vim.fn.getcwd())
    local abs_readme = vim.fs.normalize(repo_root .. "/README.md")
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local first = 1
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+x
@@ -10,1 +11,2 @@
 text
+y
 ]]

    vim.cmd("edit " .. abs_readme)

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/loclist-seed"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
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
      repo_root = repo_root,
    })

    local loclist_items = vim.fn.getloclist(0)
    vim.g.git_review_loclist_seed_items = loclist_items
    vim.g.git_review_loclist_seed_title = vim.fn.getloclist(0, { title = 1 }).title
  ]=])

  local loclist_items = child.lua_get([[vim.g.git_review_loclist_seed_items]])
  local loclist_title = child.lua_get([[vim.g.git_review_loclist_seed_title]])

  assert(type(loclist_items) == "table", "Expected loclist items table")
  assert(#loclist_items == 2, "Expected selected quickfix file hunks in loclist")
  assert(loclist_items[1].lnum == 1, "Expected first README hunk start in loclist")
  assert(loclist_items[2].lnum == 11, "Expected second README hunk start in loclist")
  assert(loclist_title == "Git Review Hunks", "Expected loclist title for review hunks")
end

set["session.start loclist navigation stays scoped to selected file hunks"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local repo_root = vim.fs.normalize(vim.fn.getcwd())
    local abs_readme = vim.fs.normalize(repo_root .. "/README.md")
    local diff = [[
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+x
@@ -10,1 +11,2 @@
 text
+y
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -20,2 +20,3 @@
 local M = {}
+local first = 1
 ]]

    vim.cmd("edit " .. abs_readme)

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/loclist-refresh"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
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
      repo_root = repo_root,
    })

    local loc_items = vim.fn.getloclist(0)
    if #loc_items > 1 then
      vim.cmd("lfirst")
      vim.cmd("lnext")
    end

    vim.g.git_review_loclist_refresh_items = vim.fn.getloclist(0)
    vim.g.git_review_loclist_refresh_title = vim.fn.getloclist(0, { title = 1 }).title
  ]=])

  local loclist_items = child.lua_get([[vim.g.git_review_loclist_refresh_items]])
  local loclist_title = child.lua_get([[vim.g.git_review_loclist_refresh_title]])

  assert(type(loclist_items) == "table", "Expected loclist items table")
  assert(#loclist_items == 2, "Expected loclist to stay scoped to selected file hunks")
  assert(loclist_items[1].lnum == 1, "Expected first selected-file hunk line in loclist")
  assert(loclist_items[2].lnum == 11, "Expected second selected-file hunk line in loclist")
  assert(loclist_title == "Git Review Hunks", "Expected loclist title for review hunks")
end

set["session.start active hunk highlight follows loclist navigation"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local repo_root = vim.fs.normalize(vim.fn.getcwd())
    local abs_readme = vim.fs.normalize(repo_root .. "/README.md")
    local diff = [[
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+x
@@ -10,1 +11,2 @@
 text
+y
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -20,2 +20,3 @@
 local M = {}
+local first = 1
 ]]

    local highlight_lnums = {}

    vim.cmd("edit " .. abs_readme)

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/loclist-highlight"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
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
      hunk_highlight = {
        render_current_hunk = function(opts)
          local item = opts and opts.qf_item or nil
          local lnum = type(item) == "table" and item.lnum or -1
          table.insert(highlight_lnums, lnum)
        end,
      },
      repo_root = repo_root,
    })

    local expected_lnum = 11
    local loc_items = vim.fn.getloclist(0)
    if #loc_items > 1 then
      vim.cmd("lfirst")
      vim.cmd("lnext")
      expected_lnum = 11
    end

    vim.g.git_review_loclist_highlight_lnums = highlight_lnums
    vim.g.git_review_loclist_expected_lnum = expected_lnum
  ]=])

  local lnums = child.lua_get([[vim.g.git_review_loclist_highlight_lnums]])
  assert(type(lnums) == "table", "Expected captured highlight line list")
  assert(lnums[1] == 1, "Expected initial highlight at first README hunk")
  assert(#lnums >= 2, "Expected loclist navigation to trigger active highlight refresh")
  assert(type(lnums[#lnums]) == "number" and lnums[#lnums] > 0, "Expected refresh highlight to resolve a valid hunk line")
end

set["session.start loclist-only flow keeps active hunk highlight in sync without quickfix list"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local repo_root = vim.fs.normalize(vim.fn.getcwd())
    local abs_readme = vim.fs.normalize(repo_root .. "/README.md")
    local diff = [[
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+x
@@ -10,1 +11,2 @@
 text
+y
]]

    local highlight_lnums = {}

    vim.cmd("edit " .. abs_readme)

    local original_getqflist = vim.fn.getqflist
    vim.fn.getqflist = function(opts)
      if type(opts) == "table" and opts.id == 0 then
        return {}
      end
      return original_getqflist(opts)
    end

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "HEAD~1...HEAD"
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
      diff_command = "git diff --no-color HEAD~1...HEAD",
      hunk_highlight = {
        render_current_hunk = function(opts)
          local item = opts and opts.qf_item or nil
          local lnum = type(item) == "table" and item.lnum or -1
          table.insert(highlight_lnums, lnum)
        end,
      },
      repo_root = repo_root,
    })

    local loc_items = vim.fn.getloclist(0)
    if #loc_items > 1 then
      vim.cmd("lfirst")
      vim.cmd("lnext")
      vim.api.nvim_exec_autocmds("CursorMoved", { modeline = false })
    end

    vim.g.git_review_loclist_only_highlight_lnums = highlight_lnums
  ]=])

  local lnums = child.lua_get([[vim.g.git_review_loclist_only_highlight_lnums]])
  assert(type(lnums) == "table", "Expected captured highlight line list")
  assert(lnums[1] == 1, "Expected initial highlight at first README hunk")
  assert(#lnums >= 2, "Expected loclist navigation to trigger highlight refresh without quickfix list")
  assert(lnums[#lnums] == 11, "Expected refresh highlight to follow loclist-only navigation")
end

set["session.start keeps review loclist scoped to source window during unrelated window movement"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local repo_root = vim.fs.normalize(vim.fn.getcwd())
    local abs_readme = vim.fs.normalize(repo_root .. "/README.md")
    local abs_init = vim.fs.normalize(repo_root .. "/lua/git-review/init.lua")
    local diff = [[
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+x
@@ -10,1 +11,2 @@
 text
+y
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -20,2 +20,3 @@
 local M = {}
+local first = 1
 ]]

    vim.cmd("edit " .. abs_readme)
    local review_winid = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    local unrelated_winid = vim.api.nvim_get_current_win()
    vim.cmd("wincmd h")

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/review-window-loclist"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
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
      repo_root = repo_root,
    })

    vim.fn.setloclist(unrelated_winid, {}, " ", {
      title = "Unrelated Window Loclist",
      items = {
        {
          filename = abs_init,
          lnum = 1,
          text = "unrelated",
        },
      },
      idx = 1,
    })

    vim.api.nvim_set_current_win(unrelated_winid)
    vim.cmd("edit " .. abs_init)
    vim.cmd("normal j")
    local loc_items = vim.fn.getloclist(0)
    if #loc_items > 1 then
      vim.cmd("lfirst")
      vim.cmd("lnext")
    end

    vim.g.git_review_loclist_scope_review_title = vim.fn.getloclist(review_winid, { title = 1 }).title
    vim.g.git_review_loclist_scope_review_items = vim.fn.getloclist(review_winid)
    vim.g.git_review_loclist_scope_unrelated_title = vim.fn.getloclist(unrelated_winid, { title = 1 }).title
    vim.g.git_review_loclist_scope_unrelated_items = vim.fn.getloclist(unrelated_winid)
  ]=])

  local unrelated_title = child.lua_get([[vim.g.git_review_loclist_scope_unrelated_title]])
  local unrelated_items = child.lua_get([[vim.g.git_review_loclist_scope_unrelated_items]])

  assert(unrelated_title == "Unrelated Window Loclist", "Expected unrelated window loclist title to remain untouched")
  assert(type(unrelated_items) == "table" and #unrelated_items == 1, "Expected unrelated window loclist items to remain untouched")
end

set["session.start active hunk highlight follows selected loclist file when loclist entry is invalid"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local repo_root = vim.fs.normalize(vim.fn.getcwd())
    local abs_readme = vim.fs.normalize(repo_root .. "/README.md")
    local diff = [[
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+x
@@ -10,1 +11,2 @@
 text
+y
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -20,2 +20,3 @@
 local M = {}
+local first = 1
 ]]

    local highlight_lnums = {}
    local highlight_files = {}

    vim.cmd("edit " .. abs_readme)

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/loclist-fallback-highlight"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
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
      hunk_highlight = {
        render_current_hunk = function(opts)
          local item = opts and opts.qf_item or nil
          local path = ""
          if type(item) == "table" then
            if type(item.filename) == "string" and item.filename ~= "" then
              path = item.filename
            elseif type(item.bufnr) == "number" and item.bufnr > 0 then
              path = vim.api.nvim_buf_get_name(item.bufnr)
            end
          end
          local lnum = type(item) == "table" and item.lnum or -1
          table.insert(highlight_files, path)
          table.insert(highlight_lnums, lnum)
        end,
      },
      repo_root = repo_root,
    })

    local loc_items = vim.fn.getloclist(0)
    if #loc_items > 1 then
      vim.cmd("lfirst")
      vim.cmd("lnext")
    end

    local selected_loclist = vim.fn.getloclist(0, { idx = 0, items = 1 })
    local selected_item = type(selected_loclist) == "table" and selected_loclist.items[selected_loclist.idx] or nil
    local selected_file = ""
    if type(selected_item) == "table" then
      if type(selected_item.filename) == "string" and selected_item.filename ~= "" then
        selected_file = selected_item.filename
      elseif type(selected_item.bufnr) == "number" and selected_item.bufnr > 0 then
        selected_file = vim.api.nvim_buf_get_name(selected_item.bufnr)
      end
    end
    local expected_lnum = 1
    if string.find(selected_file, "lua/git-review/init.lua", 1, true) then
      expected_lnum = 20
    end

    vim.g.git_review_loclist_fallback_highlight_files = highlight_files
    vim.g.git_review_loclist_fallback_highlight_lnums = highlight_lnums
    vim.g.git_review_loclist_fallback_selected_file = selected_file
    vim.g.git_review_loclist_fallback_expected_lnum = expected_lnum
  ]=])

  local files = child.lua_get([[vim.g.git_review_loclist_fallback_highlight_files]])
  local lnums = child.lua_get([[vim.g.git_review_loclist_fallback_highlight_lnums]])
  local selected_file = child.lua_get([[vim.g.git_review_loclist_fallback_selected_file]])
  local expected_lnum = child.lua_get([[vim.g.git_review_loclist_fallback_expected_lnum]])

  assert(type(files) == "table", "Expected captured highlight file list")
  assert(type(lnums) == "table", "Expected captured highlight line list")
  assert(type(selected_file) == "string" and selected_file ~= "", "Expected selected loclist file after navigation")
  local highlighted_file = files[#files]
  local same_file = type(highlighted_file) == "string"
    and highlighted_file ~= ""
    and vim.fs.basename(highlighted_file) == vim.fs.basename(selected_file)
  assert(same_file == true, "Expected fallback highlight file from selected loclist entry")
  assert(lnums[#lnums] == expected_lnum, "Expected fallback highlight line to use first hunk from selected loclist file")
end

set["session.start ignores unrelated quickfix when picker drives initial loclist highlight"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local repo_root = vim.fs.normalize(vim.fn.getcwd())
    local abs_readme = vim.fs.normalize(repo_root .. "/README.md")
    local abs_license = vim.fs.normalize(repo_root .. "/LICENSE")
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local first = 1
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+x
 ]]

    local highlighted_file = ""
    local highlighted_lnum = -1

    vim.cmd("edit " .. abs_readme)

    vim.fn.setqflist({}, " ", {
      title = "Unrelated Quickfix",
      items = {
        {
          filename = abs_license,
          lnum = 1,
          text = "unrelated",
        },
      },
      idx = 1,
    })

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/picker-unrelated-quickfix"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
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
      hunk_highlight = {
        render_current_hunk = function(opts)
          local item = opts and opts.qf_item or nil
          if type(item) ~= "table" then
            highlighted_file = ""
            highlighted_lnum = -1
            return
          end

          if type(item.filename) == "string" and item.filename ~= "" then
            highlighted_file = item.filename
          elseif type(item.bufnr) == "number" and item.bufnr > 0 then
            highlighted_file = vim.api.nvim_buf_get_name(item.bufnr)
          else
            highlighted_file = ""
          end

          highlighted_lnum = type(item.lnum) == "number" and item.lnum or -1
        end,
      },
      repo_root = repo_root,
    })

    vim.g.git_review_picker_initial_highlight_file = highlighted_file
    vim.g.git_review_picker_initial_highlight_lnum = highlighted_lnum
  ]=])

  local highlighted_file = child.lua_get([[vim.g.git_review_picker_initial_highlight_file]])
  local highlighted_lnum = child.lua_get([[vim.g.git_review_picker_initial_highlight_lnum]])

  assert(type(highlighted_file) == "string" and string.find(highlighted_file, "README.md", 1, true), "Expected initial highlight file from picker-selected loclist entry")
  assert(highlighted_lnum == 1, "Expected initial highlight line from first selected-file hunk")
end

set["session.start emits debug logs when debug_log callback is provided"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local x = 1
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+thread-refresh
 ]]

    local logs = {}
    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/pr-base"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
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
      repo = "max-farver/git-review.nvim",
      commit_id = "abc123",
      repo_root = ".",
      debug_log = function(message)
        table.insert(logs, message)
      end,
    })

    vim.g.git_review_debug_logs = logs
  ]=])

  local logs = child.lua_get([[vim.g.git_review_debug_logs]])
  assert(type(logs) == "table", "Expected debug logs list")
  assert(#logs >= 4, "Expected debug log messages")

  local saw_diff_command = false
  local saw_hunks_count = false

  for _, message in ipairs(logs) do
    if string.find(message, "diff command", 1, true) then
      saw_diff_command = true
    end
    if string.find(message, "parsed hunks", 1, true) then
      saw_hunks_count = true
    end
  end

  assert(saw_diff_command, "Expected diff command debug log")
  assert(saw_hunks_count, "Expected parsed hunks debug log")
end

set["setup wires :GitReview start to session.start"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([[
    package.loaded["git-review.session"] = {
      start = function()
        vim.g.git_review_start_call_count = (vim.g.git_review_start_call_count or 0) + 1
        return { state = "ok", hunks = {} }
      end,
    }

    pcall(vim.api.nvim_del_user_command, "GitReview")
    require("git-review").setup()
    vim.cmd("GitReview start")
  ]])

  local call_count = child.lua_get([[vim.g.git_review_start_call_count or 0]])
  assert(call_count == 1, "Expected :GitReview start to call session.start exactly once")
end

set["setup wires :GitReview toggle-resolved to session.toggle_resolved_thread_visibility"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([[
    package.loaded["git-review.session"] = {
      is_active = function()
        return true
      end,
      toggle_resolved_thread_visibility = function()
        vim.g.git_review_toggle_resolved_call_count = (vim.g.git_review_toggle_resolved_call_count or 0) + 1
        return { state = "ok" }
      end,
    }

    pcall(vim.api.nvim_del_user_command, "GitReview")
    require("git-review").setup()
    vim.cmd("GitReview toggle-resolved")
  ]])

  local call_count = child.lua_get([[vim.g.git_review_toggle_resolved_call_count or 0]])
  assert(call_count == 1, "Expected :GitReview toggle-resolved to call session.toggle_resolved_thread_visibility exactly once")
end

set[":GitReview start handles session.start failures without crashing"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([[
    local original_notify = vim.notify
    vim.g.git_review_notify_message = nil
    vim.g.git_review_notify_level = nil

    vim.notify = function(message, level)
      vim.g.git_review_notify_message = message
      vim.g.git_review_notify_level = level
    end

    package.loaded["git-review.session"] = {
      start = function()
        error("range lookup blew up")
      end,
    }

    pcall(vim.api.nvim_del_user_command, "GitReview")
    require("git-review").setup()
    vim.g.git_review_start_command_ok = pcall(vim.cmd, "GitReview start")

    vim.notify = original_notify
  ]])

  local ok = child.lua_get([[vim.g.git_review_start_command_ok]])
  assert(ok == true, "Expected :GitReview start to not hard-crash")

  local notify_message = child.lua_get([[vim.g.git_review_notify_message]])
  local notify_level = child.lua_get([[vim.g.git_review_notify_level]])

  assert(type(notify_message) == "string", "Expected notify message")
  assert(string.find(notify_message, "start failed", 1, true), "Expected actionable failure prefix")
  assert(string.find(notify_message, "range lookup blew up", 1, true), "Expected root cause in notify message")
  assert(notify_level == vim.log.levels.ERROR, "Expected error-level notification")
end

set[":GitReview start handles session module load failures without crashing"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([[
    local original_notify = vim.notify
    vim.g.git_review_notify_message = nil
    vim.g.git_review_notify_level = nil

    vim.notify = function(message, level)
      vim.g.git_review_notify_message = message
      vim.g.git_review_notify_level = level
    end

    package.preload["git-review.session"] = function()
      error("module load blew up")
    end

    pcall(vim.api.nvim_del_user_command, "GitReview")
    require("git-review").setup()
    vim.g.git_review_start_command_ok = pcall(vim.cmd, "GitReview start")

    vim.notify = original_notify
  ]])

  local ok = child.lua_get([[vim.g.git_review_start_command_ok]])
  assert(ok == true, "Expected :GitReview start to not hard-crash")

  local notify_message = child.lua_get([[vim.g.git_review_notify_message]])
  local notify_level = child.lua_get([[vim.g.git_review_notify_level]])

  assert(type(notify_message) == "string", "Expected notify message")
  assert(string.find(notify_message, "start failed", 1, true), "Expected actionable failure prefix")
  assert(string.find(notify_message, "module load blew up", 1, true), "Expected module load root cause in notify message")
  assert(notify_level == vim.log.levels.ERROR, "Expected error-level notification")
end

set["session.start resolves default diff command from review range"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,1 +1,2 @@
 local M = {}
+local x = 1
@@ -10,1 +11,2 @@
 return M
+local y = 2
 ]]

    local commands = {}
    vim.g.git_review_start_state = session.start({
      run_command = function(command)
        table.insert(commands, command)

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
          stderr = "unexpected command: " .. command,
        }
      end,
    })

    vim.g.git_review_commands = commands
  ]=])

  local commands = child.lua_get([[vim.g.git_review_commands]])

  local saw_upstream_lookup = false
  local saw_review_diff = false
  for _, command in ipairs(commands) do
    if type(command) == "table"
      and command[1] == "git"
      and command[2] == "rev-parse"
      and command[3] == "--abbrev-ref"
      and command[4] == "--symbolic-full-name"
      and command[5] == "@{upstream}"
    then
      saw_upstream_lookup = true
    end

    if type(command) == "table"
      and command[1] == "git"
      and command[2] == "diff"
      and command[3] == "--no-color"
      and command[4] == "origin/main...HEAD"
    then
      saw_review_diff = true
    end
  end

  assert(saw_upstream_lookup, "Expected upstream range resolution call")
  assert(saw_review_diff, "Expected review range diff command")
end

set["session.start prefers pull request base branch for diff range"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local x = 1
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+thread-refresh
 ]]

    local commands = {}
    vim.g.git_review_start_state = session.start({
      run_command = function(command)
        table.insert(commands, command)

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/pr-base"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
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
      repo = "max-farver/git-review.nvim",
      commit_id = "abc123",
      repo_root = ".",
    })

    vim.g.git_review_commands = commands
  ]=])

  local commands = child.lua_get([[vim.g.git_review_commands]])

  local saw_pr_base_diff = false
  local saw_upstream_lookup = false
  local saw_local_diff = false
  for _, command in ipairs(commands) do
    if type(command) == "table"
      and command[1] == "git"
      and command[2] == "diff"
      and command[3] == "--no-color"
      and command[4] == "origin/main...HEAD"
    then
      saw_pr_base_diff = true
    end

    if type(command) == "table"
      and command[1] == "git"
      and command[2] == "rev-parse"
      and command[3] == "--abbrev-ref"
      and command[4] == "--symbolic-full-name"
      and command[5] == "@{upstream}"
    then
      saw_upstream_lookup = true
    end

    if type(command) == "table"
      and command[1] == "git"
      and command[2] == "diff"
      and command[3] == "--no-color"
      and command[4] == "HEAD"
    then
      saw_local_diff = true
    end
  end

  assert(saw_pr_base_diff, "Expected diff range derived from PR base branch")
  assert(saw_upstream_lookup == false, "Expected no upstream fallback when PR base is available")
  assert(saw_local_diff == false, "Expected PR base diff to win before local fallback")
end

set["session.start falls back to upstream diff range when PR base is unavailable"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local x = 1
 ]]

    local commands = {}
    vim.g.git_review_start_state = session.start({
      run_command = function(command)
        table.insert(commands, command)

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/pr-base"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "no_pr",
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
      repo = "max-farver/git-review.nvim",
      commit_id = "abc123",
      repo_root = ".",
    })

    vim.g.git_review_commands = commands
  ]=])

  local commands = child.lua_get([[vim.g.git_review_commands]])

  local saw_upstream_lookup = false
  local saw_upstream_diff = false
  local saw_local_diff = false
  for _, command in ipairs(commands) do
    if type(command) == "table"
      and command[1] == "git"
      and command[2] == "rev-parse"
      and command[3] == "--abbrev-ref"
      and command[4] == "--symbolic-full-name"
      and command[5] == "@{upstream}"
    then
      saw_upstream_lookup = true
    end

    if type(command) == "table"
      and command[1] == "git"
      and command[2] == "diff"
      and command[3] == "--no-color"
      and command[4] == "origin/main...HEAD"
    then
      saw_upstream_diff = true
    end

    if type(command) == "table"
      and command[1] == "git"
      and command[2] == "diff"
      and command[3] == "--no-color"
      and command[4] == "HEAD"
    then
      saw_local_diff = true
    end
  end

  assert(saw_upstream_lookup, "Expected upstream lookup fallback")
  assert(saw_upstream_diff, "Expected upstream diff fallback")
  assert(saw_local_diff == false, "Expected upstream fallback to win before local diff")
end

set["session.start falls back to local diff when PR and upstream are unavailable"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select

    local commands = {}
    local diff = [[
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+local-fallback
]]

    local start_result = session.start({
      run_command = function(command)
        table.insert(commands, command)

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 128,
            stdout = "",
            stderr = "fatal: no upstream configured",
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
        return "feature/no-pr"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "no_pr",
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
      repo_root = ".",
    })

    local mode = nil
    local pr_number = nil
    for idx = 1, 40 do
      local upvalue_name, upvalue_value = debug.getupvalue(session.start, idx)
      if upvalue_name == nil then
        break
      end

      if upvalue_name == "current_session" and type(upvalue_value) == "table" then
        mode = upvalue_value.mode
        pr_number = upvalue_value.pr_number
        break
      end
    end

    vim.g.git_review_auto_local_fallback_result = start_result
    vim.g.git_review_auto_local_fallback_commands = commands
    vim.g.git_review_auto_local_fallback_mode = mode
    vim.g.git_review_auto_local_fallback_pr_number_is_nil = pr_number == nil
  ]=])

  local result = child.lua_get([[vim.g.git_review_auto_local_fallback_result]])
  local commands = child.lua_get([[vim.g.git_review_auto_local_fallback_commands]])
  local mode = child.lua_get([[vim.g.git_review_auto_local_fallback_mode]])
  local pr_number_is_nil = child.lua_get([[vim.g.git_review_auto_local_fallback_pr_number_is_nil]])

  assert(type(result) == "table" and type(result.hunks) == "table", "Expected local fallback start result")
  assert(result.auto_fallback == true, "Expected local fallback metadata")
  assert(result.source == "local", "Expected local fallback source metadata")
  assert(mode == "local", "Expected automatic local fallback to set local mode when opts.mode is nil")
  assert(pr_number_is_nil == true, "Expected automatic local fallback to keep PR metadata unset")

  local saw_local_diff = false
  for _, command in ipairs(commands) do
    if type(command) == "table"
      and command[1] == "git"
      and command[2] == "diff"
      and command[3] == "--no-color"
      and command[4] == "HEAD"
    then
      saw_local_diff = true
      break
    end
  end

  assert(saw_local_diff == true, "Expected automatic local fallback diff command")
end

set["session.start reports actionable error when PR and upstream are unavailable and local diff is empty"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select

    local ok, err = pcall(session.start, {
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 128,
            stdout = "",
            stderr = "fatal: no upstream configured",
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
          code = 1,
          stdout = "",
          stderr = "unexpected command",
        }
      end,
      resolve_branch = function(_)
        return "feature/no-pr"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "no_pr",
        }
      end,
    })

    local is_active = session.is_active()

    vim.g.git_review_auto_local_empty_ok = ok
    vim.g.git_review_auto_local_empty_error = err
    vim.g.git_review_auto_local_empty_active = is_active
  ]=])

  local ok = child.lua_get([[vim.g.git_review_auto_local_empty_ok]])
  local err = child.lua_get([[vim.g.git_review_auto_local_empty_error]])
  local is_active = child.lua_get([[vim.g.git_review_auto_local_empty_active]])

  assert(ok == false, "Expected start to fail when no PR/upstream and local diff is empty")
  assert(type(err) == "string" and string.find(err, "no pull request", 1, true), "Expected no PR mention in error")
  assert(type(err) == "string" and string.find(err, "no upstream", 1, true), "Expected no upstream mention in error")
  assert(
    type(err) == "string" and string.find(err, "no local tracked changes", 1, true),
    "Expected no local tracked changes mention in error"
  )
  assert(is_active == false, "Expected start failure to avoid creating a session")
end

set["session.refresh stays usable for automatic local fallback sessions"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select

    local diff = [[
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+local-fallback-refresh
]]

    local diff_calls = 0
    local resolve_pr_calls = 0

    local function run_command(command)
      if type(command) == "table"
        and command[1] == "git"
        and command[2] == "rev-parse"
        and command[3] == "--abbrev-ref"
        and command[4] == "--symbolic-full-name"
        and command[5] == "@{upstream}"
      then
        return {
          code = 128,
          stdout = "",
          stderr = "fatal: no upstream configured",
        }
      end

      if type(command) == "table"
        and command[1] == "git"
        and command[2] == "diff"
        and command[3] == "--no-color"
        and command[4] == "HEAD"
      then
        diff_calls = diff_calls + 1
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
    end

    local start_result = session.start({
      run_command = run_command,
      resolve_branch = function(_)
        return "feature/no-pr"
      end,
      resolve_pr_for_branch = function(_)
        resolve_pr_calls = resolve_pr_calls + 1
        return {
          state = "no_pr",
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
      repo_root = ".",
    })

    local refresh_result = session.refresh()

    local auto_fallback = nil
    local mode = nil
    for idx = 1, 40 do
      local upvalue_name, upvalue_value = debug.getupvalue(session.start, idx)
      if upvalue_name == nil then
        break
      end

      if upvalue_name == "current_session" and type(upvalue_value) == "table" then
        auto_fallback = upvalue_value.auto_fallback
        mode = upvalue_value.mode
        break
      end
    end

    vim.g.git_review_auto_local_refresh_start_result = start_result
    vim.g.git_review_auto_local_refresh_result = refresh_result
    vim.g.git_review_auto_local_refresh_diff_calls = diff_calls
    vim.g.git_review_auto_local_refresh_pr_calls = resolve_pr_calls
    vim.g.git_review_auto_local_refresh_mode = mode
    vim.g.git_review_auto_local_refresh_auto_fallback = auto_fallback
  ]=])

  local start_result = child.lua_get([[vim.g.git_review_auto_local_refresh_start_result]])
  local refresh_result = child.lua_get([[vim.g.git_review_auto_local_refresh_result]])
  local diff_calls = child.lua_get([[vim.g.git_review_auto_local_refresh_diff_calls]])
  local resolve_pr_calls = child.lua_get([[vim.g.git_review_auto_local_refresh_pr_calls]])
  local mode = child.lua_get([[vim.g.git_review_auto_local_refresh_mode]])
  local auto_fallback = child.lua_get([[vim.g.git_review_auto_local_refresh_auto_fallback]])

  assert(type(start_result) == "table" and start_result.auto_fallback == true, "Expected automatic local fallback start")
  assert(type(refresh_result) == "table" and refresh_result.state == "ok", "Expected refresh to succeed in automatic local fallback mode")
  assert(type(refresh_result.hunks) == "table", "Expected refreshed local fallback hunks")
  assert(diff_calls == 2, "Expected refresh to rerun the local diff command")
  assert(resolve_pr_calls == 1, "Expected automatic local fallback refresh to avoid repeated PR lookups")
  assert(mode == "local", "Expected automatic local fallback session mode to stay local after refresh")
  assert(auto_fallback == true, "Expected automatic local fallback state to persist across refresh")
end

set["session.start surfaces local diff command errors during automatic fallback"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local ok, err = pcall(session.start, {
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 128,
            stdout = "",
            stderr = "fatal: no upstream configured",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "HEAD"
        then
          return {
            code = 1,
            stdout = "",
            stderr = "fatal: local diff failed",
          }
        end

        return {
          code = 1,
          stdout = "",
          stderr = "unexpected command",
        }
      end,
      resolve_branch = function(_)
        return "feature/no-pr"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "no_pr",
        }
      end,
    })

    vim.g.git_review_range_error_ok = ok
    vim.g.git_review_range_error_message = err
  ]])

  local ok = child.lua_get([[vim.g.git_review_range_error_ok]])
  local err = child.lua_get([[vim.g.git_review_range_error_message]])

  assert(ok == false, "Expected session.start to fail when automatic local fallback diff fails")
  assert(string.find(err, "fatal: local diff failed", 1, true), "Expected local diff failure message")
end

set["session.start keeps upstream ref as a single diff argv argument"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local x = 1
 ]]

    local commands = {}
    vim.g.git_review_start_state = session.start({
      run_command = function(command)
        table.insert(commands, command)

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main;echo injected\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main;echo injected...HEAD"
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
    })

    vim.g.git_review_commands = commands
  ]=])

  local commands = child.lua_get([[vim.g.git_review_commands]])

  local saw_injected_upstream_diff = false
  for _, command in ipairs(commands) do
    if type(command) == "table"
      and command[1] == "git"
      and command[2] == "diff"
      and command[3] == "--no-color"
      and command[4] == "origin/main;echo injected...HEAD"
    then
      saw_injected_upstream_diff = true
    end
  end

  assert(saw_injected_upstream_diff, "Expected upstream range to stay in one argv token")
end

set["session.start fetches thread panel on start without navigation refetch"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local x = 1
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+thread-refresh
 ]]

    local fetch_calls = 0
    local render_calls = 0

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/task-6"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42 },
        }
      end,
      fetch_review_threads = function(_)
        fetch_calls = fetch_calls + 1
        return {
          state = "ok",
          threads = {
            { author = "octocat", body = "Looks good" },
          },
        }
      end,
      panel = {
        render = function(_)
          render_calls = render_calls + 1
        end,
      },
    })

    local loc_items = vim.fn.getloclist(0)
    if #loc_items > 1 then
      vim.cmd("lfirst")
      vim.cmd("lnext")
    end

    vim.g.git_review_thread_fetch_calls = fetch_calls
    vim.g.git_review_panel_render_calls = render_calls
  ]=])

  local fetch_calls = child.lua_get([[vim.g.git_review_thread_fetch_calls]])
  local render_calls = child.lua_get([[vim.g.git_review_panel_render_calls]])

  assert(fetch_calls == 1, "Expected thread fetch on start only")
  assert(render_calls == 1, "Expected panel render on start only")
end

set["session.start defers initial thread refresh until scheduled callback"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local x = 1
 ]]

    local fetch_calls = 0
    local scheduled = {}
    local original_schedule = vim.schedule
    vim.schedule = function(fn)
      table.insert(scheduled, fn)
    end

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/defer-thread-refresh"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
        }
      end,
      fetch_review_threads = function(_)
        fetch_calls = fetch_calls + 1
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

    local fetch_before = fetch_calls
    for _, callback in ipairs(scheduled) do
      callback()
    end
    local fetch_after = fetch_calls

    vim.schedule = original_schedule

    vim.g.git_review_deferred_thread_fetch_before = fetch_before
    vim.g.git_review_deferred_thread_fetch_after = fetch_after
  ]=])

  local fetch_before = child.lua_get([[vim.g.git_review_deferred_thread_fetch_before]])
  local fetch_after = child.lua_get([[vim.g.git_review_deferred_thread_fetch_after]])

  assert(fetch_before == 0, "Expected session.start to defer initial thread fetch")
  assert(fetch_after == 1, "Expected deferred callback to perform exactly one thread fetch")
end

set["session.start reuses PR lookup for deferred thread refresh"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local x = 1
 ]]

    local pr_lookup_calls = 0
    local scheduled = {}
    local original_schedule = vim.schedule
    vim.schedule = function(fn)
      table.insert(scheduled, fn)
    end

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/reuse-pr"
      end,
      resolve_pr_for_branch = function(_)
        pr_lookup_calls = pr_lookup_calls + 1
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
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
      defer_thread_refresh = true,
    })

    for _, callback in ipairs(scheduled) do
      callback()
    end

    vim.schedule = original_schedule

    vim.g.git_review_pr_lookup_call_count = pr_lookup_calls
  ]=])

  local pr_lookup_calls = child.lua_get([[vim.g.git_review_pr_lookup_call_count]])
  assert(pr_lookup_calls == 1, "Expected session.start to reuse initial PR lookup for deferred thread refresh")
end

set["session.toggle_resolved_thread_visibility rerenders from cached threads and keeps panel cursor"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])
  child.lua([[package.loaded["git-review.ui.panel"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    local panel = require("git-review.ui.panel")
    vim.ui.select = _G.git_review_test_auto_select
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local x = 1
 ]]

    local fetch_calls = 0
    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/toggle-resolved"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
        }
      end,
      fetch_review_threads = function(_)
        fetch_calls = fetch_calls + 1
        return {
          state = "ok",
          threads = {
            {
              id = "resolved-1",
              isResolved = true,
              comments = {
                { author = "octocat", body = "Resolved body should toggle" },
              },
            },
            {
              id = "open-1",
              isResolved = false,
              comments = {
                { author = "hubot", body = "Open body stays visible" },
              },
            },
          },
        }
      end,
      panel = panel,
      open_panel_on_start = true,
    })

    local panel_target = panel.open({})
    local winid = panel_target.winid
    local cursor_before = vim.api.nvim_win_get_cursor(winid)
    if cursor_before[1] < 2 then
      vim.api.nvim_win_set_cursor(winid, { 2, 0 })
    end

    local fixed_cursor = vim.api.nvim_win_get_cursor(winid)
    local bufnr = panel_target.bufnr
    local before_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local toggle_result = session.toggle_resolved_thread_visibility()

    local panel_target_after = panel.open({})
    local cursor_after = vim.api.nvim_win_get_cursor(panel_target_after.winid)
    local after_lines = vim.api.nvim_buf_get_lines(panel_target_after.bufnr, 0, -1, false)

    vim.g.git_review_toggle_threads_fetch_calls = fetch_calls
    vim.g.git_review_toggle_threads_result = toggle_result
    vim.g.git_review_toggle_threads_cursor_before = fixed_cursor[1]
    vim.g.git_review_toggle_threads_cursor_after = cursor_after[1]
    vim.g.git_review_toggle_threads_panel_open = panel.is_open()
    vim.g.git_review_toggle_threads_before_lines = before_lines
    vim.g.git_review_toggle_threads_after_lines = after_lines
  ]=])

  local fetch_calls = child.lua_get([[vim.g.git_review_toggle_threads_fetch_calls or 0]])
  local toggle_result = child.lua_get([[vim.g.git_review_toggle_threads_result]])
  local cursor_before = child.lua_get([[vim.g.git_review_toggle_threads_cursor_before or 0]])
  local cursor_after = child.lua_get([[vim.g.git_review_toggle_threads_cursor_after or 0]])
  local panel_open = child.lua_get([[vim.g.git_review_toggle_threads_panel_open]])
  local before_lines = child.lua_get([[vim.g.git_review_toggle_threads_before_lines]])
  local after_lines = child.lua_get([[vim.g.git_review_toggle_threads_after_lines]])

  local saw_collapsed_before = false
  for _, line in ipairs(before_lines or {}) do
    if line == "> (resolved thread collapsed)" then
      saw_collapsed_before = true
      break
    end
  end

  local saw_resolved_body_after = false
  for _, line in ipairs(after_lines or {}) do
    if string.find(line, "Resolved body should toggle", 1, true) then
      saw_resolved_body_after = true
      break
    end
  end

  assert(type(toggle_result) == "table", "Expected toggle result table")
  assert(toggle_result.state == "ok", "Expected toggle_resolved_thread_visibility success")
  assert(fetch_calls == 1, "Expected toggle to rerender without refetching threads")
  assert(panel_open == true, "Expected panel to remain open after toggle")
  assert(cursor_after == cursor_before, "Expected panel cursor line to be preserved")
  assert(saw_collapsed_before == true, "Expected resolved thread to be collapsed before toggle")
  assert(saw_resolved_body_after == true, "Expected resolved thread body to be visible after toggle")
end

set["session.start keeps comments panel closed by default"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,1 +1,2 @@
 local M = {}
+local x = 1
@@ -10,1 +11,2 @@
 return M
+local y = 2
 ]]

    local panel_open_value = nil
    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/task-panel-default"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
        }
      end,
      fetch_review_threads = function(_)
        return {
          state = "ok",
          threads = {},
        }
      end,
      panel = {
        render = function(_, render_opts)
          panel_open_value = render_opts and render_opts.open
        end,
      },
    })

    vim.g.git_review_panel_open_on_start = panel_open_value
  ]=])

  local panel_open_value = child.lua_get([[vim.g.git_review_panel_open_on_start]])
  assert(panel_open_value == false, "Expected comments panel to stay closed on session.start")
end

set["session.start optionally auto-opens PR info based on config"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local config = require("git-review.config")
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local x = 1
 ]]

    local open_pr_info_calls = 0
    config.setup({
      open_pr_info_on_start = true,
      open_comments_panel_on_start = false,
    })

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/task-pr-info-on-start"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
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
      open_pr_info = function(_)
        open_pr_info_calls = open_pr_info_calls + 1
        return {
          state = "ok",
        }
      end,
    })

    config.setup({})
    vim.g.git_review_open_pr_info_calls_on_start = open_pr_info_calls
  ]=])

  local calls = child.lua_get([[vim.g.git_review_open_pr_info_calls_on_start or 0]])
  assert(calls == 1, "Expected PR info view to open once when config enables it")
end

set["session.start logs PR info auto-open failures to debug log"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local config = require("git-review.config")
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local x = 1
 ]]

    local logs = {}
    config.setup({
      open_pr_info_on_start = true,
      open_comments_panel_on_start = false,
    })

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/task-pr-info-log"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
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
      open_pr_info = function(_)
        return {
          state = "context_error",
          message = "mock info failure",
        }
      end,
      debug_log = function(message)
        table.insert(logs, message)
      end,
    })

    config.setup({})
    vim.g.git_review_pr_info_auto_open_logs = logs
  ]=])

  local logs = child.lua_get([[vim.g.git_review_pr_info_auto_open_logs]])
  assert(type(logs) == "table", "Expected logs table")

  local saw_failure_log = false
  for _, message in ipairs(logs) do
    if string.find(message, "auto-open PR info returned state", 1, true)
      and string.find(message, "mock info failure", 1, true)
    then
      saw_failure_log = true
      break
    end
  end

  assert(saw_failure_log, "Expected debug log to capture PR info auto-open failure")
end

set["session.start renders active hunk highlight after quickfix population"] = function()
  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local x = 1
 ]]

    local highlight_calls = 0

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/task-highlight"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
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
      hunk_highlight = {
        render_current_hunk = function(_)
          highlight_calls = highlight_calls + 1
        end,
      },
      repo = "max-farver/git-review.nvim",
      commit_id = "abc123",
      repo_root = ".",
    })

    vim.g.git_review_highlight_calls_on_start = highlight_calls
  ]=])

  local calls = child.lua_get([[vim.g.git_review_highlight_calls_on_start or 0]])
  assert(calls >= 1, "Expected active hunk highlight render on session.start")
end

set["session.start refresh hook updates active hunk highlight"] = function()
  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,1 +1,2 @@
 local M = {}
+local x = 1
@@ -10,1 +11,2 @@
 return M
+local y = 2
 ]]

    local highlight_calls = 0

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/task-highlight"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
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
      hunk_highlight = {
        render_current_hunk = function(_)
          highlight_calls = highlight_calls + 1
        end,
      },
      repo = "max-farver/git-review.nvim",
      commit_id = "abc123",
      repo_root = ".",
    })

    vim.cmd("llast")
    vim.cmd("normal! j")
    vim.g.git_review_highlight_calls_with_refresh = highlight_calls
  ]=])

  local calls = child.lua_get([[vim.g.git_review_highlight_calls_with_refresh or 0]])
  assert(calls >= 1, "Expected active hunk highlight render during start and refresh flow")
end

set["session.start refresh hook ignores unrelated quickfix context"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local x = 1
 ]]

    local fetch_calls = 0

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/task-6"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42 },
        }
      end,
      fetch_review_threads = function(_)
        fetch_calls = fetch_calls + 1
        return {
          state = "ok",
          threads = {
            { author = "octocat", body = "Looks good" },
          },
        }
      end,
      panel = {
        render = function(_) end,
      },
    })

    vim.fn.setqflist({}, " ", {
      title = "Unrelated quickfix",
      items = {
        {
          filename = "README.md",
          lnum = 1,
          col = 1,
          text = "placeholder",
        },
        {
          filename = "lua/git-review/init.lua",
          lnum = 1,
          col = 1,
          text = "placeholder 2",
        },
      },
    })

    local loc_items = vim.fn.getloclist(0)
    if #loc_items > 1 then
      vim.cmd("lfirst")
      vim.cmd("lnext")
    end

    vim.g.git_review_thread_fetch_calls = fetch_calls
  ]=])

  local fetch_calls = child.lua_get([[vim.g.git_review_thread_fetch_calls]])

  assert(fetch_calls == 1, "Expected refresh hook to ignore unrelated quickfix usage")
end

set["session.start failure clears prior session context"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -10,2 +10,3 @@
 local M = {}
+local x = 1
 return M
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+refresh-me
]]

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

    local start_ok, start_err = pcall(session.start, {
      diff_command = { "git", "diff", "--no-color", "origin/main...HEAD" },
      run_command = function(_)
        return {
          code = 1,
          stdout = "",
          stderr = "forced diff failure",
        }
      end,
    })

    local calls = 0
    local result = session.create_comment({
      body = "stale session should not be reused",
      repo = "acme/repo",
      pr_number = 42,
      commit_id = "abc123",
      context = {
        path = "lua/git-review/init.lua",
        start_line = 11,
      },
      create_review_comment = function(comment)
        calls = calls + 1
        return {
          state = "ok",
          comment = comment,
        }
      end,
    })

    vim.g.git_review_stale_start_ok = start_ok
    vim.g.git_review_stale_start_err = start_err
    vim.g.git_review_stale_comment_result = result
    vim.g.git_review_stale_comment_calls = calls
  ]=])

  local start_ok = child.lua_get([[vim.g.git_review_stale_start_ok]])
  local start_err = child.lua_get([[vim.g.git_review_stale_start_err]])
  local comment_result = child.lua_get([[vim.g.git_review_stale_comment_result]])
  local calls = child.lua_get([[vim.g.git_review_stale_comment_calls]])

  assert(start_ok == false, "Expected second session.start call to fail")
  assert(type(start_err) == "string", "Expected start failure error")
  assert(type(comment_result) == "table", "Expected create_comment result")
  assert(comment_result.state == "context_error", "Expected missing diff context after failed start")
  assert(comment_result.message == "No diff text available for position mapping", "Expected no stale diff reuse")
  assert(calls == 0, "Expected create_review_comment not to be called")
end

set["session.start refresh invalidates stale pr_number after non-ok thread refresh"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local phase = "ok"
    local create_calls = 0
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -10,2 +10,3 @@
 local M = {}
+local x = 1
 return M
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+refresh-me
]]

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
        return "feature/task-9"
      end,
      resolve_pr_for_branch = function(_, _)
        if phase == "ok" then
          return {
            state = "single_pr",
            pr = { number = 42 },
          }
        end

        return {
          state = "no_pr",
          message = "No pull request found for current branch",
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

    phase = "no_pr"
    local loc_items = vim.fn.getloclist(0)
    if #loc_items > 1 then
      vim.cmd("lfirst")
      vim.cmd("lnext")
    end

    local result = session.create_comment({
      body = "line-level note",
      repo = "acme/repo",
      commit_id = "abc123",
      context = {
        path = "lua/git-review/init.lua",
        start_line = 11,
      },
      create_review_comment = function(_)
        create_calls = create_calls + 1
        return { state = "ok" }
      end,
    })

    vim.g.git_review_non_ok_refresh_comment_result = result
    vim.g.git_review_non_ok_refresh_comment_calls = create_calls
  ]=])

  local result = child.lua_get([[vim.g.git_review_non_ok_refresh_comment_result]])
  local calls = child.lua_get([[vim.g.git_review_non_ok_refresh_comment_calls]])

  assert(type(result) == "table", "Expected create_comment result")
  assert(result.state == "context_error", "Expected context_error result after non-ok refresh")
  assert(result.message == "pr_number is required to create comments", "Expected stale pr_number to be invalidated")
  assert(calls == 0, "Expected create_review_comment not to be called")
end

set["session.refresh re-resolves commit_id for comment creation"] = function()
  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local head_commit = "old-commit"
    local captured_payload
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

    local function run_command(command)
      if type(command) == "table"
        and command[1] == "git"
        and command[2] == "rev-parse"
        and command[3] == "HEAD"
      then
        return {
          code = 0,
          stdout = head_commit .. "\n",
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
    end

    local start_result = session.start({
      diff_command = { "git", "diff", "--no-color", "origin/main...HEAD" },
      run_command = run_command,
      resolve_branch = function(_)
        return "feature/task-10"
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

    head_commit = "new-commit"

    local refresh_result = session.refresh()
    local comment_result = session.create_comment({
      body = "line-level note",
      repo = "acme/repo",
      context = {
        path = "lua/git-review/init.lua",
        start_line = 11,
      },
      create_review_comment = function(payload)
        captured_payload = payload
        return {
          state = "ok",
        }
      end,
    })

    vim.g.git_review_commit_refresh_start_result = start_result
    vim.g.git_review_commit_refresh_result = refresh_result
    vim.g.git_review_commit_refresh_comment_result = comment_result
    vim.g.git_review_commit_refresh_payload = captured_payload
  ]=])

  local start_result = child.lua_get([[vim.g.git_review_commit_refresh_start_result]])
  local refresh_result = child.lua_get([[vim.g.git_review_commit_refresh_result]])
  local comment_result = child.lua_get([[vim.g.git_review_commit_refresh_comment_result]])
  local payload = child.lua_get([[vim.g.git_review_commit_refresh_payload]])

  assert(type(start_result) == "table", "Expected start result")
  assert(type(refresh_result) == "table", "Expected refresh result")
  assert(refresh_result.state == "ok", "Expected refresh success")
  assert(type(comment_result) == "table", "Expected comment result")
  assert(comment_result.state == "ok", "Expected create_comment success")
  assert(type(payload) == "table", "Expected comment payload")
  assert(payload.commit_id == "new-commit", "Expected refreshed HEAD commit_id in payload")
end

set["session.open_pr_info renders using current session PR metadata"] = function()
  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local x = 1
 ]]

    local resolve_pr_calls = 0
    local rendered_pr

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/task-pr-info"
      end,
      resolve_pr_for_branch = function(_)
        resolve_pr_calls = resolve_pr_calls + 1
        return {
          state = "single_pr",
          pr = {
            number = 42,
            title = "Task 2",
            body = "Adds PR info view",
            url = "https://github.com/acme/repo/pull/42",
            baseRefName = "main",
            headRefName = "feature/task-pr-info",
            author = { login = "octocat" },
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
    })

    local resolve_pr_calls_before_open = resolve_pr_calls

    local open_result = session.open_pr_info({
      render_pr_info = function(pr, _)
        rendered_pr = pr
        return {
          bufnr = 7,
          winid = 9,
        }
      end,
    })

    vim.g.git_review_pr_info_session_result = open_result
    vim.g.git_review_pr_info_session_rendered_pr = rendered_pr
    vim.g.git_review_pr_info_session_resolve_pr_calls_before_open = resolve_pr_calls_before_open
    vim.g.git_review_pr_info_session_resolve_pr_calls_after_open = resolve_pr_calls
  ]=])

  local result = child.lua_get([[vim.g.git_review_pr_info_session_result]])
  local rendered_pr = child.lua_get([[vim.g.git_review_pr_info_session_rendered_pr]])
  local resolve_pr_calls_before_open = child.lua_get([[vim.g.git_review_pr_info_session_resolve_pr_calls_before_open or 0]])
  local resolve_pr_calls_after_open = child.lua_get([[vim.g.git_review_pr_info_session_resolve_pr_calls_after_open or 0]])

  assert(type(result) == "table", "Expected open_pr_info result")
  assert(result.state == "ok", "Expected open_pr_info success")
  assert(type(rendered_pr) == "table", "Expected rendered PR metadata")
  assert(rendered_pr.number == 42, "Expected rendered PR number")
  assert(rendered_pr.title == "Task 2", "Expected rendered PR title")
  assert(resolve_pr_calls_before_open == 1, "Expected single PR lookup during session.start")
  assert(
    resolve_pr_calls_after_open == resolve_pr_calls_before_open,
    "Expected open_pr_info to reuse session PR metadata"
  )
end

set["session.open_pr_info resolves PR metadata when session is unavailable"] = function()
  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    session.stop()

    local rendered_pr
    local resolve_pr_calls = 0

    local result = session.open_pr_info({
      run_command = function(_)
        return {
          code = 0,
          stdout = "",
          stderr = "",
        }
      end,
      resolve_branch = function(_)
        return "feature/task-pr-info"
      end,
      resolve_pr_for_branch = function(branch, _)
        resolve_pr_calls = resolve_pr_calls + 1
        if branch ~= "feature/task-pr-info" then
          error("unexpected branch")
        end

        return {
          state = "single_pr",
          pr = {
            number = 42,
            title = "Task 2",
            body = "Adds PR info view",
            url = "https://github.com/acme/repo/pull/42",
            baseRefName = "main",
            headRefName = "feature/task-pr-info",
            author = { login = "octocat" },
          },
        }
      end,
      render_pr_info = function(pr, _)
        rendered_pr = pr
      end,
    })

    vim.g.git_review_pr_info_no_session_result = result
    vim.g.git_review_pr_info_no_session_rendered_pr = rendered_pr
    vim.g.git_review_pr_info_no_session_resolve_pr_calls = resolve_pr_calls
  ]=])

  local result = child.lua_get([[vim.g.git_review_pr_info_no_session_result]])
  local rendered_pr = child.lua_get([[vim.g.git_review_pr_info_no_session_rendered_pr]])
  local resolve_pr_calls = child.lua_get([[vim.g.git_review_pr_info_no_session_resolve_pr_calls or 0]])

  assert(type(result) == "table", "Expected open_pr_info result")
  assert(result.state == "ok", "Expected open_pr_info success")
  assert(type(rendered_pr) == "table", "Expected rendered PR metadata")
  assert(rendered_pr.number == 42, "Expected rendered PR number")
  assert(rendered_pr.baseRefName == "main", "Expected rendered PR base branch")
  assert(resolve_pr_calls == 1, "Expected PR lookup for open_pr_info")
end

set[":GitReview diff shows unknown-subcommand guidance"] = function()
  child.lua([[
    local original_notify = vim.notify
    vim.g.git_review_notify_message = nil
    vim.g.git_review_notify_level = nil

    package.loaded["git-review.session"] = {
      is_active = function()
        return true
      end,
    }

    vim.notify = function(message, level)
      vim.g.git_review_notify_message = message
      vim.g.git_review_notify_level = level
    end

    require("git-review").setup()
    vim.cmd("GitReview diff")

    vim.notify = original_notify
  ]])

  local notify_message = child.lua_get([[vim.g.git_review_notify_message]])
  local notify_level = child.lua_get([[vim.g.git_review_notify_level]])
  assert(type(notify_message) == "string", "Expected notify message for unknown subcommand")
  assert(string.find(notify_message, "unknown subcommand 'diff'", 1, true), "Expected unknown diff guidance")
  assert(notify_level == vim.log.levels.ERROR, "Expected error-level notify for unknown subcommand")
end

set["legacy diff command is not registered"] = function()
  child.lua([[
    require("git-review").setup()
    vim.g.git_review_diff_exists = vim.fn.exists(":GitReviewDiff")
  ]])

  local diff_exists = child.lua_get([[vim.g.git_review_diff_exists]])
  assert(diff_exists == 0, "Expected no :GitReviewDiff command")
end

set["session.stop clears review quickfix and highlight state"] = function()
  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local x = 1
 ]]

    local highlight_clear_calls = 0
    local file_hunk_clear_calls = 0
    local deletion_clear_calls = 0

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/task-stop"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
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
      hunk_highlight = {
        render_current_hunk = function(_) end,
        clear = function(_)
          highlight_clear_calls = highlight_clear_calls + 1
        end,
        clear_all_file_hunks = function()
          file_hunk_clear_calls = file_hunk_clear_calls + 1
        end,
        clear_all_deletions = function()
          deletion_clear_calls = deletion_clear_calls + 1
        end,
      },
      repo = "max-farver/git-review.nvim",
      commit_id = "abc123",
      repo_root = ".",
    })

    local stop_result = session.stop()
    vim.g.git_review_stop_result = stop_result
    vim.g.git_review_stop_highlight_clear_calls = highlight_clear_calls
    vim.g.git_review_stop_file_hunk_clear_calls = file_hunk_clear_calls
    vim.g.git_review_stop_deletion_clear_calls = deletion_clear_calls
    vim.g.git_review_stop_quickfix_items = #vim.fn.getqflist()
    vim.g.git_review_stop_quickfix_title = vim.fn.getqflist({ title = 1 }).title
  ]=])

  local result = child.lua_get([[vim.g.git_review_stop_result]])
  local clear_calls = child.lua_get([[vim.g.git_review_stop_highlight_clear_calls or 0]])
  local file_hunk_clear_calls = child.lua_get([[vim.g.git_review_stop_file_hunk_clear_calls or 0]])
  local deletion_clear_calls = child.lua_get([[vim.g.git_review_stop_deletion_clear_calls or 0]])
  local qf_items = child.lua_get([[vim.g.git_review_stop_quickfix_items]])
  local qf_title = child.lua_get([[vim.g.git_review_stop_quickfix_title]])

  assert(type(result) == "table" and result.state == "ok", "Expected session.stop success result")
  assert(clear_calls == 1, "Expected session.stop to clear hunk highlights")
  assert(file_hunk_clear_calls == 1, "Expected session.stop to clear passive file hunk highlights")
  assert(deletion_clear_calls == 1, "Expected session.stop to clear deletion ghost highlights")
  assert(qf_items == 0, "Expected session.stop to clear review quickfix entries")
  assert(qf_title == "Git Review Files", "Expected session.stop to preserve file-level quickfix title")
end

set["session.stop clears review loclist in review source window when stop runs elsewhere"] = function()
  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local repo_root = vim.fs.normalize(vim.fn.getcwd())
    local abs_readme = vim.fs.normalize(repo_root .. "/README.md")
    local diff = [[
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+x
@@ -10,1 +11,2 @@
 text
+y
 ]]

    vim.cmd("edit " .. abs_readme)
    local review_win = vim.api.nvim_get_current_win()

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/task-stop-loclist"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
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
      repo_root = repo_root,
    })

    vim.cmd("vsplit")
    local other_win = vim.api.nvim_get_current_win()

    vim.g.git_review_stop_loclist_before = #vim.fn.getloclist(review_win)
    vim.g.git_review_stop_other_loclist_before = #vim.fn.getloclist(other_win)
    vim.g.git_review_stop_review_winid = review_win
    vim.g.git_review_stop_other_winid = other_win
    session.stop()
    vim.g.git_review_stop_loclist_after = #vim.fn.getloclist(review_win)
    vim.g.git_review_stop_other_loclist_after = #vim.fn.getloclist(other_win)
  ]=])

  local loclist_before = child.lua_get([[vim.g.git_review_stop_loclist_before or 0]])
  local other_loclist_before = child.lua_get([[vim.g.git_review_stop_other_loclist_before or 0]])
  local loclist_after = child.lua_get([[vim.g.git_review_stop_loclist_after or 0]])
  local other_loclist_after = child.lua_get([[vim.g.git_review_stop_other_loclist_after or 0]])
  local review_winid = child.lua_get([[vim.g.git_review_stop_review_winid or 0]])
  local other_winid = child.lua_get([[vim.g.git_review_stop_other_winid or 0]])

  assert(loclist_before == 2, "Expected session.start to seed loclist before stop")
  assert(review_winid ~= other_winid, "Expected stop to run from a different window")
  assert(other_loclist_before >= 0, "Expected stop window loclist to be readable")
  assert(loclist_after == 0, "Expected session.stop to clear review source window loclist")
  assert(other_loclist_after >= 0, "Expected stop window loclist to remain valid")
end

set["session.stop falls back to current window loclist when review source window is invalid"] = function()
  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local repo_root = vim.fs.normalize(vim.fn.getcwd())
    local abs_readme = vim.fs.normalize(repo_root .. "/README.md")
    local diff = [[
diff --git a/README.md b/README.md
index 1111111..2222222 100644
--- a/README.md
+++ b/README.md
@@ -1,1 +1,2 @@
 # git-review.nvim
+x
 ]]

    vim.cmd("edit " .. abs_readme)
    local review_win = vim.api.nvim_get_current_win()

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/task-stop-loclist-fallback"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
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
      repo_root = repo_root,
    })

    vim.cmd("vsplit")
    local stop_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_close(review_win, true)

    vim.fn.setloclist(stop_win, {}, " ", {
      title = "Temporary Loclist",
      items = {
        {
          filename = abs_readme,
          lnum = 1,
          text = "temp",
        },
      },
    })

    vim.g.git_review_stop_fallback_loclist_before = #vim.fn.getloclist(stop_win)
    session.stop()
    vim.g.git_review_stop_fallback_loclist_after = #vim.fn.getloclist(stop_win)
  ]=])

  local before = child.lua_get([[vim.g.git_review_stop_fallback_loclist_before or 0]])
  local after = child.lua_get([[vim.g.git_review_stop_fallback_loclist_after or 0]])

  assert(before == 1, "Expected current window loclist entries before stop fallback")
  assert(after == 0, "Expected session.stop fallback to clear current window loclist")
end

set["session.stop clears review refresh hook side effects"] = function()
  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local x = 1
 ]]

    local fetch_calls = 0

    session.start({
      run_command = function(command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "rev-parse"
          and command[3] == "--abbrev-ref"
          and command[4] == "--symbolic-full-name"
          and command[5] == "@{upstream}"
        then
          return {
            code = 0,
            stdout = "origin/main\n",
            stderr = "",
          }
        end

        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
        return "feature/task-stop"
      end,
      resolve_pr_for_branch = function(_)
        return {
          state = "single_pr",
          pr = { number = 42, baseRefName = "main" },
        }
      end,
      fetch_review_threads = function(_)
        fetch_calls = fetch_calls + 1
        return {
          state = "ok",
          threads = {},
        }
      end,
      panel = {
        render = function(_) end,
      },
      hunk_highlight = {
        render_current_hunk = function(_) end,
        clear = function(_) end,
      },
      repo = "max-farver/git-review.nvim",
      commit_id = "abc123",
      repo_root = ".",
    })

    session.stop()
    vim.fn.setqflist({}, " ", {
      title = "Stop Test Quickfix",
      items = {
        {
          filename = "README.md",
          lnum = 1,
          col = 1,
          text = "first",
        },
        {
          filename = "lua/git-review/init.lua",
          lnum = 1,
          col = 1,
          text = "second",
        },
      },
    })
    local loc_items = vim.fn.getloclist(0)
    if #loc_items > 1 then
      vim.cmd("lfirst")
      vim.cmd("lnext")
    end
    vim.g.git_review_stop_fetch_calls = fetch_calls
  ]=])

  local fetch_calls = child.lua_get([[vim.g.git_review_stop_fetch_calls or 0]])
  assert(fetch_calls == 1, "Expected no thread refresh after session.stop")
end

set["session.start cleans previous owned range worktree before replacing session"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = nil

    local commands = {}
    local worktree_add_path = nil
    local worktree_remove_path = nil

    local function run_command(command)
      table.insert(commands, command)

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
          stdout = "range-head\n",
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
      then
        worktree_add_path = command[5]
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
        and command[3] == "remove"
        and command[4] == "--force"
      then
        worktree_remove_path = command[5]
        return {
          code = 0,
          stdout = "",
          stderr = "",
        }
      end

      if type(command) == "table"
        and command[1] == "git"
        and command[2] == "diff"
        and command[3] == "--no-color"
        and command[4] == "origin/main...HEAD"
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
    end

    local start_range_result = session.start_range({
      start_ref = "base/head",
      end_ref = "feature/head",
      run_command = run_command,
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
      repo = "acme/repo",
      commit_id = "range-commit",
      defer_thread_refresh = true,
    })

    local start_result = session.start({
      run_command = run_command,
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
      diff_command = { "git", "diff", "--no-color", "origin/main...HEAD" },
      repo_root = vim.fn.getcwd(),
      repo = "acme/repo",
      commit_id = "head-commit",
      defer_thread_refresh = true,
    })

    local remove_index = nil
    local start_diff_index = nil
    for idx, command in ipairs(commands) do
      if type(command) == "table"
        and command[1] == "git"
        and command[2] == "worktree"
        and command[3] == "remove"
      then
        remove_index = idx
      end

      if type(command) == "table"
        and command[1] == "git"
        and command[2] == "diff"
        and command[3] == "--no-color"
        and command[4] == "origin/main...HEAD"
      then
        start_diff_index = idx
      end
    end

    vim.g.git_review_start_cleanup_range_result = start_range_result
    vim.g.git_review_start_cleanup_start_result = start_result
    vim.g.git_review_start_cleanup_add_path = worktree_add_path
    vim.g.git_review_start_cleanup_remove_path = worktree_remove_path
    vim.g.git_review_start_cleanup_remove_index = remove_index
    vim.g.git_review_start_cleanup_start_diff_index = start_diff_index
  ]=])

  local range_result = child.lua_get([[vim.g.git_review_start_cleanup_range_result]])
  local start_result = child.lua_get([[vim.g.git_review_start_cleanup_start_result]])
  local add_path = child.lua_get([[vim.g.git_review_start_cleanup_add_path]])
  local remove_path = child.lua_get([[vim.g.git_review_start_cleanup_remove_path]])
  local remove_index = child.lua_get([[vim.g.git_review_start_cleanup_remove_index]])
  local start_diff_index = child.lua_get([[vim.g.git_review_start_cleanup_start_diff_index]])

  assert(type(range_result) == "table" and type(range_result.hunks) == "table", "Expected range session start to succeed")
  assert(type(start_result) == "table" and type(start_result.hunks) == "table", "Expected replacement start to succeed")
  assert(type(add_path) == "string" and add_path ~= "", "Expected range start to create worktree path")
  assert(remove_path == add_path, "Expected replacement start to clean up previous owned range worktree")
  assert(type(remove_index) == "number", "Expected replacement start to issue worktree remove command")
  assert(type(start_diff_index) == "number", "Expected replacement start to run its diff command")
  assert(remove_index < start_diff_index, "Expected cleanup before replacement session starts")
end

set["session.refresh retains owned range worktree"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = nil

    local commands = {}

    local function run_command(command)
      table.insert(commands, command)

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
          stdout = "range-head\n",
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
        and command[3] == "remove"
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
    end

    local start_result = session.start_range({
      start_ref = "base/head",
      end_ref = "feature/head",
      run_command = run_command,
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
      repo = "acme/repo",
      commit_id = "range-commit",
      defer_thread_refresh = true,
    })

    local refresh_result = session.refresh()

    local remove_count = 0
    for _, command in ipairs(commands) do
      if type(command) == "table"
        and command[1] == "git"
        and command[2] == "worktree"
        and command[3] == "remove"
      then
        remove_count = remove_count + 1
      end
    end

    vim.g.git_review_range_refresh_start_result = start_result
    vim.g.git_review_range_refresh_result = refresh_result
    vim.g.git_review_range_refresh_remove_count = remove_count
  ]=])

  local start_result = child.lua_get([[vim.g.git_review_range_refresh_start_result]])
  local refresh_result = child.lua_get([[vim.g.git_review_range_refresh_result]])
  local remove_count = child.lua_get([[vim.g.git_review_range_refresh_remove_count]])

  assert(type(start_result) == "table" and type(start_result.hunks) == "table", "Expected range start to succeed before refresh")
  assert(type(refresh_result) == "table", "Expected range refresh to return a result table")
  assert(remove_count == 0, "Expected refresh to retain active owned range worktree")
end

set["session.stop removes owned range worktree"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = nil

    local commands = {}
    local worktree_add_path = nil
    local worktree_remove_path = nil

    local start_result = session.start_range({
      start_ref = "base/head",
      end_ref = "feature/head",
      run_command = function(command)
        table.insert(commands, command)

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
        then
          worktree_add_path = command[5]
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
          and command[3] == "remove"
          and command[4] == "--force"
        then
          worktree_remove_path = command[5]
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
      defer_thread_refresh = true,
    })

    local stop_result = session.stop()

    vim.g.git_review_stop_owned_worktree_start_result = start_result
    vim.g.git_review_stop_owned_worktree_stop_result = stop_result
    vim.g.git_review_stop_owned_worktree_worktree_add_path = worktree_add_path
    vim.g.git_review_stop_owned_worktree_worktree_remove_path = worktree_remove_path
    vim.g.git_review_stop_owned_worktree_commands = commands
  ]=])

  local start_result = child.lua_get([[vim.g.git_review_stop_owned_worktree_start_result]])
  local stop_result = child.lua_get([[vim.g.git_review_stop_owned_worktree_stop_result]])
  local add_path = child.lua_get([[vim.g.git_review_stop_owned_worktree_worktree_add_path]])
  local remove_path = child.lua_get([[vim.g.git_review_stop_owned_worktree_worktree_remove_path]])
  local commands = child.lua_get([[vim.g.git_review_stop_owned_worktree_commands]])

  assert(type(start_result) == "table" and type(start_result.hunks) == "table", "Expected range session start to succeed")
  assert(type(stop_result) == "table" and stop_result.state == "ok", "Expected stop success for owned worktree cleanup")
  assert(type(add_path) == "string" and add_path ~= "", "Expected start_range to create detached worktree path")
  assert(remove_path == add_path, "Expected stop to remove owned worktree path")

  local remove_seen = false
  for _, command in ipairs(commands or {}) do
    if type(command) == "table" and command[1] == "git" and command[2] == "worktree" and command[3] == "remove" then
      remove_seen = true
      break
    end
  end

  assert(remove_seen == true, "Expected stop to run git worktree remove for owned range session")
end

set["session.stop does not remove non-owned worktree path"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = nil

    local commands = {}
    local stop_result = nil
    local start_result = session.start({
      run_command = function(command)
        table.insert(commands, command)
        if type(command) == "table"
          and command[1] == "git"
          and command[2] == "diff"
          and command[3] == "--no-color"
          and command[4] == "origin/main...HEAD"
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
      diff_command = { "git", "diff", "--no-color", "origin/main...HEAD" },
      fetch_review_threads = function(_)
        return {
          state = "ok",
          threads = {},
        }
      end,
      panel = {
        render = function(_) end,
      },
      worktree_path = "/tmp/non-owned-worktree",
      worktree_owned = false,
      defer_thread_refresh = true,
    })

    stop_result = session.stop()
    vim.g.git_review_stop_non_owned_worktree_start_result = start_result
    vim.g.git_review_stop_non_owned_worktree_stop_result = stop_result
    vim.g.git_review_stop_non_owned_worktree_commands = commands
  ]=])

  local start_result = child.lua_get([[vim.g.git_review_stop_non_owned_worktree_start_result]])
  local stop_result = child.lua_get([[vim.g.git_review_stop_non_owned_worktree_stop_result]])
  local commands = child.lua_get([[vim.g.git_review_stop_non_owned_worktree_commands]])

  assert(type(start_result) == "table" and type(start_result.hunks) == "table", "Expected explicit non-owned session start to succeed")
  assert(type(stop_result) == "table" and stop_result.state == "ok", "Expected stop success for non-owned worktree session")

  local remove_seen = false
  for _, command in ipairs(commands or {}) do
    if type(command) == "table" and command[1] == "git" and command[2] == "worktree" and command[3] == "remove" then
      remove_seen = true
      break
    end
  end

  assert(remove_seen == false, "Expected stop to avoid removing non-owned worktree path")
end

set["session.stop reports actionable error when owned worktree cleanup fails"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = nil

    local worktree_add_path = nil

    local start_result = session.start_range({
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
        then
          worktree_add_path = command[5]
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
          and command[3] == "remove"
          and command[4] == "--force"
        then
          return {
            code = 1,
            stdout = "",
            stderr = "permission denied",
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
      defer_thread_refresh = true,
    })

    local ok_stop, stop_result = pcall(session.stop)
    vim.g.git_review_stop_owned_worktree_cleanup_fail_start_result = start_result
    vim.g.git_review_stop_owned_worktree_cleanup_fail_ok = ok_stop
    vim.g.git_review_stop_owned_worktree_cleanup_fail_result = stop_result
    vim.g.git_review_stop_owned_worktree_cleanup_fail_path = worktree_add_path
    vim.g.git_review_stop_owned_worktree_cleanup_fail_active = session.is_active()
  ]=])

  local start_result = child.lua_get([[vim.g.git_review_stop_owned_worktree_cleanup_fail_start_result]])
  local ok_stop = child.lua_get([[vim.g.git_review_stop_owned_worktree_cleanup_fail_ok]])
  local stop_result = child.lua_get([[vim.g.git_review_stop_owned_worktree_cleanup_fail_result]])
  local worktree_path = child.lua_get([[vim.g.git_review_stop_owned_worktree_cleanup_fail_path]])
  local is_active = child.lua_get([[vim.g.git_review_stop_owned_worktree_cleanup_fail_active]])

  assert(type(start_result) == "table" and type(start_result.hunks) == "table", "Expected range session start to succeed before cleanup failure")
  assert(ok_stop == true, "Expected stop to avoid crashing when worktree cleanup fails")
  assert(type(stop_result) == "table" and stop_result.state == "command_error", "Expected stop to surface cleanup command_error")
  assert(type(stop_result.message) == "string" and string.find(stop_result.message, "permission denied", 1, true), "Expected cleanup error detail in stop result")
  assert(type(stop_result.message) == "string" and string.find(stop_result.message, worktree_path, 1, true), "Expected cleanup error to include worktree path")
  assert(is_active == false, "Expected stop to clear active session even when cleanup fails")
end

set["session.start_local defaults to git diff HEAD and local mode"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = nil

    local commands = {}
    local start_result = session.start_local({
      run_command = function(command)
        table.insert(commands, command)

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

    local mode = nil
    for idx = 1, 30 do
      local upvalue_name, upvalue_value = debug.getupvalue(session.start, idx)
      if upvalue_name == nil then
        break
      end

      if upvalue_name == "current_session" and type(upvalue_value) == "table" then
        mode = upvalue_value.mode
        break
      end
    end

    vim.g.git_review_start_local_result = start_result
    vim.g.git_review_start_local_commands = commands
    vim.g.git_review_start_local_mode = mode
  ]=])

  local result = child.lua_get([[vim.g.git_review_start_local_result]])
  local commands = child.lua_get([[vim.g.git_review_start_local_commands]])
  local mode = child.lua_get([[vim.g.git_review_start_local_mode]])

  assert(type(result) == "table" and type(result.hunks) == "table", "Expected start_local to return start result")
  assert(mode == "local", "Expected session mode to be local")

  local diff_seen = false
  for _, command in ipairs(commands or {}) do
    if type(command) == "table" and command[1] == "git" and command[2] == "diff" then
      diff_seen = command[3] == "--no-color" and command[4] == "HEAD"
      if diff_seen then
        break
      end
    end
  end

  assert(diff_seen == true, "Expected start_local default diff command to be git diff --no-color HEAD")
end

set["session.start_branch validates refs and builds branch diff command"] = function()
  child.lua([[package.loaded["git-review.session"] = nil]])

  child.lua([=[
    local session = require("git-review.session")
    vim.ui.select = nil

    local commands = {}
    local start_result = session.start_branch({
      base_ref = "main",
      head_ref = "feature/topic",
      run_command = function(command)
        table.insert(commands, command)

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
          and (command[4] == "main^{commit}" or command[4] == "feature/topic^{commit}")
        then
          return {
            code = 0,
            stdout = "validated\n",
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
          and command[4] == "main...feature/topic"
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

    local mode = nil
    for idx = 1, 30 do
      local upvalue_name, upvalue_value = debug.getupvalue(session.start, idx)
      if upvalue_name == nil then
        break
      end

      if upvalue_name == "current_session" and type(upvalue_value) == "table" then
        mode = upvalue_value.mode
        break
      end
    end

    vim.g.git_review_start_branch_result = start_result
    vim.g.git_review_start_branch_commands = commands
    vim.g.git_review_start_branch_mode = mode
  ]=])

  local result = child.lua_get([[vim.g.git_review_start_branch_result]])
  local commands = child.lua_get([[vim.g.git_review_start_branch_commands]])
  local mode = child.lua_get([[vim.g.git_review_start_branch_mode]])

  assert(type(result) == "table" and type(result.hunks) == "table", "Expected start_branch to return start result")
  assert(mode == "branch", "Expected session mode to be branch")

  local validate_base_seen = false
  local validate_head_seen = false
  local diff_seen = false
  for _, command in ipairs(commands or {}) do
    if type(command) == "table" and command[1] == "git" and command[2] == "rev-parse" and command[3] == "--verify" then
      if command[4] == "main^{commit}" then
        validate_base_seen = true
      elseif command[4] == "feature/topic^{commit}" then
        validate_head_seen = true
      end
    end

    if type(command) == "table" and command[1] == "git" and command[2] == "diff" then
      diff_seen = command[3] == "--no-color" and command[4] == "main...feature/topic"
    end
  end

  assert(validate_base_seen == true, "Expected start_branch to validate base ref")
  assert(validate_head_seen == true, "Expected start_branch to validate head ref")
  assert(diff_seen == true, "Expected start_branch diff command to use base...head")
end

set["session.stop is idempotent without active session"] = function()
  child.lua([[
    local session = require("git-review.session")
    vim.ui.select = _G.git_review_test_auto_select
    local first = session.stop()
    local second = session.stop()

    vim.g.git_review_stop_first = first
    vim.g.git_review_stop_second = second
  ]])

  local first = child.lua_get([[vim.g.git_review_stop_first]])
  local second = child.lua_get([[vim.g.git_review_stop_second]])

  assert(type(first) == "table" and first.state == "ok", "Expected first stop call success")
  assert(type(second) == "table" and second.state == "ok", "Expected second stop call success")
end

return set
