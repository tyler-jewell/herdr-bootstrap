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
