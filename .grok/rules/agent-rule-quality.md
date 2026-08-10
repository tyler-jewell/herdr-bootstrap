# Agent rule quality (machine-wide)

Standing bar for any rule shipped into the Grok **rules** harness (`~/.grok/rules/` after sync, or other agent `rules/` dirs).

## MUST

- Be **universal** for this machine setup — not one repo’s taste.
- Stay **cheap**: compliance check or application path targets **&lt; 3s** (path/`command -v`/short command). Long suites belong in runbooks or plugins.
- Be **AXI-shaped** agent text: short, specific MUST/NEVER, no interactive prompts, no full-doc dumps (link instead). See https://axi.md/
- Live in **one** file topic — refine existing rules instead of duplicating.
- Version machine-wide rules under **herdr-bootstrap `.grok/rules/`** (dotfiles). Install/sync mirrors them to `~/.grok/rules/`.

## NEVER

- Leave machine-wide rules **only in `~/`** (e.g. edit `~/.grok/rules/` with no versioned twin in herdr-bootstrap `.grok/rules/`). Home is the sync **target**, not the sole source of truth.
- Invent a side store, alternate layout, or non-harness dump for machine rules.
- Contradict another active rule without editing/removing the old one first.
- Require multi-minute work as a silent global obligation.
