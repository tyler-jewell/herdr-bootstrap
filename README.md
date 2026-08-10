# Herdr machine bootstrap

Idempotent installer for a **working Herdr coding setup** on a fresh macOS or Linux machine: Herdr, **WezTerm** (outer terminal, Herdr-tuned config), Node/npx, Grok CLI, the herdr agent skill, agent-native skill links, and Grok integration hooks.

This is **not** the Herdr application source. Upstream Herdr lives at [herdrdev/herdr](https://github.com/herdrdev/herdr).

## Install (from anywhere)

**Recommended — clone this repo, then run:**

```bash
git clone <this-repo-url>
cd herdr-bootstrap
sh install.sh
```

**One-liner** (replace the raw URL with *this* repo’s `install.sh` on GitHub → Raw):

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/main/install.sh | sh
```

**Safer (review first):**

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/main/install.sh -o /tmp/herdr-bootstrap.sh
less /tmp/herdr-bootstrap.sh
sh /tmp/herdr-bootstrap.sh
```

Use the GitHub UI “Raw” link for `install.sh` so you never hardcode an account name in docs you copy elsewhere.

### Flags

| Flag | Effect |
|------|--------|
| `--skip-node` | Do not install/upgrade Node |
| `--skip-grok` | Do not install/update Grok |
| `--skip-skills` | Skip `npx skills add` and symlink workaround |
| `--skip-integrations` | Skip `herdr integration install …` |
| `--skip-wezterm` | Skip WezTerm binary install and config sync |
| `--skip-wezterm-config-sync` | Install WezTerm if needed but do not overwrite `~/.config/wezterm` |
| `--dry-run` | Print actions only |

## After install

1. Open **WezTerm** (preferred outer terminal) or a new shell (`source ~/.zshrc`).
2. Authenticate Grok if needed: `grok login`.
3. Start Herdr from WezTerm — a **normal** terminal, not nested inside Herdr:

   ```bash
   cd ~/your-project
   herdr
   ```

4. Start your agent in a pane (for example `grok`).

**Human first-run walkthrough:** [herdr.dev/agent-guide.md](https://herdr.dev/agent-guide.md)

If the install already succeeded, that guide is the next step for mouse/keyboard, detach/reattach, and agent detection — you do not need to reinstall.

## What gets installed

| Component | Location / method |
|-----------|-------------------|
| Herdr | Official `https://herdr.dev/install.sh` → `~/.local/bin/herdr` (updates via `herdr update`) |
| **WezTerm** | Existing binary, else Homebrew, else portable (macOS app / Linux AppImage or deb-extract) — no sudo |
| WezTerm config | `config/wezterm/wezterm.lua` → `~/.config/wezterm/` (Kitty keyboard + graphics for Herdr) |
| Node / npm / npx | Portable Node LTS under `~/.local/node`, linked into `~/.local/bin` |
| Grok CLI | Official `https://x.ai/cli/install.sh` if missing |
| herdr skill | `npx skills add herdrdev/herdr --skill herdr -g -y` → `~/.agents/skills/herdr` |
| Agent-native skill links | Relative symlinks (skills CLI bug #1874 / PR #1883) including `~/.grok/skills` |
| Grok integration | `herdr integration install grok` when `~/.grok` exists |
| Shell PATH / completions | Idempotent blocks in `~/.zshrc` |

## Verify

```bash
command -v herdr node npx grok wezterm
herdr --version
node -v
wezterm --version
test -f ~/.agents/skills/herdr/SKILL.md && echo skill-ok
test -f ~/.config/wezterm/wezterm.lua && grep -q enable_kitty_keyboard ~/.config/wezterm/wezterm.lua && echo wezterm-config-ok
```

## Grok config (version-controlled) + Rust/Go LSP

**Source of truth:** [`.grok/config.yaml`](./.grok/config.yaml) (edit + commit this file).

| File | Role |
|------|------|
| `.grok/config.yaml` | Team-owned full Grok global settings intent |
| `.grok/lsp.json` | Project LSP: **rust** + **go** + **lua** (`rust-analyzer`, `gopls`, `lua-language-server`) |
| `.grok/config.toml` | Project-native MCP/plugins/permissions only |
| `bin/sync-grok-config` | **Overrides** `~/.grok/config.yaml` + regenerates `~/.grok/config.toml` |

```bash
# After editing .grok/config.yaml:
bin/sync-grok-config

# Or full bootstrap (also installs rust-analyzer + gopls + lua-language-server when missing):
sh install.sh
```

Agents **must** use the Grok `lsp` tool when coding or searching Rust/Go/Lua sources — live code on this machine is authoritative; docs can lag (see [AGENTS.md](./AGENTS.md)).

**Verify LSP:**

```bash
test -f .grok/lsp.json
command -v rust-analyzer gopls lua-language-server
grep lsp_tools ~/.grok/config.toml   # true after sync
# Restart Grok; passive diagnostics need lsp.json + servers;
# model lsp tool also needs lsp_tools=true
```

Details: [`.grok/README.md`](./.grok/README.md).

## Herdr global config (version-controlled, all agents)

**Source of truth:** [`config/herdr/config.toml`](./config/herdr/config.toml).

Synced to `~/.config/herdr/config.toml` so **every agent and Herdr session** on the machine gets the same UI, experimental flags (e.g. `kitty_graphics` for map previews), and plugin keybindings.

| File | Role |
|------|------|
| `config/herdr/config.toml` | Team Herdr global settings |
| `bin/sync-herdr-config` | Installs to `~/.config/herdr/config.toml` + `herdr server reload-config` |

```bash
bin/sync-herdr-config
# or full bootstrap:
sh install.sh
```

Includes: agent labels on pane borders, quiet toasts, **Kitty graphics**, maps open/preview keys (`prefix+shift+m` / `prefix+shift+p`), docs-wiki doctor key. See [docs/HERDR_RULES.md](./docs/HERDR_RULES.md).

## WezTerm (outer terminal, version-controlled)

**Source of truth:** [`config/wezterm/wezterm.lua`](./config/wezterm/wezterm.lua).

Synced to `~/.config/wezterm/wezterm.lua` so Herdr and coding agents get:

| Setting | Why |
|---------|-----|
| `enable_kitty_keyboard = true` | Agents request Kitty keyboard protocol (e.g. Shift+Enter) |
| `enable_kitty_graphics = true` | Matches Herdr `experimental.kitty_graphics` for image/map panes |
| Left Option = Alt (macOS) | Safe chords reach Herdr; right Option still composes |
| No steal of `ctrl+b` / `ctrl+alt+*` | Herdr prefix + recommended direct chords stay free |

Optional local overrides: `~/.config/wezterm/user.lua` (never overwritten by sync).

```bash
bin/sync-wezterm-config
# or full bootstrap:
sh install.sh
```

Details: [`config/wezterm/README.md`](./config/wezterm/README.md).  
Keyboard context: [herdr.dev/docs/keyboard](https://herdr.dev/docs/keyboard/).

## Language plugins + rules steward

Plugin **source of truth:** public monorepo [tyler-jewell/herdr-plugins](https://github.com/tyler-jewell/herdr-plugins) (clone next to this repo as `../herdr-plugins`).

| Plugin (monorepo) | Detects | Commands |
|-------------------|---------|----------|
| [`rust-lang`](https://github.com/tyler-jewell/herdr-plugins/tree/main/rust-lang) | `Cargo.toml` | Ensure **rust-analyzer** + doctor |
| [`go-lang`](https://github.com/tyler-jewell/herdr-plugins/tree/main/go-lang) | `go.mod` | Ensure **gopls** + doctor |
| [`lua-lang`](https://github.com/tyler-jewell/herdr-plugins/tree/main/lua-lang) | `*.lua` | Ensure **lua-language-server** + doctor |
| [`rules-steward`](https://github.com/tyler-jewell/herdr-plugins/tree/main/rules-steward) | CAPS policy | Spawn Herdr **rules** agent |

Language plugins equip LSPs only. Quality policy lives in [`.grok/rules/`](./.grok/rules/) via the rules steward (not format-gate hooks).

`install.sh` **clones/pulls** [tyler-jewell/herdr-plugins](https://github.com/tyler-jewell/herdr-plugins), then builds and `herdr plugin link`s **every** plugin subdir. Ids: `jewell.*`, short binary names. Override with `HERDR_PLUGINS_ROOT` / `HERDR_PLUGINS_GIT_URL` / `HERDR_PLUGINS_REF`.

## Multi-project spaces (`herdr-discover`)

Herdr has **no** native per-project config. This bootstrap defines a convention:

1. Put **`<repo>/.herdr/config.toml`** in any project under `$HOME` (version-controlled with that repo).
2. Run **`herdr-discover reconcile`** while a Herdr server is up — it opens one workspace per discovered project and applies full-stack layout only on **fresh** spaces.

```bash
# from this repo
./bin/herdr-discover scan
./bin/herdr-discover reconcile --dry-run
./bin/herdr-discover reconcile

# scaffold opt-in in another project
cd ~/your-project
/path/to/herdr-bootstrap/bin/herdr-discover init --template standard
```

Optional: `ln -sfn "$PWD/bin/herdr-discover" ~/.local/bin/herdr-discover`

Rules, safety, and schema: **[docs/HERDR_RULES.md](./docs/HERDR_RULES.md)**.  
Templates: [examples/herdr-config/](./examples/herdr-config/).

## Project wiki (`docs/*`) + doctor plugin

Each Herdr space’s **live knowledge** is a lean LLM wiki under that repo’s **`docs/`** (≤280 lines/page, no overlapping topics). Agents use skill **`docs-wiki`** / `/docs-wiki`.

| Piece | Role |
|-------|------|
| `policy/llm-wiki.toml` | Machine policy version + rubric weights (pinned to `~/.config/herdr-bootstrap/` on install) |
| [herdr-plugins `skills/docs-wiki`](https://github.com/tyler-jewell/herdr-plugins/tree/main/skills/docs-wiki) | Global agent skill (search/update `docs/`) — installed from monorepo |
| [herdr-plugins `docs-wiki`](https://github.com/tyler-jewell/herdr-plugins/tree/main/docs-wiki) | **Go Herdr plugin** — doctor, policy fix, agent-done / focus hooks (no git hooks) |
| `AGENTS.md` markers | Routes agents to the wiki |

```bash
docs-wiki doctor              # all .herdr projects
docs-wiki doctor --current
docs-wiki fix --current --apply-policy
# In Herdr: plugin actions or prefix+shift+d (after install)
```

Wiki index for this repo: [docs/index.md](./docs/index.md).

## Docs for development

- Docs: https://herdr.dev/docs/
- Plugins: https://herdr.dev/plugins/
- Blog: https://herdr.dev/blog/
- Source: https://github.com/herdrdev/herdr

Agent-facing contract and lessons from greenfield bootstrap: [AGENTS.md](./AGENTS.md).

## Caveats

- `curl | sh` runs remote code. Prefer the review path or pin a release tag when available.
- Binary install does **not** log you into Grok; run `grok login` separately.
- The installer never attaches the Herdr TUI and never runs `herdr server stop`.
- Until [vercel-labs/skills#1883](https://github.com/vercel-labs/skills/pull/1883) merges, the skill symlink workaround remains required for many agents (including Grok).

## License

MIT — see [LICENSE](./LICENSE).
