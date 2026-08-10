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
