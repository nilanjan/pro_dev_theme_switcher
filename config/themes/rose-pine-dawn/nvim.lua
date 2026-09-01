-- Rosé Pine Dawn — canonical hues, assigned by ROLE rather than by palette name.
-- base46's bundled `rosepine-dawn` mixes in Moon/Main accents (#eb6f92, #f6c177,
-- #c4a7e7) and invented warm tints; this stays inside the official Dawn hues.
-- See config/alacritty/light.toml for the full rationale, check.sh for the gate.
--
--   canvas #f2e9e1 (overlay) · raised #dfdad9 (hl med) · selected #cecacd (hl high)
--   text #575279 (6.07:1) · muted #797593 (3.67:1) · dim #9893a5
--
-- Surfaces step DOWN from the canvas: a light theme separates surfaces by
-- darkening; only a dark theme lightens. Dawn's canonical base #faf4ed is 4% off
-- pure white, which is why it read as bland and why elevation was invisible.
--
-- Three accents fall under 3:1 as text on the canvas and are walked down in HLS
-- lightness only -- hue and saturation preserved -- until they clear it:
--   gold #ea9d34 -> #bf7614 · rose #d7827e -> #cf6864 · foam #56949f -> #53909a
-- love #b4637a, pine #286983 and iris #907aa9 already pass, so they are unchanged.

---@type Base46Table
local M = {}

M.base_30 = {
  white         = "#575279", -- text
  black         = "#f2e9e1", -- base (theme bg)
  darker_black  = "#dfdad9", -- overlay
  black2        = "#dfdad9", -- raised
  one_bg        = "#dfdad9",
  one_bg2       = "#cecacd",
  one_bg3       = "#cecacd", -- selected
  grey          = "#9893a5", -- muted
  grey_fg       = "#797593", -- subtle
  grey_fg2      = "#9893a5",
  light_grey    = "#797593",
  red           = "#b4637a", -- love
  baby_pink     = "#cf6864", -- rose
  pink          = "#cf6864",
  line          = "#cecacd",
  green         = "#286983", -- pine
  vibrant_green = "#53909a", -- foam
  nord_blue     = "#53909a",
  blue          = "#286983",
  yellow        = "#bf7614", -- gold
  sun           = "#bf7614",
  purple        = "#907aa9", -- iris
  dark_purple   = "#907aa9",
  teal          = "#53909a",
  orange        = "#cf6864",
  cyan          = "#53909a",
  statusline_bg = "#dfdad9",
  lightbg       = "#dfdad9",
  pmenu_bg      = "#286983",
  folder_bg     = "#53909a",
}

M.base_16 = {
  base00 = "#f2e9e1", -- canvas
  base01 = "#dfdad9", -- raised
  base02 = "#cecacd", -- selected
  base03 = "#9893a5", -- muted
  base04 = "#797593", -- subtle
  base05 = "#575279", -- text
  base06 = "#575279",
  base07 = "#cecacd", -- highlight high
  base08 = "#b4637a", -- love
  base09 = "#bf7614", -- gold
  base0A = "#cf6864", -- rose
  base0B = "#286983", -- pine
  base0C = "#53909a", -- foam
  base0D = "#907aa9", -- iris
  base0E = "#bf7614", -- gold
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
