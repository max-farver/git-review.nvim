local T = require("mini.test")

local function task_suite_files()
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

T.run({
  collect = {
    find_files = task_suite_files,
  },
  execute = {
    reporter = T.gen_reporter.stdout({ group_depth = 2, quit_on_finish = true }),
  },
})
