# Agent rule quality (machine-wide)

Standing bar for any rule shipped into `~/.grok/rules/` (or other agent `rules/` dirs).

## MUST

- Be **universal** for this machine setup — not one repo’s taste.
- Stay **cheap**: compliance check or application path targets **&lt; 3s** (path/`command -v`/short command). Long suites belong in runbooks or plugins.
- Be **AXI-shaped** agent text: short, specific MUST/NEVER, no interactive prompts, no full-doc dumps (link instead). See https://axi.md/
- Live in **one** file topic — refine existing rules instead of duplicating.

## NEVER

- Contradict another active rule without editing/removing the old one first.
- Require multi-minute work as a silent global obligation.
