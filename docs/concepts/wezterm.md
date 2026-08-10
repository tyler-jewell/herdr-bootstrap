---
title: WezTerm outer terminal
updated: 2026-08-10
tags: [concepts, wezterm, herdr]
summary: WezTerm is the required outer terminal; install.sh registers it as default (no sudo)
---

# WezTerm outer terminal

Herdr is a **multiplexer** that runs *inside* a terminal emulator. This bootstrap treats **WezTerm** as the **required** outer terminal on macOS and Linux — not an optional preference.

## Requirement

`install.sh` → `install_wezterm` always:

1. Installs the binary (if missing)
2. Syncs Herdr-tuned config
3. Registers WezTerm as the default terminal **user-local, no sudo**

Only `--skip-wezterm` skips this (break-glass / CI). There is no separate “set default” flag.

| Platform | What install does |
|----------|-------------------|
| **Both** | `export TERMINAL=wezterm` in `~/.zshrc` / `~/.bashrc` |
| **Linux** | `.desktop` under `~/.local/share/applications/`, `xdg-terminals.list`, GNOME `gsettings`, KDE keys when present, `$HOME/.local/bin/x-terminal-emulator` → wezterm |
| **macOS** | Launch Services register of `WezTerm.app`; **no** OS API to replace Terminal.app system-wide — open WezTerm.app for Herdr |

Debian/Ubuntu system `update-alternatives` for `/usr/bin/x-terminal-emulator` needs **sudo** and is intentionally **not** run (house safety: no sudo). User PATH shadow covers normal sessions.

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

1. Open **WezTerm** (required outer terminal)
2. In a normal shell (not already in Herdr): `herdr`
3. Agents run in Herdr panes (`HERDR_ENV=1`)

Do not nest `herdr` inside a Herdr pane. Do not use WezTerm’s own mux as a second multiplexer for the same work.

## Install paths

See `install.sh` / `config/wezterm/README.md`: existing binary → Homebrew → portable zip/AppImage/deb-extract. Default-terminal registration runs after binary + config sync.

## Upstream

- https://herdr.dev/docs/keyboard/
- https://wezterm.org/config/files.html
