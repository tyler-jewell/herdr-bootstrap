# Herdr workstyle rules

Conventions for multi-project Herdr use with this bootstrap. **Not** core Herdr product features — Herdr has no native per-project config file.

Canonical Herdr docs: [herdr.dev/docs](https://herdr.dev/docs/). Concepts: [workspace → tab → pane → agent](https://herdr.dev/docs/concepts/).

## Two config layers

| Layer | Path | Role |
|-------|------|------|
| **Global (team)** | **Source:** `herdr-bootstrap/config/herdr/config.toml` → **Live:** `~/.config/herdr/config.toml` via `bin/sync-herdr-config` | Keys, theme, toasts, experimental (e.g. Kitty graphics), shared plugin actions — **same for every agent** |
| **Project** | `<repo>/.herdr/config.toml` | Opt-in marker + space layout + `agent_kind` — **version-controlled with the repo** |
| **Session** | Herdr server snapshot | Live open shape; restored after restart (local, not project VCS) |

`HERDR_CONFIG_PATH` only overrides the **global** config path. It does not select per-project files.

Edit the **bootstrap** global file, then `bin/sync-herdr-config` (or `install.sh`). Do not rely on hand-editing `~/.config/herdr/config.toml` alone — it will be overwritten on the next sync.

## Opt-in discovery

A project becomes a first-class Herdr **space** when it has:

```text
<project-root>/.herdr/config.toml
```

`herdr-discover` walks `$HOME` (with prunes and a depth limit), finds those files, and reconciles open workspaces to match.

- **No file** → never auto-opened.
- **Commit the file** so every machine that clones the repo can open the same space layout.
- Treat the file as **executable config** (commands and agents run as you). Only enable it in repos you trust.

Remote repos are not auto-cloned. Clone them under `$HOME` with `.herdr/config.toml` present; discovery picks them up.

## Topology

1. **One workspace per project root** that ships `.herdr/config.toml`.
2. **Tabs by function**, not by agent name: `agents`, `dev`, `checks`, optional `review` / `deploy`.
3. **Panes** are real terminals. Agents run inside panes; empty shells are fine.
4. Coordinate with **sibling panes** in the current tab. Open a new space only for another project root.
5. Prefer the **default session** with many workspaces. Use named sessions only for hard isolation.

Official model: one workspace per repo, task, or investigation; sidebar rolls up agent state per workspace.

## Agents

6. `agent_kind` comes from the project file (optional per-pane override). Supported kinds are whatever `herdr agent start --kind` accepts on your binary (e.g. `grok`, `codex`, `claude`).
7. Live agent names must be unique among running agents: short form `[a-z][a-z0-9_-]{0,31}` (e.g. `builder`, `reviewer`).
8. On a **shared main checkout**, keep agent scopes narrow (e.g. builder vs read-only reviewer). Herdr does not isolate the filesystem.
9. Do **not** float one live agent across spaces. Share behavior via `AGENTS.md` and skills instead.
10. Only start agents declared in `.herdr/config.toml` during auto-layout.

`agent start` requires an **empty shell pane** and never creates layout. Automation always builds tabs/panes first, then starts agents.

## Multi-agent messaging (not a Herdr “inbox”)

Upstream automation: [Agent automation](https://herdr.dev/docs/agent-automation/). Machine-wide MUST/NEVER: [`.grok/rules/herdr-multi-agent.md`](../.grok/rules/herdr-multi-agent.md).

| Mechanism | What it does | Auto-wakes peer? |
|-----------|--------------|------------------|
| `herdr agent prompt <target> "…"` | Submits text into the agent TUI (may **queue** if already working) | Yes (when turn runs) |
| Files (`docs/inbox/`, tickets, status.md) | Durable coordination | **No** — peer must open them |
| `[ui.toast] delivery = "herdr"` (global config) | Human-visible done/blocked popups | No agent injection |

**Failure modes we hit in practice:** flood `agent.prompt` while all peers are `working` → Grok `#1/#2` backlog of stale INBOX lines; API **Retrying (n/15)** freezes the queue; file “inbox” alone looks like delivery but never runs a turn. Fix is hygiene + wait for idle, not inventing config keys for a non-existent inbox API.

## Reconcile and layout safety

`herdr-discover reconcile`:

| Situation | Action |
|-----------|--------|
| Discovered, no covering workspace | `workspace create --cwd <root> --label <name> --no-focus` |
| Workspace covers project and is **fresh** | Apply layout from `.herdr/config.toml` |
| Workspace covers project, not fresh | Leave alone (session restore / live work) |
| Workspace without `.herdr/config.toml` | Leave alone (scratch space) |
| `enabled = false` | Do not open; do not close if already open |

**Fresh** means all of:

1. `tab_count == 1`
2. `pane_count == 1`
3. That pane has **no** recognized agent

A single pane already running an agent is **not** fresh — do not auto full-stack.

**Identity** uses **canonical pane `cwd`** (from `herdr api snapshot` / `pane list`), not workspace labels (labels are not unique).

Destructive re-layout only with:

```bash
herdr-discover apply --cwd /path/to/project --force-layout
```

Never auto-close spaces. Never run `herdr server stop` unless the human explicitly wants to kill the server and all pane processes.

## Persistence (know which path you rely on)

| Event | Processes | Layout |
|-------|-----------|--------|
| Detach / reattach | Stay alive | Unchanged |
| Server restart | Die | Shape restored; agents may resume via integrations |
| Discover reconcile | Does not stop existing panes | Only mutates **fresh** (or forced) spaces |

Install integrations for agents you resume (`herdr integration install grok`, etc.).

## Day-to-day commands

```bash
# List projects under $HOME with .herdr/config.toml
herdr-discover scan

# Open missing spaces; layout-apply only when fresh
herdr-discover reconcile

# Dry-run
herdr-discover reconcile --dry-run

# Scaffold config in the current repo
herdr-discover init
herdr-discover init --template fullstack

# Force rebuild layout (destructive)
herdr-discover apply --cwd "$PWD" --force-layout
```

Link `bin/herdr-discover` onto your `PATH` (e.g. `~/.local/bin`) or call it via absolute path from this repo.

## Global vs project checklist

| Want | Put it here |
|------|-------------|
| Keys, theme, notifications | `~/.config/herdr/config.toml` |
| Tabs, pane commands, agent kinds for a product | `<repo>/.herdr/config.toml` |
| Agent coding rules | `AGENTS.md`, project skills |
| Live open panes right now | Herdr session (automatic) |

## Project wiki (`docs/*`)

Knowledge for a space lives under that repo’s **`docs/`** only (not a separate vault).

- Required: `docs/index.md`, `docs/log.md`
- ≤280 lines per page; no overlapping topics; frontmatter on wiki pages
- Agents: skill **`docs-wiki`** / `/docs-wiki` (see AGENTS.md marker block)
- Machine policy: [`policy/llm-wiki.toml`](../policy/llm-wiki.toml); pin in `.herdr/config.toml` `[wiki]`
- Doctor / freshness: Go Herdr plugin [herdr-plugins/docs-wiki](https://github.com/tyler-jewell/herdr-plugins/tree/main/docs-wiki) — **not** git hooks  
  - hooks: `pane.agent_status_changed`, `workspace.focused`  
  - CLI: `docs-wiki doctor|fix|nudge`

## Related

- Tool: [`bin/herdr-discover`](../bin/herdr-discover)
- Plugin: [tyler-jewell/herdr-plugins/docs-wiki](https://github.com/tyler-jewell/herdr-plugins/tree/main/docs-wiki)
- Skill: [herdr-plugins/skills/docs-wiki](https://github.com/tyler-jewell/herdr-plugins/tree/main/skills/docs-wiki)
- Templates: [`examples/herdr-config/`](../examples/herdr-config/)
- Upstream agent guide: https://herdr.dev/agent-guide.md
- Upstream automation: https://herdr.dev/docs/agent-automation/
- Upstream session state: https://herdr.dev/docs/session-state/
- Upstream plugins: https://herdr.dev/docs/plugins/
