# Machine-wide rules (dotfiles)

Versioned here as `.grok/rules/*.md`. Install/sync copies them to `~/.grok/rules/` so **every Grok agent on this machine** loads them.

**Source of truth is this tree (git).** Home `~/.grok/rules/` is a sync target.

Authoring / migrate:

```bash
rules-steward migrate --dry-run    # home vs bootstrap inventory
rules-steward migrate --spawn      # pull home→VC if needed + open steward
# then commit herdr-bootstrap .grok; re-run install or surface sync → home
```

CAPS `NEVER`/`ALWAYS` → Herdr right pane (policy-caps hook). Follow `agent-rule-quality.md`.
