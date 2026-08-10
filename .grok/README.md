# Project Grok config

| File | Role |
|------|------|
| **`config.yaml`** | **Source of truth** (version-controlled). Edit here. |
| `lsp.json` | Project LSP servers (Grok reads this natively). |
| `config.toml` | Optional project-native MCP/plugins/permissions only. |

## Override local Grok config (the process)

Your machine’s Grok global settings live in `~/.grok/config.toml`. Grok does **not** load global `[cli]` / `[ui]` / `[features]` from the repo.

1. Edit **`config.yaml`** in this directory; commit.
2. Run from the repo:

   ```bash
   bin/sync-grok-config
   # or: sh install.sh   # includes the same sync
   ```

3. Sync **overwrites**:
   - `~/.grok/config.yaml` ← exact copy of this file  
   - `~/.grok/config.toml` ← generated from this file (Grok runtime)
   - `~/.grok/lsp.json` ← copy of project `lsp.json` (convenience)

4. Restart Grok (new session) so config reloads.

## LSP servers (Rust + Go)

Configured in **`lsp.json`** (project wins over user):

| Name | Binary | Extensions |
|------|--------|------------|
| `rust` | `rust-analyzer` | `.rs` |
| `go` | `gopls` | `.go`, `.mod`, `.sum`, `.work` |

- **Passive diagnostics:** `lsp.json` + servers on `PATH` (no flag required).
- **Model `lsp` tool:** also needs `features.lsp_tools: true` via sync → `~/.grok/config.toml`.
- **Agents:** prefer LSP + live tree for Rust/Go source questions; docs can be wrong or stale.

```bash
command -v rust-analyzer gopls
test -f .grok/lsp.json
grep lsp_tools ~/.grok/config.toml
```

`install.sh` installs missing `rust-analyzer` and `gopls` when possible.
