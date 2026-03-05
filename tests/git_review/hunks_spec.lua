local T = require("mini.test")

local set = T.new_set()

set["parse_diff converts single file hunk to quickfix item"] = function()
  local hunks = require("git-review.hunks")
  local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,3 +1,4 @@
 local M = {}
+local x = 1
 return M
]]

  local items = hunks.parse_diff(diff)

  assert(type(items) == "table", "Expected parse_diff to return a list")
  assert(#items == 1, "Expected one quickfix item")

  local item = items[1]
  assert(item.filename == "lua/git-review/init.lua", "Expected quickfix filename")
  assert(item.lnum == 1, "Expected quickfix lnum")
  assert(item.end_lnum == 4, "Expected quickfix end_lnum")
  assert(item.text == "@@ -1,3 +1,4 @@", "Expected quickfix text")
  assert(item.hunk_id == "lua/git-review/init.lua:1:4", "Expected stable hunk id")
end

set["parse_diff handles deletion-only hunk with non-decreasing range"] = function()
  local hunks = require("git-review.hunks")
  local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -8,2 +8,0 @@
-line one
-line two
]]

  local items = hunks.parse_diff(diff)

  assert(#items == 1, "Expected one quickfix item")
  local item = items[1]
  assert(item.lnum == 8, "Expected quickfix lnum")
  assert(item.end_lnum == 8, "Expected end_lnum to be clamped for deletion-only hunks")
  assert(item.hunk_id == "lua/git-review/init.lua:8:8", "Expected stable hunk id for deletion-only hunk")
end

set["parse_diff handles multiple hunks in one file"] = function()
  local hunks = require("git-review.hunks")
  local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local one = 1
@@ -10,2 +11,3 @@
 local y = 2
+local z = 3
]]

  local items = hunks.parse_diff(diff)

  assert(#items == 2, "Expected two quickfix items")
  assert(items[1].filename == "lua/git-review/init.lua", "Expected first hunk filename")
  assert(items[1].lnum == 1 and items[1].end_lnum == 3, "Expected first hunk range")
  assert(items[2].filename == "lua/git-review/init.lua", "Expected second hunk filename")
  assert(items[2].lnum == 11 and items[2].end_lnum == 13, "Expected second hunk range")
end

set["parse_diff handles multiple files in one diff"] = function()
  local hunks = require("git-review.hunks")
  local diff = [[
diff --git a/lua/git-review/a.lua b/lua/git-review/a.lua
index 1111111..2222222 100644
--- a/lua/git-review/a.lua
+++ b/lua/git-review/a.lua
@@ -1 +1,2 @@
 local A = {}
+A.x = 1
diff --git a/lua/git-review/b.lua b/lua/git-review/b.lua
index 3333333..4444444 100644
--- a/lua/git-review/b.lua
+++ b/lua/git-review/b.lua
@@ -5,2 +5,3 @@
 local B = {}
+B.y = 2
]]

  local items = hunks.parse_diff(diff)

  assert(#items == 2, "Expected two quickfix items")
  assert(items[1].filename == "lua/git-review/a.lua", "Expected first file hunk")
  assert(items[1].lnum == 1 and items[1].end_lnum == 2, "Expected first file range")
  assert(items[2].filename == "lua/git-review/b.lua", "Expected second file hunk")
  assert(items[2].lnum == 5 and items[2].end_lnum == 7, "Expected second file range")
end

set["parse_diff handles +N form without count"] = function()
  local hunks = require("git-review.hunks")
  local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -3 +5 @@
-local old = 1
+local new = 1
]]

  local items = hunks.parse_diff(diff)

  assert(#items == 1, "Expected one quickfix item")
  local item = items[1]
  assert(item.lnum == 5, "Expected quickfix lnum")
  assert(item.end_lnum == 5, "Expected +N form to default count to one line")
  assert(item.hunk_id == "lua/git-review/init.lua:5:5", "Expected stable hunk id for +N form")
end

set["parse_diff ignores deleted-file hunks with /dev/null target"] = function()
  local hunks = require("git-review.hunks")
  local diff = [[
diff --git a/lua/git-review/deleted.lua b/lua/git-review/deleted.lua
deleted file mode 100644
index 9999999..0000000
--- a/lua/git-review/deleted.lua
+++ /dev/null
@@ -1,2 +0,0 @@
-local deleted = true
-return deleted
]]

  local items = hunks.parse_diff(diff)

  assert(#items == 0, "Expected no quickfix items for deleted-file hunks")
end

set["parse_diff does not carry previous file into deleted-file hunks"] = function()
  local hunks = require("git-review.hunks")
  local diff = [[
diff --git a/lua/git-review/kept.lua b/lua/git-review/kept.lua
index 1111111..2222222 100644
--- a/lua/git-review/kept.lua
+++ b/lua/git-review/kept.lua
@@ -1 +1,2 @@
 local kept = true
+return kept
diff --git a/lua/git-review/deleted.lua b/lua/git-review/deleted.lua
deleted file mode 100644
index 9999999..0000000
--- a/lua/git-review/deleted.lua
+++ /dev/null
@@ -1,2 +0,0 @@
-local deleted = true
-return deleted
]]

  local items = hunks.parse_diff(diff)

  assert(#items == 1, "Expected only non-deleted file hunk to be parsed")
  local item = items[1]
  assert(item.filename == "lua/git-review/kept.lua", "Expected quickfix item to stay on kept file")
  assert(item.lnum == 1 and item.end_lnum == 2, "Expected kept file range")
end

set["parse_diff resolves absolute filename when repo_root is provided"] = function()
  local hunks = require("git-review.hunks")
  local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,2 +1,3 @@
 local M = {}
+local x = 1
 ]]

  local items = hunks.parse_diff(diff, {
    repo_root = "/tmp/example-repo",
  })

  assert(#items == 1, "Expected one quickfix item")
  assert(
    items[1].filename == vim.fs.normalize("/tmp/example-repo/lua/git-review/init.lua"),
    "Expected quickfix filename to be rooted at repo path"
  )
  assert(items[1].hunk_id == "lua/git-review/init.lua:1:3", "Expected stable hunk id")
end

set["parse_diff records added lines per hunk"] = function()
  local hunks = require("git-review.hunks")
  local diff = [[
diff --git a/a.lua b/a.lua
--- a/a.lua
+++ b/a.lua
@@ -1,2 +1,3 @@
 old1
+new2
 old3
 ]]

  local items = hunks.parse_diff(diff)

  assert(#items == 1, "Expected one quickfix item")
  assert(type(items[1].added_lines) == "table", "Expected added_lines table")
  assert(items[1].added_lines[2] == true, "Expected added line to be tracked")
  assert(items[1].added_lines[1] ~= true, "Expected non-added line to stay untracked")
end

set["parse_diff emits empty added_lines for deletion-only hunks"] = function()
  local hunks = require("git-review.hunks")
  local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -8,2 +8,0 @@
-line one
-line two
 ]]

  local items = hunks.parse_diff(diff)

  assert(#items == 1, "Expected one quickfix item")
  assert(type(items[1].added_lines) == "table", "Expected added_lines table")
  assert(next(items[1].added_lines) == nil, "Expected no added lines for deletion-only hunk")
end

set["parse_diff records deleted_blocks for mixed hunks"] = function()
  local hunks = require("git-review.hunks")
  local diff = [[
diff --git a/a.lua b/a.lua
--- a/a.lua
+++ b/a.lua
@@ -1,4 +1,4 @@
 keep1
-drop2
-drop3
+add2
 keep4
 ]]

  local items = hunks.parse_diff(diff)

  assert(#items == 1, "Expected one quickfix item")
  assert(type(items[1].deleted_blocks) == "table", "Expected deleted_blocks table")
  assert(#items[1].deleted_blocks == 1, "Expected one deleted block")
  assert(items[1].deleted_blocks[1].anchor_lnum == 2, "Expected deleted block anchor on new-side line")
  assert(#items[1].deleted_blocks[1].lines == 2, "Expected deleted payload lines")
  assert(items[1].deleted_blocks[1].lines[1] == "drop2", "Expected first deleted payload line")
  assert(items[1].deleted_blocks[1].lines[2] == "drop3", "Expected second deleted payload line")
end

set["parse_diff records deleted_blocks for deletion-only hunks"] = function()
  local hunks = require("git-review.hunks")
  local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -8,2 +8,0 @@
-line one
-line two
 ]]

  local items = hunks.parse_diff(diff)

  assert(#items == 1, "Expected one quickfix item")
  assert(type(items[1].deleted_blocks) == "table", "Expected deleted_blocks table")
  assert(#items[1].deleted_blocks == 1, "Expected one deleted block")
  assert(items[1].deleted_blocks[1].anchor_lnum == 8, "Expected safe anchor for deletion-only hunk")
  assert(#items[1].deleted_blocks[1].lines == 2, "Expected deleted payload lines")
  assert(items[1].deleted_blocks[1].lines[1] == "line one", "Expected first deleted payload line")
  assert(items[1].deleted_blocks[1].lines[2] == "line two", "Expected second deleted payload line")
end

return set
