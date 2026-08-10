---
title: Docs wiki doctor
updated: 2026-08-10
tags: [runbook, doctor]
summary: How to run and interpret herdr-docs-wiki doctor
---

# Docs wiki doctor

## From Herdr

- Action: **Docs wiki doctor (this space)** / **(all projects)**
- Or key: `prefix+shift+d` (if installed)

## From a terminal

```bash
# after build + PATH link
herdr-docs-wiki doctor
herdr-docs-wiki doctor --current
herdr-docs-wiki doctor --json --strict
herdr-docs-wiki fix --current --apply-policy
```

## Grades

Rubric totals 100. Treat **F (&lt;60)** or any page over 280 lines (strict) as fail.

`fix --apply-policy` updates the policy pin, AGENTS marker block, and scaffolds missing `docs/index.md` + `log.md` — it does **not** rewrite wiki prose.
