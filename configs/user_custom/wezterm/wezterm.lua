local wezterm = require 'wezterm'
local config = {}

config.font = wezterm.font_with_fallback {
  { family = 'JetBrainsMono Nerd Font' },
  { family = 'Noto Sans Arabic', scale = 1.3 },
  'Noto Serif',
  'Noto Sans',
}
config.font_size = 13.0
config.harfbuzz_features = { 'calt=1', 'clig=1', 'liga=1', 'rlig=1', 'rclt=1', 'ccmp=1' }
config.bidi_enabled = true
config.bidi_direction = "AutoLeftToRight"
config.line_height = 1.15

-- Match kitty color scheme
config.colors = {
  foreground = '#C8CBCD',
  background = '#000000',
  cursor_fg = '#000000',
  cursor_bg = '#BEC9C6',
  selection_fg = '#000000',
  selection_bg = '#BEC9C6',
  ansi    = { '#000000', '#CC6666', '#7A9E8E', '#C4A882', '#8AABB0', '#A899B8', '#8FB5A4', '#BEC9C6' },
  brights = { '#5A5E62', '#CC6666', '#8FB5A4', '#D4BC96', '#9BBEC4', '#B8ADCC', '#9EC4B3', '#C8CBCD' },
}
config.window_background_opacity = 1.0
config.hide_tab_bar_if_only_one_tab = true
config.window_padding = { left = 8, right = 8, top = 8, bottom = 8 }

return config
