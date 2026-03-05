local M = {}

local pr_info_state = {
  bufnr = nil,
  winid = nil,
}

local function normalize_author(author)
  if type(author) == "string" and author ~= "" then
    return author
  end

  if type(author) == "table" and type(author.login) == "string" and author.login ~= "" then
    return author.login
  end

  return "unknown"
end

local function string_or_fallback(value, fallback)
  if type(value) == "string" and value ~= "" then
    return value
  end

  return fallback
end

local function split_lines(text)
  if type(text) ~= "string" or text == "" then
    return { "(no description)" }
  end

  local lines = vim.split(text, "\n", { plain = true })
  if #lines == 0 then
    return { "(no description)" }
  end

  return lines
end

function M.render_lines(pr)
  vim.validate({
    pr = { pr, "table" },
  })

  local number = type(pr.number) == "number" and tostring(pr.number) or "?"
  local title = string_or_fallback(pr.title, "(untitled pull request)")
  local body_lines = split_lines(pr.body)
  local author = normalize_author(pr.author)
  local base_ref = string_or_fallback(pr.baseRefName, "(unknown)")
  local head_ref = string_or_fallback(pr.headRefName, "(unknown)")
  local url = string_or_fallback(pr.url, "(unknown)")

  local lines = {
    string.format("# PR #%s: %s", number, title),
    "",
    "- URL: " .. url,
    "- Author: @" .. author,
    "- Base: " .. base_ref,
    "- Head: " .. head_ref,
    "",
    "## Description",
    "",
  }

  for _, line in ipairs(body_lines) do
    table.insert(lines, line)
  end

  return lines
end

local function ensure_window()
  local bufnr = pr_info_state.bufnr
  local winid = pr_info_state.winid

  if bufnr and vim.api.nvim_buf_is_valid(bufnr) and winid and vim.api.nvim_win_is_valid(winid) then
    return bufnr, winid
  end

  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].bufhidden = "hide"
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].modifiable = true
    vim.bo[bufnr].filetype = "markdown"
    pr_info_state.bufnr = bufnr
  end

  vim.cmd("botright vsplit")
  winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(winid, 64)
  vim.api.nvim_win_set_buf(winid, bufnr)
  pr_info_state.winid = winid

  return bufnr, winid
end

function M.render(pr, opts)
  opts = opts or {}
  vim.validate({
    pr = { pr, "table" },
    opts = { opts, "table" },
  })

  local bufnr = opts.bufnr
  local winid = opts.winid
  if bufnr == nil or winid == nil then
    bufnr, winid = ensure_window()
  end

  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].filetype = "markdown"

  local lines = M.render_lines(pr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false

  return {
    bufnr = bufnr,
    winid = winid,
  }
end

return M
