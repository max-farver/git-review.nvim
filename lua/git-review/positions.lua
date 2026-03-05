local M = {}

local function parse_hunk_header(line)
  local new_start, new_count = line:match("^@@ %-[0-9]+,?[0-9]* %+([0-9]+),?([0-9]*) @@")
  if not new_start then
    return nil
  end

  local start_line = tonumber(new_start)
  local count = tonumber(new_count)
  if not count then
    count = 1
  end

  return {
    start_line = start_line,
    count = count,
  }
end

local function build_line_position_map(diff_text)
  local file_maps = {}
  local current_file = nil
  local in_hunk = false
  local next_new_line = nil
  local file_position = 0

  for _, line in ipairs(vim.split(diff_text, "\n", { plain = true })) do
    local next_file = line:match("^%+%+%+ b/(.+)$")
    if next_file then
      current_file = next_file
      in_hunk = false
      next_new_line = nil
      file_position = 0
      file_maps[current_file] = file_maps[current_file] or {}
    else
      local parsed_hunk = parse_hunk_header(line)
      if parsed_hunk then
        in_hunk = true
        next_new_line = parsed_hunk.start_line
      elseif in_hunk and current_file then
        local prefix = line:sub(1, 1)
        if prefix ~= "\\" then
          file_position = file_position + 1
        end

        if prefix == " " or prefix == "+" then
          file_maps[current_file][next_new_line] = file_position
          next_new_line = next_new_line + 1
        elseif prefix == "-" then
          -- Keep new-file line unchanged for deletion entries.
        else
          in_hunk = false
          next_new_line = nil
        end
      end
    end
  end

  return file_maps
end

function M.map_line(diff_text, path, line)
  vim.validate({
    diff_text = { diff_text, "string" },
    path = { path, "string" },
    line = { line, "number" },
  })

  local file_maps = build_line_position_map(diff_text)
  local line_map = file_maps[path]
  if not line_map then
    return nil, "No diff entries found for file: " .. path
  end

  local position = line_map[line]
  if type(position) ~= "number" then
    return nil, string.format("Unable to map line %d in %s to a diff position", line, path)
  end

  return {
    position = position,
  }
end

function M.map_range(diff_text, path, start_line, end_line)
  vim.validate({
    diff_text = { diff_text, "string" },
    path = { path, "string" },
    start_line = { start_line, "number" },
    end_line = { end_line, "number" },
  })

  local first_line = math.min(start_line, end_line)
  local last_line = math.max(start_line, end_line)

  local start_mapped, start_err = M.map_line(diff_text, path, first_line)
  if not start_mapped then
    return nil, start_err
  end

  local end_mapped, end_err = M.map_line(diff_text, path, last_line)
  if not end_mapped then
    return nil, end_err
  end

  return {
    start_position = start_mapped.position,
    position = end_mapped.position,
  }
end

return M
