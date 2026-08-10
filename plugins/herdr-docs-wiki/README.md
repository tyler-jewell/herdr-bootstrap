# herdr-docs-wiki

Herdr plugin (Go) for **per-repo `docs/*` LLM wikis**: doctor rubric, policy fix, and event hooks (no git hooks).

## Build

```bash
# Go ≥ 1.22
cd plugins/herdr-docs-wiki
go build -o bin/herdr-docs-wiki ./cmd/herdr-docs-wiki
herdr plugin link "$PWD"
ln -sfn "$PWD/bin/herdr-docs-wiki" ~/.local/bin/herdr-docs-wiki
ln -sfn "$PWD/bin/herdr-docs-wiki" ~/.local/bin/herdr-doctor
```

Or run `sh install.sh` from the bootstrap repo root.

## Commands

```bash
herdr-docs-wiki doctor [--current] [--json] [--strict]
herdr-docs-wiki fix --current --apply-policy
herdr-docs-wiki nudge --current
```

## Herdr hooks

| Event | Behavior |
|-------|----------|
| `startup` | Cache discovered `.herdr` projects |
| `pane.agent_status_changed` | On `done`/`idle`, notify if docs look stale |
| `workspace.focused` | Soft notify on grade F or policy drift |

Actions: doctor (all / current), nudge, fix-policy. Optional key: `prefix+shift+d`.

## Safety

Never stops the Herdr server, never closes panes, never rewrites wiki prose (structure + AGENTS markers only).
