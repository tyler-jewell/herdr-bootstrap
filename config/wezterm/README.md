# WezTerm (outer terminal for Herdr)

Version-controlled WezTerm config for **macOS and Linux**, tuned so Herdr and coding agents get reliable keyboard + graphics protocols.

## Layout

| Path | Role |
|------|------|
| `wezterm.lua` | Managed config (source of truth in this repo) |
| `~/.config/wezterm/wezterm.lua` | Live config after sync |
| `~/.config/wezterm/user.lua` | Optional local overrides (never overwritten) |

## Why these settings

| Setting | Why |
|---------|-----|
| `enable_kitty_keyboard = true` | Agents request Kitty keyboard protocol (Shift+Enter, etc.). Default is off. |
| `enable_kitty_graphics = true` | Matches Herdr `[experimental] kitty_graphics` for image/map panes. |
| Left Option = Alt (macOS) | `ctrl+alt` and Alt chords reach Herdr; right Option still composes. |
| No grab of `ctrl+b` / `ctrl+alt+*` | Herdr prefix + recommended direct chords stay free. |

Herdr is the multiplexer. Prefer **one WezTerm window** → run `herdr` inside it. Do not nest `herdr` inside a Herdr pane.

## Sync

```bash
bin/sync-wezterm-config
# or
sh install.sh
```

## Install (idempotent via `install.sh`)

**Requirement: Herdr + agent work uses WezTerm.** `install.sh` always:

1. Use existing `wezterm` on `PATH` if present.
2. Else Homebrew: `brew install --cask wezterm` (macOS) / Linuxbrew formula when available.
3. Else portable (no sudo):
   - **macOS:** GitHub release zip → `~/Applications/WezTerm.app`, CLI link in `~/.local/bin`
   - **Linux x86_64:** AppImage → `~/.local/bin/wezterm`
   - **Linux aarch64:** extract `.deb` payload into `~/.local/share/wezterm`, link CLI
4. Sync this config → `~/.config/wezterm/`
5. Register for that workflow (user-local, no sudo): `TERMINAL=wezterm` in shell rc; on Linux also `.desktop`, `xdg-terminals.list`, GNOME/KDE hooks, and `~/.local/bin/x-terminal-emulator` → wezterm.

Only `--skip-wezterm` skips (break-glass). Scope is **Herdr + agents**, not every OS terminal. On macOS open **WezTerm.app** for Herdr (Terminal.app is not replaced system-wide).

## Verify

```bash
command -v wezterm
wezterm --version
test -f ~/.config/wezterm/wezterm.lua
grep -q enable_kitty_keyboard ~/.config/wezterm/wezterm.lua
grep -q 'herdr-bootstrap terminal' ~/.zshrc && echo TERMINAL-ok
# Linux:
test -f ~/.local/share/applications/org.wezfurlong.wezterm.desktop && echo desktop-ok
```

Then open WezTerm, run `herdr` from a normal shell (not inside Herdr).

## References

- [Herdr keyboard](https://herdr.dev/docs/keyboard/)
- [Herdr configuration / Kitty graphics](https://herdr.dev/docs/configuration/)
- [WezTerm config files](https://wezterm.org/config/files.html)
- [enable_kitty_keyboard](https://wezterm.org/config/lua/config/enable_kitty_keyboard.html)
