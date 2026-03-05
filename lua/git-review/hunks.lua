local M = {}

function M.parse_diff(text, opts)
  opts = opts or {}

  vim.validate({
    text = { text, "string" },
    opts = { opts, "table" },
    repo_root = { opts.repo_root, "string", true },
  })

  local repo_root = opts.repo_root
  if type(repo_root) == "string" and repo_root ~= "" then
    repo_root = vim.fs.normalize(repo_root)
  else
    repo_root = nil
  end

  local items = {}
  local current_file

  local lines = vim.split(text, "\n", { plain = true })
  local i = 1
  while i <= #lines do
    local line = lines[i]
    if line:match("^diff %-%-git ") then
      current_file = nil
    end

    local next_file = line:match("^%+%+%+ (.+)$")
    if next_file then
      if next_file == "/dev/null" then
        current_file = nil
      else
        current_file = next_file:match("^b/(.+)$")
      end
    else
      local hunk_text, start_text, count_text = line:match("^(@@ %-[0-9,]+ %+([0-9]+),?([0-9]*) @@)")
      if hunk_text and current_file then
        local lnum = tonumber(start_text)
        if lnum and lnum > 0 then
          local count = tonumber(count_text)
          if not count then
            count = 1
          end

          local end_lnum = math.max(lnum, lnum + count - 1)
          local filename = current_file
          if repo_root ~= nil then
            filename = vim.fs.normalize(repo_root .. "/" .. current_file)
          end

          local added_lines = {}
          local deleted_blocks = {}
          local pending_deleted_block
          local new_lnum = lnum

          local function flush_deleted_block()
            if pending_deleted_block ~= nil then
              table.insert(deleted_blocks, pending_deleted_block)
              pending_deleted_block = nil
            end
          end

          local j = i + 1
          while j <= #lines do
            local body_line = lines[j]
            if body_line:match("^diff %-%-git ")
              or body_line:match("^@@ ")
              or body_line:match("^%-%-%- ")
              or body_line:match("^%+%+%+ ")
            then
              flush_deleted_block()
              break
            end

            local prefix = body_line:sub(1, 1)
            if prefix == "+" then
              flush_deleted_block()
              added_lines[new_lnum] = true
              new_lnum = new_lnum + 1
            elseif prefix == " " then
              flush_deleted_block()
              new_lnum = new_lnum + 1
            elseif prefix == "-" then
              if pending_deleted_block == nil then
                pending_deleted_block = {
                  anchor_lnum = math.max(new_lnum, 1),
                  lines = {},
                }
              end
              table.insert(pending_deleted_block.lines, body_line:sub(2))
            else
              flush_deleted_block()
            end

            j = j + 1
          end

          flush_deleted_block()

          table.insert(items, {
            filename = filename,
            lnum = lnum,
            end_lnum = end_lnum,
            text = hunk_text,
            hunk_id = string.format("%s:%d:%d", current_file, lnum, end_lnum),
            added_lines = added_lines,
            deleted_blocks = deleted_blocks,
          })

          i = j - 1
        end
      end
    end

    i = i + 1
  end

  return items
end

return M
