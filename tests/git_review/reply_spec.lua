local T = require("mini.test")

local set = T.new_set()

set["github.reply_to_thread assembles GraphQL request payload"] = function()
  local github = require("git-review.github")
  local captured_request

  local result = github.reply_to_thread("PRRT_kwDOAA", "Thanks for the catch.", function(request)
    captured_request = request
    return {
      code = 0,
      stdout = [[{"data":{"addPullRequestReviewThreadReply":{"comment":{"id":"C_1","body":"Thanks for the catch."}}}}]],
      stderr = "",
    }
  end)

  assert(type(captured_request) == "table", "Expected request table")
  assert(captured_request.method == "POST", "Expected POST request")
  assert(captured_request.path == "graphql", "Expected GraphQL API path")
  assert(type(captured_request.body) == "table", "Expected GraphQL request body")
  assert(type(captured_request.body.query) == "string", "Expected GraphQL mutation query")
  assert(string.find(captured_request.body.query, "addPullRequestReviewThreadReply", 1, true), "Expected reply mutation")
  assert(captured_request.body.variables.input.pullRequestReviewThreadId == "PRRT_kwDOAA", "Expected thread id variable")
  assert(captured_request.body.variables.input.body == "Thanks for the catch.", "Expected reply body variable")

  assert(result.state == "ok", "Expected ok state")
  assert(type(result.reply) == "table", "Expected reply payload")
  assert(result.reply.comment.id == "C_1", "Expected comment id in parsed payload")
end

set["github.reply_to_thread returns command_error on gh failure"] = function()
  local github = require("git-review.github")

  local result = github.reply_to_thread("PRRT_kwDOAA", "Nope", function(_)
    return {
      code = 1,
      stdout = "",
      stderr = "gh: validation failed",
    }
  end)

  assert(result.state == "command_error", "Expected command_error state")
  assert(result.message == "gh: validation failed", "Expected command failure message")
end

set["panel.get_selected_thread_id resolves thread from rendered line"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local bufnr = vim.api.nvim_create_buf(false, true)
  panel.render({
    { id = "T1", comments = { { author = "alice", body = "one" } } },
    { id = "T2", comments = { { author = "bob", body = "two" } } },
  }, { bufnr = bufnr })

  local selected_thread_id = panel.get_selected_thread_id({ bufnr = bufnr, cursor_line = 6 })
  assert(selected_thread_id == "T2", "Expected selected thread id by rendered line")
end

set["panel.get_selected_thread_id returns nil without valid cursor context"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local bufnr = vim.api.nvim_create_buf(false, true)
  panel.render({
    { id = "T1", comments = { { author = "alice", body = "one" } } },
    { id = "T2", comments = { { author = "bob", body = "two" } } },
  }, { bufnr = bufnr })

  local selected_thread_id = panel.get_selected_thread_id({ bufnr = bufnr })
  assert(selected_thread_id == nil, "Expected nil selected thread id without cursor context")
end

set["session.reply_to_selected_thread replies using selected thread id"] = function()
  local session = require("git-review.session")

  local called = 0
  local called_thread_id
  local called_body

  local result = session.reply_to_selected_thread({
    body = "Looks good now.",
    panel = {
      get_selected_thread_id = function()
        return "THREAD_42"
      end,
    },
    reply_to_thread = function(thread_id, body)
      called = called + 1
      called_thread_id = thread_id
      called_body = body
      return {
        state = "ok",
        reply = { comment = { id = "C_2" } },
      }
    end,
  })

  assert(called == 1, "Expected one reply call")
  assert(called_thread_id == "THREAD_42", "Expected selected thread id")
  assert(called_body == "Looks good now.", "Expected reply body")
  assert(result.state == "ok", "Expected successful reply")
end

set["session.reply_to_selected_thread forwards send transport"] = function()
  local session = require("git-review.session")

  local called_send
  local arg_count
  local result = session.reply_to_selected_thread({
    body = "Looks good now.",
    panel = {
      get_selected_thread_id = function()
        return "THREAD_42"
      end,
    },
    send = function(_)
      return {
        code = 0,
        stdout = [[{"data":{"addPullRequestReviewThreadReply":{"comment":{"id":"C_3"}}}}]],
        stderr = "",
      }
    end,
    reply_to_thread = function(...)
      arg_count = select("#", ...)
      local _, _, send = ...
      called_send = send
      return {
        state = "ok",
      }
    end,
  })

  assert(arg_count == 3, "Expected reply_to_thread(thread_id, body, send) contract")
  assert(type(called_send) == "function", "Expected send transport callback")
  assert(result.state == "ok", "Expected successful reply")
end

set["session.reply_to_selected_thread prompts for body when omitted"] = function()
  local session = require("git-review.session")

  local called_body
  local result = session.reply_to_selected_thread({
    panel = {
      get_selected_thread_id = function()
        return "THREAD_99"
      end,
    },
    input = function(_)
      return "prompted reply"
    end,
    reply_to_thread = function(_, body)
      called_body = body
      return {
        state = "ok",
      }
    end,
  })

  assert(result.state == "ok", "Expected successful reply from prompted text")
  assert(called_body == "prompted reply", "Expected prompted reply body")
end

set["session.reply_to_selected_thread returns context_error when no thread selected"] = function()
  local session = require("git-review.session")

  local result = session.reply_to_selected_thread({
    body = "irrelevant",
    panel = {
      get_selected_thread_id = function()
        return nil
      end,
    },
  })

  assert(result.state == "context_error", "Expected context_error state")
  assert(result.message == "No review thread selected", "Expected no thread selected message")
end

set["session.open_panel refreshes latest threads and opens panel"] = function()
  package.loaded["git-review.session"] = nil
  local session = require("git-review.session")

  local fetch_calls = 0
  local panel_render_calls = 0
  local panel_open_flags = {}

  session.start({
    run_command = function(command)
      if type(command) == "table"
        and command[1] == "git"
        and command[2] == "rev-parse"
        and command[3] == "--abbrev-ref"
        and command[4] == "--symbolic-full-name"
        and command[5] == "@{upstream}"
      then
        return { code = 0, stdout = "origin/main\n", stderr = "" }
      end

      if type(command) == "table"
        and command[1] == "git"
        and command[2] == "diff"
        and command[3] == "--no-color"
        and command[4] == "origin/main...HEAD"
      then
        return {
          code = 0,
          stdout = "diff --git a/a.lua b/a.lua\n--- a/a.lua\n+++ b/a.lua\n@@ -1 +1 @@\n-a\n+b\n",
          stderr = "",
        }
      end

      return { code = 1, stdout = "", stderr = "unexpected command" }
    end,
    resolve_branch = function(_)
      return "feature/reply-open-panel"
    end,
    resolve_pr_for_branch = function(_)
      return { state = "single_pr", pr = { number = 42 } }
    end,
    fetch_review_threads = function(_)
      fetch_calls = fetch_calls + 1
      return {
        state = "ok",
        threads = {
          { id = "THREAD_1", comments = { { author = "alice", body = "hello" } } },
        },
      }
    end,
    panel = {
      render = function(_, render_opts)
        panel_render_calls = panel_render_calls + 1
        panel_open_flags[panel_render_calls] = render_opts and render_opts.open == true
      end,
      close = function() end,
    },
  })

  local open_result = session.open_panel()

  assert(open_result.state == "ok", "Expected open_panel success")
  assert(fetch_calls == 2, "Expected open_panel to refresh latest thread data")
  assert(panel_render_calls == 2, "Expected panel render on start and explicit open")
  assert(panel_open_flags[1] == false, "Expected start render to stay passive")
  assert(panel_open_flags[2] == true, "Expected open_panel render to force open")

  session.stop({ panel = { close = function() end } })
end

set["session.reply_to_selected_thread auto-opens panel and requires explicit selection"] = function()
  package.loaded["git-review.session"] = nil
  local session = require("git-review.session")

  local panel_reads = 0
  local panel_render_calls = 0
  local panel_stub = {
    render = function(_, _) panel_render_calls = panel_render_calls + 1 end,
    get_selected_thread_id = function(_)
      panel_reads = panel_reads + 1
      return nil
    end,
    close = function() end,
  }

  session.start({
    run_command = function(command)
      if type(command) == "table"
        and command[1] == "git"
        and command[2] == "rev-parse"
        and command[3] == "--abbrev-ref"
        and command[4] == "--symbolic-full-name"
        and command[5] == "@{upstream}"
      then
        return { code = 0, stdout = "origin/main\n", stderr = "" }
      end

      if type(command) == "table"
        and command[1] == "git"
        and command[2] == "diff"
        and command[3] == "--no-color"
        and command[4] == "origin/main...HEAD"
      then
        return {
          code = 0,
          stdout = "diff --git a/a.lua b/a.lua\n--- a/a.lua\n+++ b/a.lua\n@@ -1 +1 @@\n-a\n+b\n",
          stderr = "",
        }
      end

      return { code = 1, stdout = "", stderr = "unexpected command" }
    end,
    resolve_branch = function(_)
      return "feature/reply-auto-open"
    end,
    resolve_pr_for_branch = function(_)
      return { state = "single_pr", pr = { number = 100 } }
    end,
    fetch_review_threads = function(_)
      return {
        state = "ok",
        threads = {
          { id = "THREAD_AUTO", comments = { { author = "alice", body = "hello" } } },
        },
      }
    end,
    panel = panel_stub,
  })

  local result = session.reply_to_selected_thread({
    body = "Thanks",
    panel = panel_stub,
    reply_to_thread = function(_, _)
      return { state = "ok" }
    end,
  })

  assert(result.state == "context_error", "Expected selection error without explicit cursor context")
  assert(result.message == "No review thread selected", "Expected actionable selection guidance")
  assert(panel_reads == 1, "Expected only initial selection read without implicit retry")
  assert(panel_render_calls == 2, "Expected panel to auto-open via render call")

  session.stop({ panel = { close = function() end } })
end

set["session.reply_to_selected_thread is blocked in range mode"] = function()
  package.loaded["git-review.session"] = nil
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

  local called = 0
  local result = session.reply_to_selected_thread({
    thread_id = "THREAD_42",
    body = "Thanks",
    reply_to_thread = function(_, _)
      called = called + 1
      return {
        state = "ok",
      }
    end,
  })

  assert(result.state == "unsupported_in_range_mode", "Expected range mode to block reply_to_selected_thread")
  assert(result.message == "reply_to_selected_thread is unsupported in range mode", "Expected deterministic range mode message")
  assert(called == 0, "Expected blocked reply action to skip transport")

  session.stop({ panel = { close = function() end } })
end

set["session.reply_to_selected_thread remains blocked in range mode after refresh"] = function()
  package.loaded["git-review.session"] = nil
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

  local called = 0
  local result = session.reply_to_selected_thread({
    thread_id = "THREAD_42",
    body = "Thanks",
    reply_to_thread = function(_, _)
      called = called + 1
      return {
        state = "ok",
      }
    end,
  })

  assert(result.state == "unsupported_in_range_mode", "Expected range mode to block reply_to_selected_thread after refresh")
  assert(result.message == "reply_to_selected_thread is unsupported in range mode", "Expected deterministic range mode message")
  assert(called == 0, "Expected blocked reply action to skip transport after refresh")

  session.stop({ panel = { close = function() end } })
end

set["session.open_panel_toggle filters by scope, toggles, and notifies on fetch"] = function()
  package.loaded["git-review.session"] = nil
  local session = require("git-review.session")

  local fetch_calls = 0
  local render_calls = 0
  local last_render_count = 0
  local panel_open = false
  local notify_messages = {}
  local original_notify = vim.notify

  vim.notify = function(message, _)
    table.insert(notify_messages, tostring(message))
  end

  local panel_stub = {
    is_open = function()
      return panel_open
    end,
    open = function()
      panel_open = true
      return { bufnr = vim.api.nvim_create_buf(false, true), winid = vim.api.nvim_get_current_win() }
    end,
    close = function()
      panel_open = false
    end,
    render = function(threads, _)
      render_calls = render_calls + 1
      last_render_count = #threads
    end,
  }

  session.start({
    run_command = function(command)
      if type(command) == "table"
        and command[1] == "git"
        and command[2] == "rev-parse"
        and command[3] == "--abbrev-ref"
        and command[4] == "--symbolic-full-name"
        and command[5] == "@{upstream}"
      then
        return { code = 0, stdout = "origin/main\n", stderr = "" }
      end

      if type(command) == "table"
        and command[1] == "git"
        and command[2] == "diff"
        and command[3] == "--no-color"
        and command[4] == "origin/main...HEAD"
      then
        return {
          code = 0,
          stdout = "diff --git a/a.lua b/a.lua\n--- a/a.lua\n+++ b/a.lua\n@@ -1 +1 @@\n-a\n+b\n",
          stderr = "",
        }
      end

      return { code = 1, stdout = "", stderr = "unexpected command" }
    end,
    resolve_branch = function(_)
      return "feature/panel-toggle"
    end,
    resolve_pr_for_branch = function(_)
      return { state = "single_pr", pr = { number = 7 } }
    end,
    fetch_review_threads = function(_)
      fetch_calls = fetch_calls + 1
      return {
        state = "ok",
        threads = {
          { id = "A", path = "a.lua", comments = { { author = "alice", body = "A" } } },
          { id = "B", path = "b.lua", comments = { { author = "bob", body = "B" } } },
        },
      }
    end,
    panel = panel_stub,
    defer_thread_refresh = false,
  })

  local current_result = session.open_panel_toggle({ panel = panel_stub, scope = "current", path = "a.lua" })
  assert(current_result.state == "ok", "Expected open_panel_toggle(current) success")
  assert(last_render_count == 1, "Expected current-scope render to show only matching path")
  assert(panel_open == true, "Expected current-scope toggle to open panel")

  vim.wait(100)
  assert(fetch_calls == 2, "Expected async fetch after opening panel toggle")

  local toggled_close = session.open_panel_toggle({ panel = panel_stub, scope = "current", path = "a.lua" })
  assert(toggled_close.state == "ok", "Expected second same-scope toggle success")
  assert(panel_open == false, "Expected second same-scope toggle to close panel")

  local all_result = session.open_panel_toggle({ panel = panel_stub, scope = "all" })
  assert(all_result.state == "ok", "Expected open_panel_toggle(all) success")
  assert(last_render_count == 2, "Expected all-scope render to show all threads")
  assert(panel_open == true, "Expected all-scope toggle to open panel")

  local saw_fetch_notify = false
  for _, message in ipairs(notify_messages) do
    if string.find(message, "fetching comments", 1, true) then
      saw_fetch_notify = true
      break
    end
  end
  assert(saw_fetch_notify == true, "Expected fetching notification during panel toggle refresh")
  assert(render_calls >= 3, "Expected panel renders for current/all toggle interactions")

  session.stop({ panel = panel_stub })
  vim.notify = original_notify
end

return set
