# Project Grok config

| File / dir | Role |
|------------|------|
| **`config.yaml`** | **Source of truth** for global Grok settings. Edit here. |
| `lsp.json` | Project LSP servers (Grok reads this natively). |
| `config.toml` | Optional project-native MCP/plugins/permissions only. |
| `rules/` | Machine-wide rules → synced to `~/.grok/rules/` |
| `hooks/` | Grok hooks (e.g. CAPS → rules-steward) → `~/.grok/hooks/` |
| `agents/` | Named agent defs → `~/.grok/agents/` |
| `personas/` | Subagent personas → `~/.grok/personas/` |

## Override local Grok config (the process)

Your machine’s Grok global settings live in `~/.grok/config.toml`. Grok does **not** load global `[cli]` / `[ui]` / `[features]` from the repo.

1. Edit **`config.yaml`** in this directory; commit.
2. Run from the repo:

   ```bash
   bin/sync-grok-config
   # or: sh install.sh   # includes the same sync
   ```

3. Sync **overwrites** / mirrors:
   - `~/.grok/config.yaml` ← exact copy of this file  
   - `~/.grok/config.toml` ← generated from this file (Grok runtime)
   - `~/.grok/lsp.json` ← copy of project `lsp.json` (convenience)
   - `~/.grok/{rules,hooks,agents,personas}/` ← mirrored from this tree (`install.sh`)

4. Restart Grok (new session) so config/hooks reload.

**CAPS policy:** whole-word `NEVER`/`ALWAYS`/`MUST`/… fires `rules-steward detect` (hook), which opens/reuses a Herdr rules steward pane.

## LSP servers (Rust + Go + Lua)

Configured in **`lsp.json`** (project wins over user):

| Name | Binary | Extensions |
|------|--------|------------|
| `rust` | `rust-analyzer` | `.rs` |
| `go` | `gopls` | `.go`, `.mod`, `.sum`, `.work` |
| `lua` | `lua-language-server` | `.lua` |

- **Passive diagnostics:** `lsp.json` + servers on `PATH` (no flag required).
- **Model `lsp` tool:** also needs `features.lsp_tools: true` via sync → `~/.grok/config.toml`.
- **Agents:** prefer LSP + live tree for Rust/Go/Lua source questions; docs can be wrong or stale.
- **Lua workspace:** repo-root [`.luarc.json`](../.luarc.json) (WezTerm `wezterm` global, Lua 5.4).

```bash
command -v rust-analyzer gopls lua-language-server
test -f .grok/lsp.json
grep lsp_tools ~/.grok/config.toml
```

`install.sh` installs missing `rust-analyzer`, `gopls`, and `lua-language-server` when possible.
