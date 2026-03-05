local T = require("mini.test")

local set = T.new_set()

set["map_line resolves diff position for file line"] = function()
  local positions = require("git-review.positions")
  local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -10,2 +10,3 @@
 local M = {}
+local x = 1
 return M
]]

  local mapped = positions.map_line(diff, "lua/git-review/init.lua", 11)

  assert(type(mapped) == "table", "Expected mapped position table")
  assert(mapped.position == 2, "Expected line 11 to map to diff position 2")
end

set["map_range resolves start and end diff positions"] = function()
  local positions = require("git-review.positions")
  local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -10,2 +10,3 @@
 local M = {}
+local x = 1
 return M
]]

  local mapped = positions.map_range(diff, "lua/git-review/init.lua", 10, 12)

  assert(type(mapped) == "table", "Expected mapped range table")
  assert(mapped.start_position == 1, "Expected start line to map to diff position 1")
  assert(mapped.position == 3, "Expected end line to map to diff position 3")
end

set["map_line returns nil with message when line is unmapped"] = function()
  local positions = require("git-review.positions")
  local diff = [[
diff --git a/lua/git-review/init.lua b/lua/git-review/init.lua
index 1111111..2222222 100644
--- a/lua/git-review/init.lua
+++ b/lua/git-review/init.lua
@@ -1,1 +1,1 @@
-local old = 1
+local new = 1
]]

  local mapped, err = positions.map_line(diff, "lua/git-review/init.lua", 99)

  assert(mapped == nil, "Expected no mapping for out-of-range line")
  assert(type(err) == "string", "Expected unmapped-line error message")
end

return set
