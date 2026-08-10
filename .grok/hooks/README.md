# Grok hooks (versioned)

Team hooks live here and sync to `~/.grok/hooks/` via `install.sh` (`sync_grok_harness_surfaces`).

## Versioned

| File | Role |
|------|------|
| `policy-caps.json` | CAPS detect → rules-steward |

## NEVER version (Herdr-managed, home-only)

| File | Role |
|------|------|
| `herdr.json` | SessionStart → Herdr agent-state |
| `herdr-agent-state.sh` | Installed by `herdr integration install grok` |

Add custom hooks **beside** those files. Do not copy them into this repo.

```bash
rules-steward migrate --dry-run   # ignores herdr.json / herdr-agent-state.sh
```
