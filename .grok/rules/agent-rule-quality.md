# Agent rule quality (machine-wide)

Standing bar for harness policy and any rule under the Grok **rules** surface.

## MUST

- Be **universal** for this machine setup — not one repo’s taste.
- Stay **cheap**: compliance check or application path targets **&lt; 3s** (path/`command -v`/short command). Long suites belong in runbooks or plugins.
- Be **AXI-shaped** agent text: short, specific MUST/NEVER, no interactive prompts, no full-doc dumps (link instead). See https://axi.md/
- Live in **one** file topic — refine existing rules instead of duplicating.
- **Migrate harness policy into version control** under **herdr-bootstrap `.grok/`** (dotfiles: `rules/`, `hooks/`, `agents/`, `personas/`). Prefer `rules-steward migrate` / `migrate --dry-run` for home→VC pulls.
- After landing policy: **commit** bootstrap `.grok/`; remind the human to re-run install / harness sync on **other machines**.

## REQUIRED

- **Bootstrap `.grok/` is the source of truth.** Home `~/.grok/` is the **sync target** only (`install.sh` → `sync_grok_harness_surfaces`, or equivalent).
- Language quality policy lives in **`.grok/rules/`** (e.g. `language-lsp.md`). Equip LSPs via monorepo plugins **`jewell.rust-lang`**, **`jewell.go-lang`**, **`jewell.lua-lang`** — not code-gate hooks.

## NEVER

- Leave machine-wide harness policy **only in `~/`** (edit home with no versioned twin under herdr-bootstrap `.grok/`).
- Invent a **side store**, alternate layout, or non-harness dump for machine rules.
- **Version Herdr-managed integration hooks:** `herdr.json`, `herdr-agent-state.sh` (home-only; written by `herdr integration install`; reinstall overwrites).
- Invent format/lint “code-gate” hooks that reimplement house quality policy.
- Contradict another active rule without editing/removing the old one first.
- Require multi-minute work as a silent global obligation.
