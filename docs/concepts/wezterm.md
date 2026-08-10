---
title: WezTerm outer terminal
updated: 2026-08-10
tags: [concepts, wezterm, herdr]
summary: WezTerm as the recommended outer terminal for Herdr on macOS/Linux
---

# WezTerm outer terminal

Herdr is a **multiplexer** that runs *inside* a terminal emulator. This bootstrap installs and configures **WezTerm** as that outer terminal on macOS and Linux.

## Why WezTerm

| Need | WezTerm setting |
|------|-----------------|
| Agent modified keys (Shift+Enter, …) | `enable_kitty_keyboard = true` |
| Herdr image/map panes | `enable_kitty_graphics` + Herdr `experimental.kitty_graphics` |
| Cross-platform | macOS + Linux portable install (no sudo) |
| Herdr prefix / `ctrl+alt` chords | Defaults do not steal `ctrl+b` or `ctrl+alt+*` |

## Layout

- Source of truth: `config/wezterm/wezterm.lua`
- Live: `~/.config/wezterm/wezterm.lua` via `bin/sync-wezterm-config`
- Optional: `~/.config/wezterm/user.lua` (never overwritten)

## Workflow

1. Open **WezTerm**
2. In a normal shell (not already in Herdr): `herdr`
3. Agents run in Herdr panes (`HERDR_ENV=1`)

Do not nest `herdr` inside a Herdr pane. Do not use WezTerm’s own mux as a second multiplexer for the same work.

## Install paths

See `install.sh` / `config/wezterm/README.md`: existing binary → Homebrew → portable zip/AppImage/deb-extract.

## Upstream

- https://herdr.dev/docs/keyboard/
- https://wezterm.org/config/files.html
