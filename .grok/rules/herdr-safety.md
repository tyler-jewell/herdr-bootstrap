# Herdr safety (machine-wide)

Applies to every agent on every host with Herdr installed.

## MUST

- Prefer user-local installs under `$HOME` (no sudo).
- Use `herdr --help`, group help, or `herdr status` for discovery — never bare `herdr` when you only need info (bare `herdr` attaches the TUI).
- Control panes/tabs/workspaces via the herdr skill **only** when `HERDR_ENV=1` and the human asked for Herdr control. Otherwise teach: https://herdr.dev/agent-guide.md

## NEVER

- Run `herdr server stop` unless the human explicitly wants to kill the server and all pane processes.
- Invent Herdr keybindings, config keys, or CLI flags — read https://herdr.dev/docs/ and the upstream skill.
- Auto-close workspaces or force re-layout on non-fresh spaces without explicit `--force-layout` (or equivalent human intent).
