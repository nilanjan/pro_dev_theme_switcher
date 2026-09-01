# Neovim edits that can't be shipped as whole files

The two `.lua` theme files here are standalone and installed by `make install-config`.
These three are *edits* to your own config, so apply them by hand:

**`lua/utils/theme_manager.lua`** — add before `function M.apply_theme`:
```lua
-- Re-read the state file and apply it, WITHOUT persisting or re-syncing tmux.
-- Called on FocusGained so an external switcher lands in running instances.
function M.reload_from_disk()
  local t = M.get_current_theme()
  if t ~= vim.g._ngthmch_last then
    vim.g._ngthmch_last = t
    apply_preview(t)
  end
end
```
Also add `"tokyonight-storm"` to `themes.dark` and `"rose-pine-dawn"` to `themes.light`
(first in each list so `toggle_mode()` prefers them).

**`lua/options.lua`** — append:
```lua
vim.api.nvim_create_autocmd({ "FocusGained", "VimResume" }, {
  callback = function() require("utils.theme_manager").reload_from_disk() end,
})
```

**`lua/mappings.lua`** — point `<leader>tt` at the app so the keybinding and the
menu bar can't disagree; see README.
