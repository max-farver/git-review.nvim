local T = require("mini.test")

local M = {}

local function default_suite_files()
  local files = {
    "tests/git_review/comment_create_spec.lua",
    "tests/git_review/positions_spec.lua",
    "tests/git_review/start_spec.lua",
    "tests/git_review/hunks_spec.lua",
    "tests/git_review/hunk_highlight_spec.lua",
    "tests/git_review/github_spec.lua",
    "tests/git_review/errors_spec.lua",
    "tests/git_review/panel_spec.lua",
    "tests/git_review/progress_spec.lua",
    "tests/git_review/reply_spec.lua",
    "tests/git_review/setup_spec.lua",
    "tests/git_review/smoke_spec.lua",
    "tests/git_review/submit_spec.lua",
  }

  table.sort(files)
  return files
end

function M.run(files)
  vim.validate({
    files = { files, "table", true },
  })

  local suite_files = files or default_suite_files()

  T.run({
    collect = {
      find_files = function()
        return vim.deepcopy(suite_files)
      end,
    },
    execute = {
      reporter = T.gen_reporter.stdout({ group_depth = 2, quit_on_finish = false }),
    },
  })
end

return M
