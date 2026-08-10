---
title: Herdr spaces
updated: 2026-08-10
tags: [herdr]
summary: One workspace per .herdr repo; layout in config.toml
---

# Herdr spaces

- **Workspace** = one repo/task (official Herdr model).
- Opt-in: `.herdr/config.toml` discovered under `$HOME` by `herdr-discover`.
- Layout (tabs/panes/agents) is versioned in that file; UI keys stay global `~/.config/herdr/config.toml`.
- Match spaces by pane **cwd**, not labels.
- Wiki knowledge is **not** a Herdr layer — it lives in `docs/*` beside the code.
