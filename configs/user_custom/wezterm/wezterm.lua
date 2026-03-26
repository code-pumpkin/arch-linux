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
  foreground = '#b8b4af',
  background = '#000000',
  cursor_fg = '#000000',
  cursor_bg = '#e6b450',
  selection_fg = '#000000',
  selection_bg = '#e6b450',
  ansi = { '#000000', '#d95757', '#7fd962', '#e6b450', '#73b8ff', '#d2a6ff', '#95e6cb', '#b8b4af' },
  brights = { '#484d58', '#d95757', '#7fd962', '#e6b450', '#73b8ff', '#d2a6ff', '#95e6cb', '#b8b4af' },
}
config.window_background_opacity = 1.0
config.hide_tab_bar_if_only_one_tab = true
config.window_padding = { left = 8, right = 8, top = 8, bottom = 8 }

return config
