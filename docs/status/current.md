---
title: Current status
updated: 2026-08-10
tags: [status]
summary: Live view of herdr-bootstrap purpose and tooling
---

# Current status

**herdr-bootstrap** orchestrates a greenfield Herdr machine setup: Herdr, Node/npx, Grok, skills, integrations — not the Herdr app source.

## Live tools

| Tool | Role |
|------|------|
| `bin/herdr-discover` | Open spaces for `$HOME/**/.herdr/config.toml` |
| `plugins/herdr-docs-wiki` | Go Herdr plugin: doctor, policy fix, agent-done freshness hooks |
| `skills/docs-wiki` | Agent skill: search/update `docs/*` |
| `policy/llm-wiki.toml` | Machine wiki policy (versioned) |

## Wiki home

All project knowledge for this repo: **`docs/*`** only (≤280 lines/page).
