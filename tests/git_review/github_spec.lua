local T = require("mini.test")

local set = T.new_set()

set["resolve_pr_for_branch returns single_pr state"] = function()
  local github = require("git-review.github")
  local called_argv

  local result = github.resolve_pr_for_branch("feature/task-3", function(argv)
    called_argv = argv
    return {
      code = 0,
      stdout = '[{"number":42,"title":"Task 3","body":"Implements review flow","url":"https://github.com/acme/repo/pull/42","baseRefName":"main","headRefName":"feature/task-3","author":{"login":"octocat"}}]',
      stderr = "",
    }
  end)

  assert(type(called_argv) == "table", "Expected argv table")
  assert(called_argv[1] == "gh", "Expected gh binary argv")
  assert(called_argv[2] == "pr", "Expected pr subcommand argv")
  assert(called_argv[3] == "list", "Expected list subcommand argv")
  assert(called_argv[4] == "--head", "Expected --head flag argv")
  assert(called_argv[5] == "feature/task-3", "Expected branch argv")
  assert(called_argv[6] == "--json", "Expected --json flag argv")
  assert(
    called_argv[7] == "number,title,body,author,baseRefName,headRefName,url",
    "Expected --json fields argv"
  )

  assert(result.state == "single_pr", "Expected single_pr state")
  assert(type(result.pr) == "table", "Expected a PR table")
  assert(result.pr.number == 42, "Expected PR number")
  assert(result.pr.title == "Task 3", "Expected PR title")
  assert(result.pr.body == "Implements review flow", "Expected PR body")
  assert(type(result.pr.author) == "table", "Expected PR author object")
  assert(result.pr.author.login == "octocat", "Expected PR author login")
  assert(result.pr.baseRefName == "main", "Expected PR base branch")
  assert(result.pr.headRefName == "feature/task-3", "Expected PR head branch")
  assert(result.pr.url == "https://github.com/acme/repo/pull/42", "Expected PR URL")
end

set["resolve_pr_for_branch returns no_pr state"] = function()
  local github = require("git-review.github")

  local result = github.resolve_pr_for_branch("feature/task-3", function(_)
    return {
      code = 0,
      stdout = "[]",
      stderr = "",
    }
  end)

  assert(result.state == "no_pr", "Expected no_pr state")
end

set["resolve_pr_for_branch returns multiple_prs state"] = function()
  local github = require("git-review.github")

  local result = github.resolve_pr_for_branch("feature/task-3", function(_)
    return {
      code = 0,
      stdout = '[{"number":1,"title":"A","url":"https://example.com/1"},{"number":2,"title":"B","url":"https://example.com/2"}]',
      stderr = "",
    }
  end)

  assert(result.state == "multiple_prs", "Expected multiple_prs state")
  assert(type(result.prs) == "table", "Expected prs array")
  assert(#result.prs == 2, "Expected two PRs")
end

set["resolve_pr_for_branch returns command_error state"] = function()
  local github = require("git-review.github")

  local result = github.resolve_pr_for_branch("feature/task-3", function(_)
    return {
      code = 1,
      stdout = "",
      stderr = "gh: auth required",
    }
  end)

  assert(result.state == "command_error", "Expected command_error state")
  assert(result.message == "gh: auth required", "Expected command error message")
end

set["resolve_pr_for_branch returns parse_error state"] = function()
  local github = require("git-review.github")

  local result = github.resolve_pr_for_branch("feature/task-3", function(_)
    return {
      code = 0,
      stdout = "not-json",
      stderr = "",
    }
  end)

  assert(result.state == "parse_error", "Expected parse_error state")
  assert(type(result.message) == "string", "Expected parse error message")
end

set["resolve_pr_for_branch returns parse_error for object JSON"] = function()
  local github = require("git-review.github")

  local result = github.resolve_pr_for_branch("feature/task-3", function(_)
    return {
      code = 0,
      stdout = '{"number":42,"title":"Task 3","url":"https://github.com/acme/repo/pull/42"}',
      stderr = "",
    }
  end)

  assert(result.state == "parse_error", "Expected parse_error state")
  assert(type(result.message) == "string", "Expected parse error message")
end

set["resolve_pr_for_branch handles malformed run_command result"] = function()
  local github = require("git-review.github")

  local result = github.resolve_pr_for_branch("feature/task-3", function(_)
    return "invalid"
  end)

  assert(result.state == "command_error", "Expected command_error state")
  assert(type(result.message) == "string", "Expected command error message")
end

set["fetch_review_threads returns ok state with thread list"] = function()
  local github = require("git-review.github")
  local called_argv

  local result = github.fetch_review_threads(42, function(argv)
    called_argv = argv
    return {
      code = 0,
      stdout = [[{"reviewThreads":[{"id":"T1","isResolved":false,"comments":[{"author":{"login":"octocat"},"body":"Looks good"}]}]}]],
      stderr = "",
    }
  end)

  assert(type(called_argv) == "table", "Expected argv table")
  assert(called_argv[1] == "gh", "Expected gh binary argv")
  assert(called_argv[2] == "pr", "Expected pr subcommand argv")
  assert(called_argv[3] == "view", "Expected view subcommand argv")
  assert(called_argv[4] == "42", "Expected PR number argv")
  assert(called_argv[5] == "--json", "Expected --json flag argv")
  assert(called_argv[6] == "reviewThreads", "Expected reviewThreads json field")

  assert(result.state == "ok", "Expected ok state")
  assert(type(result.threads) == "table", "Expected thread list")
  assert(#result.threads == 1, "Expected one thread")
end

set["fetch_review_threads preserves thread path metadata"] = function()
  local github = require("git-review.github")

  local result = github.fetch_review_threads(42, function(_)
    return {
      code = 0,
      stdout = [[{"reviewThreads":[{"id":"T1","path":"lua/git-review/init.lua","isResolved":false,"comments":[{"author":{"login":"octocat"},"body":"Looks good"}]}]}]],
      stderr = "",
    }
  end)

  assert(result.state == "ok", "Expected ok state")
  assert(type(result.threads) == "table" and #result.threads == 1, "Expected one thread")
  assert(result.threads[1].path == "lua/git-review/init.lua", "Expected thread path metadata")
end

set["fetch_review_threads returns parse_error for invalid payload"] = function()
  local github = require("git-review.github")

  local result = github.fetch_review_threads(42, function(_)
    return {
      code = 0,
      stdout = "[]",
      stderr = "",
    }
  end)

  assert(result.state == "parse_error", "Expected parse_error state")
end

set["fetch_review_threads returns command_error on gh failure"] = function()
  local github = require("git-review.github")

  local result = github.fetch_review_threads(42, function(_)
    return {
      code = 1,
      stdout = "",
      stderr = "gh: auth required",
    }
  end)

  assert(result.state == "command_error", "Expected command_error state")
  assert(result.message == "gh: auth required", "Expected command failure message")
end

set["fetch_review_threads falls back to GraphQL when reviewThreads json field is unsupported"] = function()
  local github = require("git-review.github")
  local calls = {}

  local result = github.fetch_review_threads(42, function(argv)
    table.insert(calls, argv)

    if #calls == 1 then
      return {
        code = 1,
        stdout = "",
        stderr = "unknown json field: reviewThreads",
      }
    end

    if #calls == 2 then
      return {
        code = 0,
        stdout = [[{"nameWithOwner":"acme/repo"}]],
        stderr = "",
      }
    end

    return {
      code = 0,
      stdout = [[{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"id":"T1","isResolved":false,"comments":{"nodes":[{"author":{"login":"octocat"},"body":"Looks good"}]}}]}}}}}]],
      stderr = "",
    }
  end)

  assert(#calls == 3, "Expected repo lookup and GraphQL fallback request after unsupported field")
  assert(calls[1][1] == "gh" and calls[1][2] == "pr" and calls[1][3] == "view", "Expected first call to gh pr view")
  assert(calls[2][1] == "gh" and calls[2][2] == "repo" and calls[2][3] == "view", "Expected second call to gh repo view")
  assert(calls[3][1] == "gh" and calls[3][2] == "api" and calls[3][3] == "graphql", "Expected fallback call to gh api graphql")
  assert(result.state == "ok", "Expected ok state from GraphQL fallback")
  assert(type(result.threads) == "table", "Expected thread list")
  assert(#result.threads == 1, "Expected one thread from GraphQL fallback")
end

set["fake_pr_fixture provides mundane changes and comments for verification"] = function()
  local fixture = require("git-review.fake_pr_fixture")

  local sample = fixture.sample_review_data()
  assert(type(sample) == "table", "Expected fixture sample table")
  assert(type(sample.changes) == "table" and #sample.changes >= 2, "Expected multiple mundane change entries")
  assert(type(sample.comments) == "table" and #sample.comments >= 2, "Expected multiple comment entries")
  assert(sample.changes[1].path == "README.md", "Expected first change path for stable verification")
  assert(type(sample.comments[1].author) == "string", "Expected fixture comment author")
end

set["submit_review assembles request payload and path"] = function()
  local github = require("git-review.github")
  local called_request

  local result = github.submit_review({
    repo = "acme/repo",
    pr_number = 42,
    event = "COMMENT",
    body = "Looks good to me",
  }, function(request)
    called_request = request
    return {
      code = 0,
      stdout = [[{"id":101,"state":"COMMENTED"}]],
      stderr = "",
    }
  end)

  assert(type(called_request) == "table", "Expected request table")
  assert(called_request.method == "POST", "Expected POST method")
  assert(called_request.path == "repos/acme/repo/pulls/42/reviews", "Expected submit review API path")
  assert(type(called_request.body) == "table", "Expected payload table")
  assert(called_request.body.event == "COMMENT", "Expected event payload")
  assert(called_request.body.body == "Looks good to me", "Expected body payload")

  assert(result.state == "ok", "Expected ok state")
  assert(type(result.review) == "table", "Expected review payload")
  assert(result.review.id == 101, "Expected parsed review id")
end

set["submit_review omits empty optional body"] = function()
  local github = require("git-review.github")
  local called_request

  github.submit_review({
    repo = "acme/repo",
    pr_number = 42,
    event = "APPROVE",
    body = "",
  }, function(request)
    called_request = request
    return {
      code = 0,
      stdout = [[{"id":102,"state":"APPROVED"}]],
      stderr = "",
    }
  end)

  assert(type(called_request.body) == "table", "Expected payload table")
  assert(called_request.body.event == "APPROVE", "Expected event payload")
  assert(called_request.body.body == nil, "Expected body to be omitted for empty string")
end

set["submit_review returns command_error on gh failure"] = function()
  local github = require("git-review.github")

  local result = github.submit_review({
    repo = "acme/repo",
    pr_number = 42,
    event = "REQUEST_CHANGES",
  }, function(_)
    return {
      code = 1,
      stdout = "",
      stderr = "gh: auth required",
    }
  end)

  assert(result.state == "command_error", "Expected command_error state")
  assert(result.message == "gh: auth required", "Expected command failure message")
end

set["submit_review returns command_error for malformed send result"] = function()
  local github = require("git-review.github")

  local result = github.submit_review({
    repo = "acme/repo",
    pr_number = 42,
    event = "COMMENT",
  }, function(_)
    return "invalid"
  end)

  assert(result.state == "command_error", "Expected command_error state")
  assert(result.message == "run_command must return a table", "Expected invalid result error message")
end

set["submit_review returns ok with empty review for empty stdout"] = function()
  local github = require("git-review.github")

  local result = github.submit_review({
    repo = "acme/repo",
    pr_number = 42,
    event = "COMMENT",
  }, function(_)
    return {
      code = 0,
      stdout = "",
      stderr = "",
    }
  end)

  assert(result.state == "ok", "Expected ok state")
  assert(type(result.review) == "table", "Expected review payload")
  assert(vim.tbl_isempty(result.review), "Expected empty review payload")
end

set["submit_review returns parse_error for invalid JSON"] = function()
  local github = require("git-review.github")

  local result = github.submit_review({
    repo = "acme/repo",
    pr_number = 42,
    event = "COMMENT",
  }, function(_)
    return {
      code = 0,
      stdout = "not-json",
      stderr = "",
    }
  end)

  assert(result.state == "parse_error", "Expected parse_error state")
  assert(type(result.message) == "string", "Expected parse error message")
end

set["submit_review returns parse_error for non-object JSON"] = function()
  local github = require("git-review.github")

  local result = github.submit_review({
    repo = "acme/repo",
    pr_number = 42,
    event = "COMMENT",
  }, function(_)
    return {
      code = 0,
      stdout = "[]",
      stderr = "",
    }
  end)

  assert(result.state == "parse_error", "Expected parse_error state")
  assert(result.message == "gh api submit review returned non-object JSON", "Expected parse error message")
end

return set
