---
title: WezTerm outer terminal
updated: 2026-08-10
tags: [concepts, wezterm, herdr]
summary: Herdr + agent work uses WezTerm; install equips and registers it for that path
---

# WezTerm outer terminal

Herdr is a **multiplexer** that runs *inside* a terminal emulator.

## Requirement

**Herdr + agent work uses WezTerm.** That is required, not optional.

| In scope | Out of scope |
|----------|--------------|
| Open WezTerm → run `herdr` → agents in panes | Replacing every OS “open a terminal” path forever |
| Herdr-tuned keyboard + graphics config | Claiming macOS Terminal.app is gone |
| User-local hooks so tools spawn WezTerm | `sudo` / system `update-alternatives` |

`install.sh` → `install_wezterm` always:

1. Installs the binary (if missing)
2. Syncs Herdr-tuned config
3. Registers WezTerm for this workflow (user-local, no sudo)

Only `--skip-wezterm` skips (break-glass / CI).

| Platform | Registration |
|----------|----------------|
| **Both** | `export TERMINAL=wezterm` in `~/.zshrc` / `~/.bashrc` |
| **Linux** | `.desktop`, `xdg-terminals.list`, GNOME `gsettings`, KDE keys when present, `$HOME/.local/bin/x-terminal-emulator` → wezterm |
| **macOS** | Launch Services register of `WezTerm.app`; open **WezTerm.app** for Herdr (Terminal.app not replaced OS-wide) |

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

See `install.sh` / `config/wezterm/README.md`: existing binary → Homebrew → portable zip/AppImage/deb-extract. Registration runs after binary + config sync.

## Upstream

- https://herdr.dev/docs/keyboard/
- https://wezterm.org/config/files.html
