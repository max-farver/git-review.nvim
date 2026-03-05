local M = {}

function M.make_repo(opts)
  opts = opts or {}
  assert(type(opts) == "table", "make_repo: opts must be a table")

  local path = opts.path
  assert(type(path) == "string" and path ~= "", "make_repo: opts.path must be a non-empty string")

  return {
    path = vim.fs.normalize(path),
  }
end

return M
