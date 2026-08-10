---
name: docs-wiki
description: >
  Search and update the project LLM wiki under docs/ (lean Karpathy-style pages).
  Use when the user asks what the project knows, to search the wiki, update docs after work,
  check current status, or runs /docs-wiki. Prefer docs/status for "what's going on now".
  Not for generic notes outside docs/, Obsidian vaults, or Herdr layout control.
---

# docs-wiki

Per-repo knowledge lives only under **`docs/`** at the project root (directory containing `.herdr/` or git root).

## Hard rules

- Never write wiki content outside `docs/`.
- **≤280 lines** per `docs/**/*.md` page (split or cut if over).
- **No overlapping topics** — one concept = one page; link with `[[Title]]` or relative links.
- Lean and specific — distill, do not dump source trees or full chat logs.
- Wiki pages (not `docs/README.md`) need frontmatter:

```yaml
---
title: Short title
updated: YYYY-MM-DD
tags: [tag1, tag2]
summary: One-line gist
---
```

Required files: `docs/index.md` (lists every page), `docs/log.md` (append-only activity).

## Search (default)

1. Resolve project root (nearest ancestor with `.herdr/config.toml`, else git root, else cwd).
2. Read `docs/index.md`.
3. Match the query against titles, tags, and summaries; prefer `docs/status/` for live state.
4. Open at most **3** page bodies.
5. Answer with citations as repo-relative paths (e.g. `docs/concepts/foo.md`).

If index is missing, say so and list `docs/**/*.md` shallowly; do not invent pages.

## Update

1. Find the single correct existing page, or create one under the right category folder.
2. Merge new facts; remove duplication.
3. Set `updated` to today; refresh `summary` if needed.
4. Ensure the page appears in `docs/index.md`.
5. Append one line to `docs/log.md`: `YYYY-MM-DD | <title> | <what changed>`.
6. Re-check line count ≤280.

## Categories (optional dirs)

`concepts/`, `decisions/`, `entities/`, `runbooks/`, `status/`

## Out of scope

- Herdr panes/tabs/workspaces (use herdr skill only when asked).
- Full vault tools under `OBSIDIAN_VAULT_PATH` — this house uses **`docs/*` only**.
