local M = {}

function M.sample_review_data()
  return {
    title = "Fake PR for testing",
    status = "open",
    reviewers = { "octocat", "hubot" },
    changes = {
      {
        path = "README.md",
        hunk = "@@ -1,3 +1,4 @@",
        summary = "add usage note",
      },
      {
        path = "lua/git-review/init.lua",
        hunk = "@@ -20,2 +20,3 @@",
        summary = "wire new command",
      },
    },
    comments = {
      {
        author = "octocat",
        body = "Looks good overall.",
      },
      {
        author = "hubot",
        body = "Nit: improve command description.",
      },
    },
  }
end

return M
