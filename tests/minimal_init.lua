local config_path = vim.fn.stdpath("config")
vim.opt.runtimepath:remove(config_path)
vim.opt.runtimepath:remove(config_path .. "/after")

vim.opt.runtimepath:append(".")
package.path = table.concat({ "./?.lua", "./?/init.lua", package.path }, ";")

local ok, mini_test = pcall(require, "mini.test")
if ok then
  _G.MiniTest = mini_test
end
