# Herdr machine bootstrap

Idempotent installer for a **working Herdr coding setup** on a fresh macOS or Linux machine: Herdr, Node/npx, Grok CLI, the herdr agent skill, agent-native skill links, and Grok integration hooks.

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
| `--dry-run` | Print actions only |

## After install

1. Open a **new** terminal (or `source ~/.zshrc`).
2. Authenticate Grok if needed: `grok login`.
3. Start Herdr from a normal terminal (not nested inside Herdr):

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
| Node / npm / npx | Portable Node LTS under `~/.local/node`, linked into `~/.local/bin` |
| Grok CLI | Official `https://x.ai/cli/install.sh` if missing |
| herdr skill | `npx skills add herdrdev/herdr --skill herdr -g -y` → `~/.agents/skills/herdr` |
| Agent-native skill links | Relative symlinks (skills CLI bug #1874 / PR #1883) including `~/.grok/skills` |
| Grok integration | `herdr integration install grok` when `~/.grok` exists |
| Shell PATH / completions | Idempotent blocks in `~/.zshrc` |

## Verify

```bash
command -v herdr node npx grok
herdr --version
node -v
test -f ~/.agents/skills/herdr/SKILL.md && echo skill-ok
```

## Grok config (version-controlled) + Rust/Go LSP

**Source of truth:** [`.grok/config.yaml`](./.grok/config.yaml) (edit + commit this file).

| File | Role |
|------|------|
| `.grok/config.yaml` | Team-owned full Grok global settings intent |
| `.grok/lsp.json` | Project LSP: **rust** (`rust-analyzer`) + **go** (`gopls`) |
| `.grok/config.toml` | Project-native MCP/plugins/permissions only |
| `bin/sync-grok-config` | **Overrides** `~/.grok/config.yaml` + regenerates `~/.grok/config.toml` |

```bash
# After editing .grok/config.yaml:
bin/sync-grok-config

# Or full bootstrap (also installs rust-analyzer + gopls when missing):
sh install.sh
```

Agents **must** use the Grok `lsp` tool when coding or searching Rust/Go sources — live code on this machine is authoritative; docs can lag (see [AGENTS.md](./AGENTS.md)).

**Verify LSP:**

```bash
test -f .grok/lsp.json
command -v rust-analyzer gopls
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

## Code gates (one plugin per language)

Strict format/lint/build after agent work (or on demand). **No warnings; no local lint suppressions/overrides.**

| Plugin | Detects | Commands |
|--------|---------|----------|
| [`plugins/herdr-code-gate-rust`](./plugins/herdr-code-gate-rust) | `Cargo.toml` | `fmt --check`, `clippy -D warnings`, `cargo check` |
| [`plugins/herdr-code-gate-go`](./plugins/herdr-code-gate-go) | `go.mod` | `gofmt`, `go vet`, `staticcheck`, `go build` |

Hook: `pane.agent_status_changed` → run when agent is `done`/`idle` and the tree is **cheap** (size limits). CLI: `herdr-code-gate-rust|go check --current [--force]`.

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
| `policy/llm-wiki.toml` | Machine policy version + rubric weights |
| `skills/docs-wiki` | Global agent skill (search/update `docs/`) |
| `plugins/herdr-docs-wiki` | **Go Herdr plugin** — doctor, policy fix, agent-done / focus hooks (no git hooks) |
| `AGENTS.md` markers | Routes agents to the wiki |

```bash
herdr-docs-wiki doctor              # all .herdr projects
herdr-docs-wiki doctor --current
herdr-docs-wiki fix --current --apply-policy
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
