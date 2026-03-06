local T = require("mini.test")

local set = T.new_set()

set["panel.render_lines renders markdown thread/comment structure"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "b",
    },
  })

  assert(type(lines) == "table", "Expected panel.render_lines to return a list")
  assert(lines[1] == "## Thread 1 · 1 comment · unresolved", "Expected first rendered line to include thread metadata")
  assert(lines[2] == "### a", "Expected author heading line")
  assert(lines[3] == "> b", "Expected markdown quote body line")
end

set["panel.render_lines supports custom empty message"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({}, {
    empty_message = "No review threads for current buffer.",
  })

  assert(lines[1] == "No review threads for current buffer.", "Expected custom empty-state message")
end

set["panel.render_lines falls back for whitespace-only body"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "   \n\n",
    },
  })

  assert(lines[3] == "> (no body)", "Expected whitespace-only body to render fallback text")
end

set["panel.render_lines never renders nil body line"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "\n",
    },
  })

  assert(lines[3] ~= "> nil", "Expected first rendered body line to never include nil")
end

set["panel.render_lines normalizes html anchors to markdown links"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "See <a href=\"https://example.com\">docs</a>",
    },
  })

  assert(lines[3] == "> See [docs](https://example.com)", "Expected anchor tag to render as markdown link")
end

set["panel.render_lines normalizes links inside paragraph tags"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = 'See <p><a href="https://example.com/docs">docs</a></p>next',
    },
  })

  assert(lines[3] == "> See", "Expected text before paragraph to remain visible")
  assert(lines[4] == "> [docs](https://example.com/docs)", "Expected link inside paragraph to normalize")
  assert(lines[5] == "> next", "Expected trailing text after paragraph to remain visible")
end

set["panel.render_lines normalizes paragraph tags case-insensitively with attributes"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = '<P class="note">first</P><p data-x="1">second</p>',
    },
  })

  assert(lines[3] == "> first", "Expected uppercase paragraph tag normalization")
  assert(lines[4] == "> second", "Expected paragraph tags with attributes to normalize")
end

set["panel.render_lines folds html comments to placeholder"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "before <!-- hidden --> after",
    },
  })

  assert(lines[3] == "> before [HTML comment hidden] after", "Expected html comment to fold")
end

set["panel.render_lines keeps folded html comments adjacent to punctuation"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "foo<!--x-->,bar",
    },
  })

  assert(lines[3] == "> foo [HTML comment hidden],bar", "Expected folded html comment to avoid spacing before punctuation")
end

set["panel.render_lines folds multiline html comments"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "<!-- line one\nline two -->",
    },
  })

  assert(lines[3] == "> [HTML comment hidden]", "Expected multiline html comment fold placeholder")
end

set["panel.render_lines preserves mixed paragraph and folded comment ordering"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = 'intro<!-- hidden --><p><a href="https://example.com/docs">docs</a></p>outro',
    },
  })

  assert(lines[3] == "> intro [HTML comment hidden]", "Expected folded html comment to remain readable before paragraph content")
  assert(lines[4] == "> [docs](https://example.com/docs)", "Expected link inside paragraph to normalize in-order")
  assert(lines[5] == "> outro", "Expected trailing text after paragraph to remain visible")
end

set["panel.render_lines folds unterminated html comment to end of body"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "visible <!-- hidden\nstill hidden",
    },
  })

  assert(lines[3] == "> visible [HTML comment hidden]", "Expected unterminated html comment to fold")
end

set["panel.render_lines preserves literal folded-comment placeholder text"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "literal[HTML comment hidden],text",
    },
  })

  assert(lines[3] == "> literal[HTML comment hidden],text", "Expected literal placeholder text without html comment markers to remain unchanged")
end

set["panel.render_lines normalizes inline html emphasis code and breaks"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "Top<br/>Use <code>x</code> with <strong>bold</strong> and <em>italics</em>",
    },
  })

  assert(lines[3] == "> Top", "Expected br tag to split body into a new rendered line")
  assert(lines[4] == "> Use `x` with **bold** and *italics*", "Expected inline html tags to normalize to markdown")
end

set["panel.render_lines normalizes non-self-closing br tags"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "Top<br>Bottom",
    },
  })

  assert(lines[3] == "> Top", "Expected non-self-closing br tag to split body into a new rendered line")
  assert(lines[4] == "> Bottom", "Expected text after non-self-closing br tag on next rendered line")
end

set["panel.render_lines normalizes break tags case-insensitively"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "Top<BR>Middle<Br/>Bottom",
    },
  })

  assert(lines[3] == "> Top", "Expected uppercase BR tag to split body into a new rendered line")
  assert(lines[4] == "> Middle", "Expected mixed-case Br tag to split body into a new rendered line")
  assert(lines[5] == "> Bottom", "Expected trailing text after mixed-case break tag on next rendered line")
end

set["panel.render_lines normalizes b and i tags"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "Use <b>bold</b> and <i>italics</i>",
    },
  })

  assert(lines[3] == "> Use **bold** and *italics*", "Expected b and i tags to normalize to markdown emphasis")
end

set["panel.render_lines normalizes pre code blocks to fenced markdown"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "<pre><code>local x = 1\nprint(x)</code></pre>",
    },
  })

  assert(lines[3] == "> ```", "Expected pre/code block start to render as fenced markdown")
  assert(lines[4] == "> local x = 1", "Expected first code line inside markdown fence")
  assert(lines[5] == "> print(x)", "Expected second code line inside markdown fence")
  assert(lines[6] == "> ```", "Expected pre/code block end to render as fenced markdown")
end

set["panel.render_lines keeps paragraph normalization around pre code blocks"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "<p>before</p><pre><code>local x = 1</code></pre><p>after</p>",
    },
  })

  assert(lines[3] == "> before", "Expected opening paragraph content before fenced code")
  assert(lines[4] == "> ```", "Expected fenced code start after opening paragraph")
  assert(lines[5] == "> local x = 1", "Expected pre/code body to remain in fenced code")
  assert(lines[6] == "> ```", "Expected fenced code end before trailing paragraph")
  assert(lines[7] == "> after", "Expected trailing paragraph content after fenced code")
end

set["panel.render_lines normalizes blockquote tags to markdown blockquotes"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "<blockquote>quoted line\nsecond line</blockquote>",
    },
  })

  assert(lines[3] == "> > quoted line", "Expected blockquote content to use markdown quote prefix")
  assert(lines[4] == "> > second line", "Expected multiline blockquote content to keep markdown quote prefix")
end

set["panel.render_lines normalizes ul and ol lists to markdown lists"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "<ul><li>one</li><li>two</li></ul>\n<ol><li>alpha</li><li>beta</li></ol>",
    },
  })

  assert(lines[3] == "> - one", "Expected unordered list item to render with markdown bullet")
  assert(lines[4] == "> - two", "Expected second unordered list item to render with markdown bullet")
  assert(lines[5] == "> 1. alpha", "Expected ordered list item to render with numeric markdown prefix")
  assert(lines[6] == "> 2. beta", "Expected second ordered list item numbering")
end

set["panel.render_lines tolerates malformed html list input"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "<ul><li>one<li>two</ul>",
    },
  })

  assert(lines[3] == "> - one", "Expected malformed list input to still render first item")
  assert(lines[4] == "> - two", "Expected malformed list input to still render second item")
end

set["panel.render_lines gracefully handles partial html anchor tags"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "See <a href=\"https://example.com\">docs",
    },
  })

  assert(lines[3] == "> See docs", "Expected partial anchor tag input to preserve visible text without raw html")
end

set["panel.render_lines gracefully handles malformed inline html tags"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "Use <strong>bold and <em>italics",
    },
  })

  assert(lines[3] == "> Use bold and italics", "Expected malformed inline tag input to preserve readable plaintext")
end

set["panel.render_lines strips unknown html tags while preserving inner text"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "Keep <span class=\"warn\">this text</span> visible",
    },
  })

  assert(lines[3] == "> Keep this text visible", "Expected unknown html tags to be stripped while preserving inner text")
end

set["panel.render_lines strips unknown uppercase html tags while preserving inner text"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "Keep <SPAN class=\"warn\">this text</SPAN> visible",
    },
  })

  assert(lines[3] == "> Keep this text visible", "Expected uppercase unknown html tags to be stripped while preserving inner text")
end

set["panel.render_lines strips unknown mixed-case html tags while preserving inner text"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "Keep <SpAn class=\"warn\">this text</SpAn> visible",
    },
  })

  assert(lines[3] == "> Keep this text visible", "Expected mixed-case unknown html tags to be stripped while preserving inner text")
end

set["panel.render_lines strips unknown html tags without stripping preserved angle bracket text"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "Strip <span>noise</span> but keep <https://example.com> <T> </code-review>",
    },
  })

  assert(lines[3] == "> Strip noise but keep <https://example.com> <T> </code-review>", "Expected unknown tags removed while non-html angle-bracket text stays intact")
end

set["panel.render_lines preserves markdown autolink-like angle bracket text"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "Link <https://example.com>",
    },
  })

  assert(lines[3] == "> Link <https://example.com>", "Expected markdown autolink-like text to be preserved")
end

set["panel.render_lines preserves generic angle bracket text"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "Use <T> and <A,B>",
    },
  })

  assert(lines[3] == "> Use <T> and <A,B>", "Expected generic angle-bracket text to be preserved")
end

set["panel.render_lines preserves prefixed closing tokens that are not html tags"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      author = "a",
      body = "Keep </code-review> </stronger> </emphasis> </i18n>",
    },
  })

  assert(lines[3] == "> Keep </code-review> </stronger> </emphasis> </i18n>", "Expected prefixed closing tokens to be preserved")
end

set["panel.render_lines renders reaction summaries when present"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      id = "thread-1",
      comments = {
        {
          author = "alice",
          body = "Top-level feedback",
          reactions = {
            THUMBS_UP = 2,
            HEART = 1,
          },
        },
      },
    },
  })

  assert(lines[4] == "> Reactions: 👍 2  ❤️ 1", "Expected deterministic reaction summary line")
end

set["panel.render maps reaction summary line to selected thread id"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local bufnr = vim.api.nvim_create_buf(false, true)
  panel.render({
    {
      id = "thread-42",
      comments = {
        {
          author = "alice",
          body = "Top-level",
          reactions = {
            THUMBS_UP = 1,
          },
        },
      },
    },
  }, { bufnr = bufnr })

  local thread_id = panel.get_selected_thread_id({
    bufnr = bufnr,
    cursor_line = 4,
  })

  assert(thread_id == "thread-42", "Expected reaction summary line to resolve parent thread id")
end

set["panel.render writes to scratch buffer"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local bufnr = vim.api.nvim_create_buf(false, true)
  local rendered_bufnr = panel.render({
    {
      author = "hubot",
      body = "Nit: extract helper.",
    },
  }, { bufnr = bufnr })

  assert(rendered_bufnr == bufnr, "Expected panel.render to return provided buffer")

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = table.concat(lines, "\n")

  assert(vim.bo[bufnr].buftype == "nofile", "Expected scratch nofile buffer")
  assert(string.find(text, "hubot", 1, true), "Expected author to be rendered")
  assert(string.find(text, "Nit: extract helper.", 1, true), "Expected body to be rendered")
end

set["panel.render_lines renders full thread comments as markdown"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      id = "thread-1",
      comments = {
        {
          author = "alice",
          body = "Top-level feedback\nsecond line",
        },
        {
          author = "bob",
          body = "Reply one",
        },
        {
          author = "carol",
          body = "Reply two",
        },
      },
    },
  })

  assert(type(lines) == "table", "Expected rendered lines table")
  assert(lines[1] == "## Thread 1 · 3 comments · unresolved", "Expected markdown thread heading with comment count and unresolved status")
  assert(lines[2] == "### alice", "Expected top-level comment author heading")
  assert(lines[3] == "> Top-level feedback", "Expected first comment body line")
  assert(lines[4] == "> second line", "Expected continuation body line")
  assert(lines[5] == "> ---", "Expected separator between thread comments")
  assert(lines[6] == "### bob", "Expected first reply heading")
  assert(lines[7] == "> Reply one", "Expected first reply body")
  assert(lines[8] == "> ---", "Expected separator before final thread comment")
  assert(lines[9] == "### carol", "Expected second reply heading")
  assert(lines[10] == "> Reply two", "Expected second reply body")
end

set["panel.render_lines renders resolved status in enriched thread heading"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      id = "thread-1",
      isResolved = true,
      comments = {
        {
          author = "alice",
          body = "Done",
        },
      },
    },
  })

  assert(lines[1] == "## Thread 1 · 1 comment · resolved", "Expected heading to include resolved status")
end

set["panel.render_lines collapses resolved thread body by default"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      id = "thread-1",
      isResolved = true,
      comments = {
        {
          author = "alice",
          body = "Resolved context that should be hidden by default",
        },
      },
    },
  })

  assert(lines[1] == "## Thread 1 · 1 comment · resolved", "Expected heading to preserve resolved status metadata")
  assert(lines[2] == "> (resolved thread collapsed)", "Expected resolved thread body to render collapsed placeholder by default")
  assert(lines[3] == nil, "Expected collapsed resolved thread to omit expanded comment heading/body lines")
end

set["panel.render_lines is deterministic by input and ignores module toggle state"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local threads = {
    {
      id = "thread-1",
      isResolved = true,
      comments = {
        {
          author = "alice",
          body = "Resolved context that should remain collapsed without explicit per-call override",
        },
      },
    },
  }

  panel.set_show_resolved_bodies(true)

  local lines = panel.render_lines(threads)

  assert(lines[1] == "## Thread 1 · 1 comment · resolved", "Expected heading to preserve resolved status metadata")
  assert(lines[2] == "> (resolved thread collapsed)", "Expected render_lines default to remain collapsed regardless of module toggle state")
  assert(lines[3] == nil, "Expected no expanded comment lines without explicit per-call override")
end

set["panel.set_show_resolved_bodies(true) keeps panel.render resolved full body behavior"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  panel.set_show_resolved_bodies(true)

  local bufnr = vim.api.nvim_create_buf(false, true)
  panel.render({
    {
      id = "thread-1",
      isResolved = true,
      comments = {
        {
          author = "alice",
          body = "Resolved context that should be visible when enabled",
        },
      },
    },
  }, { bufnr = bufnr })

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  assert(lines[1] == "## Thread 1 · 1 comment · resolved", "Expected heading to preserve resolved status metadata")
  assert(lines[2] == "### alice", "Expected resolved comment heading when resolved bodies are enabled")
  assert(lines[3] == "> Resolved context that should be visible when enabled", "Expected resolved comment body when resolved bodies are enabled")
end

set["panel.render_lines per-call show_resolved_bodies override takes precedence without mutation"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  panel.set_show_resolved_bodies(false)

  local lines = panel.render_lines({
    {
      id = "thread-1",
      isResolved = true,
      comments = {
        {
          author = "alice",
          body = "Resolved context that should be visible by per-call override",
        },
      },
    },
  }, {
    show_resolved_bodies = true,
  })

  assert(lines[2] == "### alice", "Expected per-call show_resolved_bodies=true to override module toggle for render_lines")
  assert(panel.get_show_resolved_bodies() == false, "Expected render_lines per-call override to avoid mutating module toggle state")
end

set["panel.render per-call show_resolved_bodies override takes precedence without mutation"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  panel.set_show_resolved_bodies(true)

  local bufnr = vim.api.nvim_create_buf(false, true)
  panel.render({
    {
      id = "thread-1",
      isResolved = true,
      comments = {
        {
          author = "alice",
          body = "Resolved context that should remain collapsed by per-call override",
        },
      },
    },
  }, {
    bufnr = bufnr,
    show_resolved_bodies = false,
  })

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  assert(lines[2] == "> (resolved thread collapsed)", "Expected render per-call show_resolved_bodies=false to override module toggle")
  assert(panel.get_show_resolved_bodies() == true, "Expected render per-call override to avoid mutating module toggle state")
end

set["panel.render_lines rejects non-boolean opts.show_resolved_bodies"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local ok, err = pcall(panel.render_lines, {}, {
    show_resolved_bodies = "true",
  })

  assert(ok == false, "Expected non-boolean opts.show_resolved_bodies to raise validation error in render_lines")
  assert(type(err) == "string" and err:find("boolean", 1, true), "Expected render_lines validation error to mention boolean type")
end

set["panel.render rejects non-boolean opts.show_resolved_bodies"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local ok, err = pcall(panel.render, {}, {
    show_resolved_bodies = "true",
  })

  assert(ok == false, "Expected non-boolean opts.show_resolved_bodies to raise validation error in render")
  assert(type(err) == "string" and err:find("boolean", 1, true), "Expected render validation error to mention boolean type")
end

set["panel.toggle_show_resolved_bodies flips state and returns new value"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  assert(panel.get_show_resolved_bodies() == false, "Expected resolved body visibility to default to false")

  local first_toggle = panel.toggle_show_resolved_bodies()
  assert(first_toggle == true, "Expected first toggle to return true")
  assert(panel.get_show_resolved_bodies() == true, "Expected first toggle to update stored state")

  local second_toggle = panel.toggle_show_resolved_bodies()
  assert(second_toggle == false, "Expected second toggle to return false")
  assert(panel.get_show_resolved_bodies() == false, "Expected second toggle to restore stored state")
end

set["panel.set_show_resolved_bodies rejects non-boolean input"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local ok, err = pcall(panel.set_show_resolved_bodies, "true")

  assert(ok == false, "Expected non-boolean input to raise a validation error")
  assert(type(err) == "string" and err:find("boolean", 1, true), "Expected validation error to mention boolean type")
end

set["panel.render_lines uses singular heading grammar for one comment"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      id = "thread-1",
      comments = {
        {
          author = "alice",
          body = "Only comment",
        },
      },
    },
  })

  assert(lines[1] == "## Thread 1 · 1 comment · unresolved", "Expected singular grammar in heading for one comment")
end

set["panel.render_lines inserts thread separator between comments in thread"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      id = "thread-1",
      comments = {
        {
          author = "alice",
          body = "Top-level",
        },
        {
          author = "bob",
          body = "Reply",
        },
      },
    },
  })

  assert(lines[4] == "> ---", "Expected separator marker between adjacent comments")
end

set["panel.render_lines does not add trailing separator after final comment"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local lines = panel.render_lines({
    {
      id = "thread-1",
      comments = {
        {
          author = "alice",
          body = "Top-level",
        },
        {
          author = "bob",
          body = "Final reply",
        },
      },
    },
  })

  assert(lines[#lines] == "> Final reply", "Expected final line to remain last comment body")
  assert(lines[#lines - 1] == "### bob", "Expected no separator after final comment")
end

set["panel.render maps every thread comment line to selected thread id"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local bufnr = vim.api.nvim_create_buf(false, true)
  panel.render({
    {
      id = "thread-42",
      comments = {
        {
          author = "alice",
          body = "Top-level",
        },
        {
          author = "bob",
          body = "Reply body",
        },
      },
    },
  }, { bufnr = bufnr })

  local thread_id = panel.get_selected_thread_id({
    bufnr = bufnr,
    cursor_line = 6,
  })

  assert(thread_id == "thread-42", "Expected reply line to resolve parent thread id")
end

set["panel.render maps thread and comment heading lines to selected thread id"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local bufnr = vim.api.nvim_create_buf(false, true)
  panel.render({
    {
      id = "thread-42",
      comments = {
        {
          author = "alice",
          body = "Top-level",
        },
        {
          author = "bob",
          body = "Reply body",
        },
      },
    },
  }, { bufnr = bufnr })

  local thread_heading_id = panel.get_selected_thread_id({
    bufnr = bufnr,
    cursor_line = 1,
  })

  local comment_heading_id = panel.get_selected_thread_id({
    bufnr = bufnr,
    cursor_line = 5,
  })

  assert(thread_heading_id == "thread-42", "Expected thread heading line to resolve parent thread id")
  assert(comment_heading_id == "thread-42", "Expected comment heading line to resolve parent thread id")
end

set["panel.render maps thread separator line to selected thread id"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local bufnr = vim.api.nvim_create_buf(false, true)
  panel.render({
    {
      id = "thread-42",
      comments = {
        {
          author = "alice",
          body = "Top-level",
        },
        {
          author = "bob",
          body = "Reply body",
        },
      },
    },
  }, { bufnr = bufnr })

  local thread_id = panel.get_selected_thread_id({
    bufnr = bufnr,
    cursor_line = 4,
  })

  assert(thread_id == "thread-42", "Expected separator line to resolve parent thread id")
end

set["panel.render maps folded html comment body lines to selected thread id"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local bufnr = vim.api.nvim_create_buf(false, true)
  panel.render({
    {
      id = "thread-42",
      comments = {
        {
          author = "alice",
          body = 'intro<!-- hidden --><p><a href="https://example.com/docs">docs</a></p>outro',
        },
      },
    },
  }, { bufnr = bufnr })

  local folded_line_id = panel.get_selected_thread_id({
    bufnr = bufnr,
    cursor_line = 3,
  })

  local normalized_line_id = panel.get_selected_thread_id({
    bufnr = bufnr,
    cursor_line = 4,
  })

  local trailing_line_id = panel.get_selected_thread_id({
    bufnr = bufnr,
    cursor_line = 5,
  })

  assert(folded_line_id == "thread-42", "Expected folded html comment body line to resolve parent thread id")
  assert(normalized_line_id == "thread-42", "Expected normalized html paragraph line to resolve parent thread id")
  assert(trailing_line_id == "thread-42", "Expected trailing body line to resolve parent thread id")
end

set["panel.render maps collapsed resolved placeholder line to selected thread id"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  local bufnr = vim.api.nvim_create_buf(false, true)
  panel.render({
    {
      id = "thread-42",
      isResolved = true,
      comments = {
        {
          author = "alice",
          body = "Resolved context that should be hidden by default",
        },
      },
    },
  }, { bufnr = bufnr })

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  assert(lines[2] == "> (resolved thread collapsed)", "Expected second line to be collapsed resolved-thread placeholder")

  local thread_id = panel.get_selected_thread_id({
    bufnr = bufnr,
    cursor_line = 2,
  })

  assert(thread_id == "thread-42", "Expected collapsed placeholder line to resolve parent thread id")
end

set["panel.render does not force-open side window by default"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  panel.close()
  local wins_before = #vim.api.nvim_list_wins()

  panel.render({
    {
      id = "thread-1",
      comments = {
        { author = "alice", body = "hello" },
      },
    },
  })

  local wins_after = #vim.api.nvim_list_wins()
  assert(wins_after == wins_before, "Expected passive render to avoid opening a split")
end

set["panel.open and panel.close manage explicit panel lifecycle"] = function()
  package.loaded["git-review.ui.panel"] = nil
  local panel = require("git-review.ui.panel")

  panel.close()
  local wins_before = #vim.api.nvim_list_wins()
  local opened = panel.open()
  local wins_after_open = #vim.api.nvim_list_wins()

  assert(type(opened) == "table", "Expected open result state")
  assert(type(opened.bufnr) == "number", "Expected opened buffer number")
  assert(type(opened.winid) == "number", "Expected opened window id")
  assert(wins_after_open == wins_before + 1, "Expected open to create side window")

  panel.close()
  local wins_after_close = #vim.api.nvim_list_wins()
  assert(wins_after_close == wins_before, "Expected close to remove panel window")
end

return set
