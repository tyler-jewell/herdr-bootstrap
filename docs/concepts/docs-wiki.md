---
title: docs-wiki contract
updated: 2026-08-10
tags: [wiki, policy]
summary: Lean per-repo LLM wiki under docs/
---

# docs-wiki contract

Karpathy-style compiled knowledge, simplified for Herdr spaces:

1. Wiki root is always **`docs/`** at the project root.
2. Required: `index.md`, `log.md`.
3. Pages ≤ **280 lines**; no overlapping topics.
4. Frontmatter: `title`, `updated`, `tags` (+ optional `summary`).
5. Agents search via skill **`docs-wiki`**; AGENTS.md routes them here.
6. Freshness is enforced by the **Herdr plugin** (agent done / space focus), not git hooks.

Machine policy: `policy/llm-wiki.toml`. Project pin: `.herdr/config.toml` `[wiki]`.
