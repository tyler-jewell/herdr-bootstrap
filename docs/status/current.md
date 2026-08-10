---
title: Current status
updated: 2026-08-10
tags: [status]
summary: Live view of herdr-bootstrap purpose and tooling
---

# Current status

**herdr-bootstrap** orchestrates a greenfield Herdr machine setup: Herdr, **WezTerm** (outer terminal), Node/npx, Grok, skills, integrations — not the Herdr app source.

## Live tools

| Tool | Role |
|------|------|
| `bin/herdr-discover` | Open spaces for `$HOME/**/.herdr/config.toml` |
| `bin/sync-wezterm-config` | Sync `config/wezterm` → `~/.config/wezterm` |
| [herdr-plugins `docs-wiki`](https://github.com/tyler-jewell/herdr-plugins/tree/main/docs-wiki) | Go Herdr plugin: doctor, policy fix, agent-done freshness hooks |
| [herdr-plugins language plugins](https://github.com/tyler-jewell/herdr-plugins) | `go-lang` / `rust-lang` / `lua-lang` LSP equip + rules-steward |
| [herdr-plugins `skills/docs-wiki`](https://github.com/tyler-jewell/herdr-plugins/tree/main/skills/docs-wiki) | Agent skill: search/update `docs/*` |
| `policy/llm-wiki.toml` | Machine wiki policy (versioned) |
| `config/wezterm/` | Herdr-compatible WezTerm config (Kitty keyboard/graphics) |

## Wiki home

All project knowledge for this repo: **`docs/*`** only (≤280 lines/page).
