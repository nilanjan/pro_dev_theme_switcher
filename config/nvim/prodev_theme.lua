-- ProDev Theme Switcher -- follow the menu bar app.
--
-- Installed by the app into ~/.config/nvim/lua and loaded by the
-- `pcall(require, "prodev_theme")` line it appends to init.lua. Delete that line
-- to opt out.
--
-- The app writes the colorscheme name (tokyonight-storm, rose-pine-dawn) and the
-- mode. The colorscheme applies if its plugin is installed -- folke/tokyonight.nvim,
-- rose-pine/neovim -- otherwise only `background` flips, which is enough for any
-- scheme that adapts to it. Re-checked on focus, so a switch lands in running
-- instances without a restart.
local M = {}

local function first_line(path)
  local f = io.open(vim.fn.expand(path))
  if not f then return nil end
  local s = f:read("*l")
  f:close()
  return s and s:match("^%s*(.-)%s*$")
end

function M.apply()
  local name = first_line("~/.local/share/nvim/theme_state.txt")
  local mode = first_line("~/.cache/macos_theme_mode") or "dark"
  if not name or name == "" or name == vim.g.prodev_theme_applied then return end
  if pcall(vim.cmd.colorscheme, name) then
    vim.g.prodev_theme_applied = name
  elseif vim.o.background ~= mode then
    vim.o.background = mode  -- not recorded, so the colorscheme is retried once its plugin loads
  end
end

M.apply()
vim.api.nvim_create_autocmd({ "FocusGained", "VimResume" }, {
  group = vim.api.nvim_create_augroup("ProDevTheme", { clear = true }),
  callback = M.apply,
})
return M
