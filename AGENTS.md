# AGENTS.md — Herdr machine bootstrap

**MUST use the Grok `lsp` tool for all Rust, Go, and Lua work** (`rust-analyzer` / `gopls` / `lua-language-server`). Prefer live source on this machine via LSP over docs or memory.

## Dotfiles, not a transformer

This repo is a **dotfiles-style machine layout**. The version-controlled tree is what we install: paths and filenames should match (or closely mirror) their live destinations so `install.sh` is mostly **copy / link / sync**, not invent.

| Repo path | Live destination (example) |
|-----------|----------------------------|
| `.grok/*` | `~/.grok/*` (plus project `.grok` when working here) |
| `.grok/rules/`, `hooks/`, `agents/`, `personas/` | `~/.grok/rules|hooks|agents|personas/` (machine-wide harness) |
| `config/herdr/` | `~/.config/herdr/` |
| `config/wezterm/` | `~/.config/wezterm/` |
| `policy/` | pinned under `~/.config/herdr-bootstrap/` (or sibling lookup) |
| `bin/` | helpers on `PATH` / called as `bin/…` |

**Requirement for agents:** Prefer adding or editing files in the shape they will have on disk. Do **not** invent alternate layouts, intermediate formats, or rename-on-install schemes — every mismatch forces more setup code. Thin sync scripts and `install.sh` phases are fine; structural translation is not. Plugins/skills live only in [herdr-plugins](https://github.com/tyler-jewell/herdr-plugins), not here.

**Harness surfaces:** put policy in the native Grok slot (rules / hooks / agents / personas / skills / config) even if only one consumer. CAPS `NEVER`/`ALWAYS`/`MUST` may open the **rules steward** (right Herdr pane) via `rules-steward` + `.grok/hooks/policy-caps.json`.

This repository **orchestrates** a greenfield install of Herdr, WezTerm (outer terminal), Node/npx, Grok, agent skills, and integrations. It is **not** the Herdr source tree and **not** the plugin monorepo.

**Plugins live in** [tyler-jewell/herdr-plugins](https://github.com/tyler-jewell/herdr-plugins). `install.sh` clones/pulls that repo and installs **all** plugins (every `*/herdr-plugin.toml`).

## Canonical development URLs

Use these for all Herdr development, configuration, plugins, and product context. Prefer them over inventing CLI flags, keybindings, or config keys.

| Resource | URL |
|----------|-----|
| Docs | https://herdr.dev/docs/ |
| Plugins | https://herdr.dev/plugins/ |
| Blog | https://herdr.dev/blog/ |
| Source | https://github.com/herdrdev/herdr |
| Human first-run / agent teaching guide | https://herdr.dev/agent-guide.md |
| Agent skill (control Herdr when `HERDR_ENV=1`) | https://raw.githubusercontent.com/herdrdev/herdr/master/skills/herdr/SKILL.md |

## What `install.sh` does

Idempotent phases:

1. Ensure `~/.local/bin` on PATH (shell rc + current process)
2. Portable Node LTS → `~/.local/node` + `node`/`npm`/`npx` in `~/.local/bin` (if missing or &lt; 20)
3. Herdr binary via official installer / `herdr update` (never attaches TUI, never `server stop`)
4. WezTerm (outer terminal) if missing + sync `config/wezterm` → `~/.config/wezterm` (Kitty keyboard/graphics for Herdr)
5. Grok CLI via official installer if missing
6. `npx --yes skills add herdrdev/herdr --skill herdr -g -y` (canonical skill only)
7. Agent-native skill symlink workaround (skills#1874 / PR#1883)
8. `herdr integration install` for agents whose config dirs already exist (always Grok if `~/.grok` exists)
9. Verify paths and versions

Correct skill install command:

```bash
npx --yes skills add herdrdev/herdr --skill herdr -g -y
```

**Wrong** (do not use): `npx skill install herdr`

**Never** pass `--agent '*'` — it creates dozens of empty agent homes under `$HOME`.

## `npx skills` global install: agent-native dir workaround

**Bug:** [vercel-labs/skills#1874](https://github.com/vercel-labs/skills/issues/1874) — global installs write only to canonical `~/.agents/skills/` for “universal” agents and skip agent-native global dirs (Codex, Cursor, Gemini CLI, Antigravity, OpenCode, Windsurf, …). Grok is not in the skills CLI agent table at all, so it also needs a manual link.

**Fix PR (unmerged as of bootstrap):** [vercel-labs/skills#1883](https://github.com/vercel-labs/skills/pull/1883)

**Workaround** (also applied by `install.sh`):

```bash
CANONICAL="$HOME/.agents/skills/herdr"
for dir in \
  "$HOME/.codex/skills" \
  "$HOME/.cursor/skills" \
  "$HOME/.claude/skills" \
  "$HOME/.gemini/skills" \
  "$HOME/.gemini/antigravity/skills" \
  "$HOME/.gemini/antigravity-cli/skills" \
  "$HOME/.config/opencode/skills" \
  "$HOME/.config/amp/agents/skills" \
  "$HOME/.codeium/windsurf/skills" \
  "$HOME/.grok/skills"
do
  mkdir -p "$dir"
  ln -sfn "$(python3 -c "import os; print(os.path.relpath('$CANONICAL', '$dir'))")" "$dir/herdr"
done
```

Canonical skill: `~/.agents/skills/herdr`. Drop the workaround once #1883 ships and a reinstall populates native dirs.

## Multi-project spaces (convention)

Herdr core has **no** per-project `config.toml`. This repo’s convention:

- **Global UI (versioned here):** [`config/herdr/config.toml`](./config/herdr/config.toml) → synced to `~/.config/herdr/config.toml` via [`bin/sync-herdr-config`](./bin/sync-herdr-config) (also run from `install.sh`). Includes agent pane labels, toast defaults, **`experimental.kitty_graphics`**, and shared plugin keybindings (maps, docs-wiki). **All agents on the machine see this file** after sync/reload.
- **Per-project space layout (git):** `<repo>/.herdr/config.toml`
- **Discovery tool:** [`bin/herdr-discover`](./bin/herdr-discover) — scan `$HOME` for that file, open workspaces, apply layout only when the space is **fresh**
- **Rules:** [`docs/HERDR_RULES.md`](./docs/HERDR_RULES.md)

Do not invent a second global catalog or claim native Herdr project config. Match workspaces by pane **cwd** (via `herdr api snapshot`), never by label alone.

After changing `config/herdr/config.toml`, run `bin/sync-herdr-config` (or re-run `install.sh`) so every agent session picks up the update.

## Language equipping (LSP) vs quality rules

| Concern | Where |
|---------|--------|
| LSP servers on PATH + doctor | Herdr plugins `jewell.go-lang` / `jewell.rust-lang` / `jewell.lua-lang` (`status`, `ensure`, `doctor`) |
| Project LSP map | [`.grok/lsp.json`](./.grok/lsp.json) → synced to `~/.grok/lsp.json` |
| Quality / MUST–NEVER policy | **Rules steward** + versioned [`.grok/rules/`](./.grok/rules/) (e.g. `language-lsp.md`) |

Plugin sources: **https://github.com/tyler-jewell/herdr-plugins** only.  
This bootstrap repo has **no** `plugins/` trees (skills may still be installed from the monorepo).

- Do **not** reintroduce code-gate format/lint hooks; put policy in rules.
- Prefer Grok **`lsp` tool** when editing Rust/Go/Lua.


## Safety rules (agents)

- If `HERDR_ENV` is not `1`, do **not** control panes/agents with the herdr skill; teach the human instead (agent guide).
- Do **not** run bare `herdr` for discovery — it attaches the TUI. Use `herdr --help`, group help, `herdr status`.
- Do **not** run `herdr server stop` unless the human explicitly wants to kill the server and all pane processes.
- Do not invent keybindings, config keys, or CLI flags; read https://herdr.dev/docs/ and the upstream skill.
- Prefer user-local installs under `$HOME` (no sudo).
- Do not auto-close workspaces or re-apply layout on non-fresh spaces without an explicit `--force-layout`.


## Lessons learned (greenfield bootstrap)

1. Fresh macOS often has **no Node/npx** — install portable Node before `npx skills`.
2. Official herdr installer puts the binary in `~/.local/bin` but **does not** always patch shell PATH.
3. Informal `npx skill install herdr` fails; use the official `skills add` form above.
4. Global skill install alone is incomplete until #1883 — always link agent-native dirs (especially `~/.grok/skills`).
5. `--agent '*'` pollutes `$HOME`; target explicit dirs only.
6. Eve/PromptScript may fail global skill install; treat as noise if canonical skill exists.
7. `herdr integration install grok` needs `~/.grok` already present (install Grok first).
8. First human attach: run `herdr` from a **normal** terminal, start the agent in a pane, then use the skill inside Herdr.

## WezTerm (outer terminal)

Herdr runs **inside** a real terminal. This bootstrap prefers **WezTerm** on macOS and Linux:

- Install: existing `wezterm` on PATH → else Homebrew → else portable (no sudo): macOS `~/Applications/WezTerm.app`, Linux AppImage (x86_64) or `.deb` extract (aarch64).
- Config source of truth: `config/wezterm/wezterm.lua` → `bin/sync-wezterm-config` → `~/.config/wezterm/wezterm.lua`
- Required for agents: `enable_kitty_keyboard = true` (WezTerm defaults this off)
- Aligns with Herdr `experimental.kitty_graphics` for image panes
- Optional overrides: `~/.config/wezterm/user.lua` (never overwritten)

Do not invent WezTerm keys for Herdr control; Herdr keybindings live in `config/herdr/config.toml` and https://herdr.dev/docs/keyboard/.

Flags: `--skip-wezterm`, `--skip-wezterm-config-sync`. Override release: `WEZTERM_VERSION=…`.

## Verify

```bash
command -v herdr node npx grok wezterm
herdr --version
node -v
wezterm --version
test -f ~/.agents/skills/herdr/SKILL.md
test -f ~/.grok/skills/herdr/SKILL.md
test -f ~/.config/wezterm/wezterm.lua
grep -q enable_kitty_keyboard ~/.config/wezterm/wezterm.lua
herdr integration status
```

<!-- docs-wiki:start -->
## Project wiki (`docs/`)

This repo’s **live knowledge view** is the markdown wiki under `docs/`.
Rules: lean, non-overlapping topics, **≤280 lines per page**, updated when work lands (before you treat a task as done).

### Before answering project questions
1. Use skill **`docs-wiki`** / `/docs-wiki`, or read `docs/index.md` then the relevant pages.
2. Prefer `docs/status/` for current state.
3. Cite paths under `docs/`.

### When finishing work (agent `done` / before you commit)
1. Distill what changed into the **one** correct `docs/` page (update existing; do not duplicate).
2. Update `docs/index.md` and append a line to `docs/log.md`.
3. Split or trim any page over 280 lines.

Policy pin: `.herdr/config.toml` → `[wiki].policy_version` (machine policy in herdr-bootstrap `policy/llm-wiki.toml`).
Doctor: Herdr action **Docs wiki doctor** or `docs-wiki doctor --current`.
<!-- docs-wiki:end -->
