local M = {}

function M.run(command)
  local argv = command
  if type(command) == "string" then
    argv = { "sh", "-c", command }
  end

  local completed = vim.system(argv, { text = true }):wait()

  return {
    code = completed.code,
    stdout = completed.stdout or "",
    stderr = completed.stderr or "",
  }
end

return M
