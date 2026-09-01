-- Rosé Pine Dawn — canonical palette only (https://rosepinetheme.com).
-- base46's bundled `rosepine-dawn` mixes in Moon/Main accents (#eb6f92, #f6c177,
-- #c4a7e7) and invented warm tints; this uses strictly the 15 official Dawn roles.
--   base #faf4ed  surface #fffaf3  overlay #f2e9e1
--   muted #9893a5 subtle #797593   text #575279
--   love #b4637a  gold #ea9d34     rose #d7827e
--   pine #286983  foam #56949f     iris #907aa9
--   hl low #f4ede8  hl med #dfdad9  hl high #cecacd

---@type Base46Table
local M = {}

M.base_30 = {
  white         = "#575279", -- text
  black         = "#faf4ed", -- base (theme bg)
  darker_black  = "#f2e9e1", -- overlay
  black2        = "#fffaf3", -- surface
  one_bg        = "#fffaf3",
  one_bg2       = "#f2e9e1",
  one_bg3       = "#dfdad9", -- highlight med
  grey          = "#9893a5", -- muted
  grey_fg       = "#797593", -- subtle
  grey_fg2      = "#9893a5",
  light_grey    = "#797593",
  red           = "#b4637a", -- love
  baby_pink     = "#d7827e", -- rose
  pink          = "#d7827e",
  line          = "#dfdad9",
  green         = "#286983", -- pine
  vibrant_green = "#56949f", -- foam
  nord_blue     = "#56949f",
  blue          = "#286983",
  yellow        = "#ea9d34", -- gold
  sun           = "#ea9d34",
  purple        = "#907aa9", -- iris
  dark_purple   = "#907aa9",
  teal          = "#56949f",
  orange        = "#d7827e",
  cyan          = "#56949f",
  statusline_bg = "#fffaf3",
  lightbg       = "#f2e9e1",
  pmenu_bg      = "#286983",
  folder_bg     = "#56949f",
}

M.base_16 = {
  base00 = "#faf4ed", -- base
  base01 = "#fffaf3", -- surface
  base02 = "#f2e9e1", -- overlay
  base03 = "#9893a5", -- muted
  base04 = "#797593", -- subtle
  base05 = "#575279", -- text
  base06 = "#575279",
  base07 = "#cecacd", -- highlight high
  base08 = "#b4637a", -- love
  base09 = "#ea9d34", -- gold
  base0A = "#d7827e", -- rose
  base0B = "#286983", -- pine
  base0C = "#56949f", -- foam
  base0D = "#907aa9", -- iris
  base0E = "#ea9d34", -- gold
  base0F = "#9893a5", -- muted
}

M.type = "light"

M.polish_hl = {
  syntax = {
    Type = { fg = M.base_30.teal },
  },
  treesitter = {
    ["@type.builtin"] = { fg = M.base_30.teal, bold = true },
    ["@variable.parameter"] = { fg = M.base_30.purple },
  },
}

M = require("base46").override_theme(M, "rose-pine-dawn")

return M
