-- WezTerm config for Herdr outer-terminal use (managed by herdr-bootstrap).
-- Source of truth: herdr-bootstrap/config/wezterm/
-- Synced to: ~/.config/wezterm/wezterm.lua  (bin/sync-wezterm-config / install.sh)
--
-- Herdr runs *inside* this terminal (do not nest herdr inside herdr).
-- Docs: https://herdr.dev/docs/keyboard/  |  https://wezterm.org/config/files.html

local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- ---------------------------------------------------------------------------
-- Protocols Herdr + coding agents rely on
-- ---------------------------------------------------------------------------

-- Kitty keyboard protocol: accurate modified keys (Shift+Enter, Super chords, …).
-- Default is false; agents and modern TUIs request this via escape sequences.
-- https://wezterm.org/config/lua/config/enable_kitty_keyboard.html
config.enable_kitty_keyboard = true

-- Kitty graphics protocol: Herdr experimental.kitty_graphics (map previews, images).
-- Supported by WezTerm; set explicitly so image panes work when Herdr enables them.
-- Unknown on ancient builds: ignore failure via pcall below.
pcall(function()
  config.enable_kitty_graphics = true
end)

-- Prefer WezTerm terminfo when present (undercurl, styled underlines, etc.).
config.term = 'wezterm'

-- ---------------------------------------------------------------------------
-- macOS Option / Alt (Herdr ctrl+alt chords + word-nav sequences)
-- ---------------------------------------------------------------------------
-- Left Option acts as Alt (sends ESC- sequences) so chords reach Herdr/apps.
-- Right Option keeps macOS compose for special characters.
-- https://herdr.dev/docs/keyboard/  (plain alt is awkward on macOS terminals)
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = true

-- ---------------------------------------------------------------------------
-- Mouse (Herdr is mouse-first: click panes, drag splits, right-click menus)
-- ---------------------------------------------------------------------------
-- WezTerm already forwards mouse reporting when the app (Herdr) enables it.
-- Keep scrollback for the outer shell only; Herdr owns pane scrollback inside.
config.scrollback_lines = 10000
config.hide_mouse_cursor_when_typing = true

-- ---------------------------------------------------------------------------
-- Keys: do not steal Herdr’s prefix or safe direct chords
-- ---------------------------------------------------------------------------
-- WezTerm defaults do not bind ctrl+b (Herdr prefix) or ctrl+alt+* family.
-- Keep defaults (copy/paste, font size, Super-tabs). Herdr is the multiplexer —
-- prefer one WezTerm tab running `herdr` rather than WezTerm’s own pane mux.
--
-- Disable only bindings that would eat common agent / Herdr input if needed
-- later; leave keys table empty so defaults remain.
config.keys = config.keys or {}

-- ---------------------------------------------------------------------------
-- Window / UX (sane defaults for long agent sessions)
-- ---------------------------------------------------------------------------
config.audible_bell = 'Disabled'
config.window_close_confirmation = 'NeverPrompt'
config.skip_close_confirmation_for_processes_named = {
  'bash',
  'sh',
  'zsh',
  'fish',
  'tmux',
  'nu',
  'cmd.exe',
  'pwsh.exe',
  'powershell.exe',
}

-- Larger default geometry for multi-pane Herdr layouts
config.initial_cols = 140
config.initial_rows = 40

-- ---------------------------------------------------------------------------
-- Optional user overrides (not managed; survives re-sync)
-- ---------------------------------------------------------------------------
-- Create ~/.config/wezterm/user.lua that returns a function(config) or a table
-- of assignments, e.g.:
--   return function(config)
--     config.font_size = 13
--     config.color_scheme = 'Catppuccin Mocha'
--   end
local user_ok, user = pcall(require, 'user')
if user_ok and user ~= nil then
  if type(user) == 'function' then
    user(config)
  elseif type(user) == 'table' then
    if type(user.apply_to_config) == 'function' then
      user.apply_to_config(config)
    else
      for k, v in pairs(user) do
        config[k] = v
      end
    end
  end
end

return config
