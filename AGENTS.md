# AGENTS.md — Herdr machine bootstrap

This repository **orchestrates** a greenfield install of Herdr, Node/npx, Grok, the herdr agent skill, and integrations. It is **not** the Herdr source tree.

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
4. Grok CLI via official installer if missing
5. `npx --yes skills add herdrdev/herdr --skill herdr -g -y` (canonical skill only)
6. Agent-native skill symlink workaround (skills#1874 / PR#1883)
7. `herdr integration install` for agents whose config dirs already exist (always Grok if `~/.grok` exists)
8. Verify paths and versions

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

## Safety rules (agents)

- If `HERDR_ENV` is not `1`, do **not** control panes/agents with the herdr skill; teach the human instead (agent guide).
- Do **not** run bare `herdr` for discovery — it attaches the TUI. Use `herdr --help`, group help, `herdr status`.
- Do **not** run `herdr server stop` unless the human explicitly wants to kill the server and all pane processes.
- Do not invent keybindings, config keys, or CLI flags; read https://herdr.dev/docs/ and the upstream skill.
- Prefer user-local installs under `$HOME` (no sudo).

## Lessons learned (greenfield bootstrap)

1. Fresh macOS often has **no Node/npx** — install portable Node before `npx skills`.
2. Official herdr installer puts the binary in `~/.local/bin` but **does not** always patch shell PATH.
3. Informal `npx skill install herdr` fails; use the official `skills add` form above.
4. Global skill install alone is incomplete until #1883 — always link agent-native dirs (especially `~/.grok/skills`).
5. `--agent '*'` pollutes `$HOME`; target explicit dirs only.
6. Eve/PromptScript may fail global skill install; treat as noise if canonical skill exists.
7. `herdr integration install grok` needs `~/.grok` already present (install Grok first).
8. First human attach: run `herdr` from a **normal** terminal, start the agent in a pane, then use the skill inside Herdr.

## Verify

```bash
command -v herdr node npx grok
herdr --version
node -v
test -f ~/.agents/skills/herdr/SKILL.md
test -f ~/.grok/skills/herdr/SKILL.md
herdr integration status
```
