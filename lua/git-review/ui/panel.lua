local M = {}

local panel_state = {
  bufnr = nil,
  winid = nil,
  thread_id_by_bufnr = {},
  show_resolved_bodies = false,
}

local function is_valid_bufnr(bufnr)
  return type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr)
end

local function is_valid_winid(winid)
  return type(winid) == "number" and vim.api.nvim_win_is_valid(winid)
end

local function normalize_author(comment)
  if type(comment.author) == "string" and comment.author ~= "" then
    return comment.author
  end

  if type(comment.author) == "table" and type(comment.author.login) == "string" and comment.author.login ~= "" then
    return comment.author.login
  end

  return "unknown"
end

local function trim(text)
  return text:gsub("^%s+", ""):gsub("%s+$", "")
end

local function case_insensitive_tag_pattern(tag)
  local chunks = {}

  for i = 1, #tag do
    local char = tag:sub(i, i)
    chunks[#chunks + 1] = string.format("[%s%s]", char:lower(), char:upper())
  end

  return table.concat(chunks)
end

local function normalize_break_tags(text)
  local br = case_insensitive_tag_pattern("br")
  return text:gsub("<" .. br .. "%s*/?>", "\n")
end

local function normalize_paragraph_tags(text)
  local p = case_insensitive_tag_pattern("p")
  local normalized = text
  normalized = normalized:gsub("%s*<" .. p .. "%f[%s>/][^>]*>", "\n")
  normalized = normalized:gsub("</" .. p .. "%f[%s>/][^>]*>%s*", "\n")
  normalized = normalized:gsub("\n\n\n+", "\n\n")
  return normalized
end

local function fold_html_comments(text)
  local placeholder = "[HTML comment hidden]"
  local folded_placeholder = "HTML_COMMENT_HIDDEN_SENTINEL"
  local normalized = text:gsub("<!%-%-.-%-%->", folded_placeholder)
  normalized = normalized:gsub("<!%-%-.*$", folded_placeholder)
  normalized = normalized:gsub("(%S)" .. folded_placeholder, "%1 " .. folded_placeholder)
  normalized = normalized:gsub(folded_placeholder .. "(%S)", function(next_char)
    if next_char:match("^[,%.!%?:;%)%]%}]$") then
      return folded_placeholder .. next_char
    end

    return folded_placeholder .. " " .. next_char
  end)
  normalized = normalized:gsub(folded_placeholder, placeholder)
  return normalized
end

local function normalize_pre_code_blocks(text)
  local pre = case_insensitive_tag_pattern("pre")
  local code = case_insensitive_tag_pattern("code")

  return text:gsub("<" .. pre .. "%s*[^>]*>%s*<" .. code .. "%s*[^>]*>(.-)</" .. code .. ">%s*</" .. pre .. ">", function(block)
    local trimmed_block = block:gsub("^%s*\n", ""):gsub("\n%s*$", "")
    return string.format("```\n%s\n```", trimmed_block)
  end)
end

local function normalize_blockquotes(text)
  local blockquote = case_insensitive_tag_pattern("blockquote")

  return text:gsub("<" .. blockquote .. "%s*[^>]*>(.-)</" .. blockquote .. ">", function(content)
    local lines = {}
    for line in content:gmatch("[^\n]+") do
      local trimmed_line = trim(line)
      if trimmed_line ~= "" then
        lines[#lines + 1] = "> " .. trimmed_line
      end
    end

    return table.concat(lines, "\n")
  end)
end

local function extract_li_items(list_content)
  local items = {}
  local starts = {}
  local li = case_insensitive_tag_pattern("li")

  for item_start, item_after_tag in list_content:gmatch("()<" .. li .. "%s*[^>]*>()") do
    table.insert(starts, { start = item_start, after_tag = item_after_tag })
  end

  for i = 1, #starts do
    local item_end = (starts[i + 1] and starts[i + 1].start - 1) or #list_content
    local item = list_content:sub(starts[i].after_tag, item_end)
    item = trim(item:gsub("</" .. li .. ">%s*$", ""))
    if item ~= "" then
      table.insert(items, item)
    end
  end

  return items
end

local function render_list_markdown(list_content, ordered)
  local items = extract_li_items(list_content)
  local lines = {}

  for i = 1, #items do
    if ordered then
      lines[#lines + 1] = string.format("%d. %s", i, items[i])
    else
      lines[#lines + 1] = "- " .. items[i]
    end
  end

  return table.concat(lines, "\n")
end

local function normalize_lists(text)
  local ul = case_insensitive_tag_pattern("ul")
  local ol = case_insensitive_tag_pattern("ol")

  local normalized = text:gsub("<" .. ul .. "%s*[^>]*>(.-)</" .. ul .. ">", function(content)
    return render_list_markdown(content, false)
  end)

  normalized = normalized:gsub("<" .. ol .. "%s*[^>]*>(.-)</" .. ol .. ">", function(content)
    return render_list_markdown(content, true)
  end)

  return normalized
end

local function normalize_anchor_tags(text)
  local a = case_insensitive_tag_pattern("a")
  local href = case_insensitive_tag_pattern("href")

  return text:gsub("<" .. a .. "%s*([^>]*)>(.-)</" .. a .. ">", function(attrs, label)
    local url = attrs:match(href .. '%s*=%s*"([^"]-)"') or attrs:match(href .. "%s*=%s*'([^']-)'")
    if type(url) == "string" and url ~= "" then
      return string.format("[%s](%s)", label, url)
    end

    return label
  end)
end

local function normalize_inline_tags(text)
  local normalized = text
  local code = case_insensitive_tag_pattern("code")
  local strong = case_insensitive_tag_pattern("strong")
  local b = case_insensitive_tag_pattern("b")
  local em = case_insensitive_tag_pattern("em")
  local i = case_insensitive_tag_pattern("i")

  normalized = normalized:gsub("<" .. code .. "%s*[^>]*>(.-)</" .. code .. ">", "`%1`")
  normalized = normalized:gsub("<" .. strong .. "%s*[^>]*>(.-)</" .. strong .. ">", "**%1**")
  normalized = normalized:gsub("<" .. b .. "%s*[^>]*>(.-)</" .. b .. ">", "**%1**")
  normalized = normalized:gsub("<" .. em .. "%s*[^>]*>(.-)</" .. em .. ">", "*%1*")
  normalized = normalized:gsub("<" .. i .. "%s*[^>]*>(.-)</" .. i .. ">", "*%1*")

  return normalized
end

local function strip_supported_html_tags(text)
  local normalized = text
  local supported_tags = {
    "a",
    "pre",
    "code",
    "blockquote",
    "ul",
    "ol",
    "li",
    "strong",
    "b",
    "em",
    "i",
    "br",
  }

  for _, tag in ipairs(supported_tags) do
    local pattern = case_insensitive_tag_pattern(tag)
    normalized = normalized:gsub("</" .. pattern .. "%f[%s>/][^>\n]*>", "")
    normalized = normalized:gsub("</" .. pattern .. "%f[%s>/][^>\n]*$", "")
    normalized = normalized:gsub("<" .. pattern .. "%s*/>", "")
    normalized = normalized:gsub("<" .. pattern .. "%s*>", "")
    normalized = normalized:gsub("<" .. pattern .. "%s+[^>\n]*>", "")
    normalized = normalized:gsub("<" .. pattern .. "%s+[^>\n]*", "")
  end

  return normalized
end

local function strip_unknown_html_tags(text)
  local normalized = text
  local tag_name_pattern = "[a-zA-Z][a-zA-Z0-9]+"
  local opening_tags = {}

  for tag_name in text:gmatch("<(" .. tag_name_pattern .. ")%f[%s>/][^>\n]*>") do
    opening_tags[tag_name:lower()] = true
  end

  normalized = normalized:gsub("<" .. tag_name_pattern .. "%f[%s>/][^>\n]*/>", "")
  normalized = normalized:gsub("<" .. tag_name_pattern .. "%f[%s>/][^>\n]*>", "")
  normalized = normalized:gsub("<" .. tag_name_pattern .. "%f[%s>/][^>\n]*$", "")

  for tag_name in pairs(opening_tags) do
    local tag_pattern = case_insensitive_tag_pattern(tag_name)
    normalized = normalized:gsub("</" .. tag_pattern .. "%f[%s>/][^>\n]*>", "")
    normalized = normalized:gsub("</" .. tag_pattern .. "%f[%s>/][^>\n]*$", "")
  end

  return normalized
end

local function normalize_html_to_markdown(text)
  local normalized = text
  normalized = fold_html_comments(normalized)
  normalized = normalize_paragraph_tags(normalized)
  normalized = normalize_break_tags(normalized)
  normalized = normalize_pre_code_blocks(normalized)
  normalized = normalize_blockquotes(normalized)
  normalized = normalize_lists(normalized)
  normalized = normalize_anchor_tags(normalized)
  normalized = normalize_inline_tags(normalized)
  normalized = strip_supported_html_tags(normalized)
  normalized = strip_unknown_html_tags(normalized)
  return normalized
end

local function normalize_body(comment)
  if type(comment.body) == "string" and comment.body:find("%S") then
    local normalized = normalize_html_to_markdown(comment.body)
    if normalized:find("%S") then
      return normalized
    end
  end

  return "(no body)"
end

local function split_body_lines(comment)
  local body_lines = {}
  for body_line in string.gmatch(normalize_body(comment), "[^\n]+") do
    table.insert(body_lines, body_line)
  end

  if #body_lines == 0 then
    body_lines[1] = "(no body)"
  end

  return body_lines
end

local function get_thread_comments(thread)
  if type(thread.comments) == "table" and #thread.comments > 0 then
    return thread.comments
  end

  return { thread }
end

local function append_line(lines, thread_id_by_line, text, thread_id)
  table.insert(lines, text)
  if type(thread_id) == "string" and thread_id ~= "" and type(thread_id_by_line) == "table" then
    thread_id_by_line[#lines] = thread_id
  end
end

local function format_comment_count(comment_count)
  local noun = comment_count == 1 and "comment" or "comments"
  return string.format("%d %s", comment_count, noun)
end

local function format_thread_heading(thread_index, comment_count, thread_status)
  return string.format("## Thread %d · %s · %s", thread_index, format_comment_count(comment_count), thread_status)
end

local function format_comment_heading(author)
  return string.format("### %s", author)
end

local function format_comment_separator()
  return "> ---"
end

local function resolve_show_resolved_bodies(opts, fallback)
  if opts.show_resolved_bodies ~= nil then
    vim.validate({
      show_resolved_bodies = { opts.show_resolved_bodies, "boolean" },
    })
    return opts.show_resolved_bodies
  end

  return fallback
end

local REACTION_DISPLAY_BY_CONTENT = {
  THUMBS_UP = "👍",
  THUMBS_DOWN = "👎",
  LAUGH = "😄",
  HOORAY = "🎉",
  CONFUSED = "😕",
  HEART = "❤️",
  ROCKET = "🚀",
  EYES = "👀",
}

local REACTION_ORDER = {
  "THUMBS_UP",
  "THUMBS_DOWN",
  "LAUGH",
  "HOORAY",
  "CONFUSED",
  "HEART",
  "ROCKET",
  "EYES",
}

local function summarize_reactions(comment)
  if type(comment) ~= "table" then
    return nil
  end

  local counts = {}

  if type(comment.reactionGroups) == "table" then
    for _, group in ipairs(comment.reactionGroups) do
      if type(group) == "table" and type(group.content) == "string" then
        local count = group.users and group.users.totalCount
        if type(count) ~= "number" then
          count = group.count
        end

        if type(count) == "number" and count > 0 then
          counts[group.content] = count
        end
      end
    end
  end

  if type(comment.reactions) == "table" then
    for key, value in pairs(comment.reactions) do
      if type(key) == "string" and type(value) == "number" and value > 0 then
        counts[key] = value
      end
    end
  end

  local chunks = {}
  for _, content in ipairs(REACTION_ORDER) do
    local count = counts[content]
    local emoji = REACTION_DISPLAY_BY_CONTENT[content]
    if type(count) == "number" and count > 0 and type(emoji) == "string" then
      chunks[#chunks + 1] = string.format("%s %d", emoji, count)
    end
  end

  if #chunks == 0 then
    return nil
  end

  return table.concat(chunks, "  ")
end

local function should_collapse_thread(thread, show_resolved_bodies)
  return thread.isResolved == true and show_resolved_bodies == false
end

local function append_thread_comment_lines(lines, thread, thread_id_by_line, thread_index, show_resolved_bodies)
  local comments = get_thread_comments(thread)
  local thread_id = type(thread.id) == "string" and thread.id or ""
  local thread_status = thread.isResolved == true and "resolved" or "unresolved"

  append_line(lines, thread_id_by_line, format_thread_heading(thread_index, #comments, thread_status), thread_id)

  if should_collapse_thread(thread, show_resolved_bodies) then
    append_line(lines, thread_id_by_line, "> (resolved thread collapsed)", thread_id)
    return
  end

  for comment_index, comment in ipairs(comments) do
    local author = normalize_author(comment)
    local body_lines = split_body_lines(comment)
    append_line(lines, thread_id_by_line, format_comment_heading(author), thread_id)

    for body_line_index = 1, #body_lines do
      append_line(lines, thread_id_by_line, "> " .. body_lines[body_line_index], thread_id)
    end

    local reaction_summary = summarize_reactions(comment)
    if type(reaction_summary) == "string" and reaction_summary ~= "" then
      append_line(lines, thread_id_by_line, "> Reactions: " .. reaction_summary, thread_id)
    end

    if comment_index < #comments then
      append_line(lines, thread_id_by_line, format_comment_separator(), thread_id)
    end
  end
end

local build_render_model

function M.render_lines(threads, opts)
  opts = opts or {}
  vim.validate({
    threads = { threads, "table" },
    opts = { opts, "table" },
    empty_message = { opts.empty_message, "string", true },
  })

  return build_render_model(threads, {
    show_resolved_bodies = resolve_show_resolved_bodies(opts, false),
    empty_message = opts.empty_message,
  }).lines
end

build_render_model = function(threads, opts)
  opts = opts or {}

  if #threads == 0 then
    local empty_message = opts.empty_message
    if type(empty_message) ~= "string" or empty_message == "" then
      empty_message = "No review threads for this context."
    end

    return {
      lines = { empty_message },
      thread_id_by_line = {},
    }
  end

  local show_resolved_bodies = opts.show_resolved_bodies
  if show_resolved_bodies == nil then
    show_resolved_bodies = false
  end
  local lines = {}
  local thread_id_by_line = {}

  for i, thread in ipairs(threads) do
    append_thread_comment_lines(lines, thread, thread_id_by_line, i, show_resolved_bodies)

    if i < #threads then
      table.insert(lines, "")
    end
  end

  return {
    lines = lines,
    thread_id_by_line = thread_id_by_line,
  }
end

local function ensure_panel_buffer()
  if is_valid_bufnr(panel_state.bufnr) then
    return panel_state.bufnr
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].filetype = "markdown"
  panel_state.bufnr = bufnr

  return bufnr
end

function M.is_open()
  return is_valid_winid(panel_state.winid) and is_valid_bufnr(panel_state.bufnr)
end

function M.open(opts)
  opts = opts or {}
  vim.validate({
    opts = { opts, "table" },
  })

  local bufnr = opts.bufnr
  if not is_valid_bufnr(bufnr) then
    bufnr = ensure_panel_buffer()
  end

  panel_state.bufnr = bufnr

  if is_valid_winid(panel_state.winid) then
    vim.api.nvim_win_set_buf(panel_state.winid, bufnr)
    return {
      bufnr = bufnr,
      winid = panel_state.winid,
    }
  end

  vim.cmd("botright vsplit")
  local winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(winid, opts.width or 48)
  vim.api.nvim_win_set_buf(winid, bufnr)
  panel_state.winid = winid

  return {
    bufnr = bufnr,
    winid = winid,
  }
end

function M.close()
  if is_valid_winid(panel_state.winid) then
    pcall(vim.api.nvim_win_close, panel_state.winid, false)
  end

  panel_state.winid = nil
end

local function resolve_render_target(opts)
  local bufnr = panel_state.bufnr
  if is_valid_bufnr(opts.bufnr) then
    bufnr = opts.bufnr
    panel_state.bufnr = bufnr
  end

  if not is_valid_bufnr(bufnr) then
    bufnr = ensure_panel_buffer()
  end

  if opts.open == true then
    local opened = M.open({
      bufnr = bufnr,
      width = opts.width,
    })
    bufnr = opened.bufnr
  elseif is_valid_winid(opts.winid) then
    vim.api.nvim_win_set_buf(opts.winid, bufnr)
  end

  return bufnr
end

function M.render(threads, opts)
  opts = opts or {}
  vim.validate({
    threads = { threads, "table" },
    opts = { opts, "table" },
    empty_message = { opts.empty_message, "string", true },
  })

  local bufnr = resolve_render_target(opts)

  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].filetype = "markdown"

  local model = build_render_model(threads, {
    show_resolved_bodies = resolve_show_resolved_bodies(opts, panel_state.show_resolved_bodies),
    empty_message = opts.empty_message,
  })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, model.lines)
  vim.bo[bufnr].modifiable = false

  panel_state.thread_id_by_bufnr[bufnr] = model.thread_id_by_line

  return bufnr
end

function M.get_show_resolved_bodies()
  return panel_state.show_resolved_bodies
end

function M.set_show_resolved_bodies(value)
  vim.validate({
    value = { value, "boolean" },
  })

  panel_state.show_resolved_bodies = value
end

function M.toggle_show_resolved_bodies()
  panel_state.show_resolved_bodies = not panel_state.show_resolved_bodies
  return panel_state.show_resolved_bodies
end

function M.get_selected_thread_id(opts)
  opts = opts or {}
  vim.validate({
    opts = { opts, "table" },
  })

  local bufnr = opts.bufnr or panel_state.bufnr
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local line = opts.cursor_line
  if type(line) ~= "number" then
    if bufnr == panel_state.bufnr and panel_state.winid and vim.api.nvim_win_is_valid(panel_state.winid) then
      line = vim.api.nvim_win_get_cursor(panel_state.winid)[1]
    else
      return nil
    end
  end

  local thread_id_by_line = panel_state.thread_id_by_bufnr[bufnr]
  if type(thread_id_by_line) ~= "table" then
    return nil
  end

  return thread_id_by_line[line]
end

return M
