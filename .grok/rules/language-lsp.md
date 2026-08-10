# Language work → LSP (machine-wide)

When editing or searching **Rust, Go, or Lua** source on this machine:

## MUST

- Prefer the Grok **`lsp` tool** (`goToDefinition`, `findReferences`, `hover`, symbols) over guessing or stale docs.
- Keep language servers on PATH: `rust-analyzer`, `gopls`, `lua-language-server`.
- Use monorepo plugins **`jewell.rust-lang`**, **`jewell.go-lang`**, **`jewell.lua-lang`** (`status` / `ensure` / `doctor`) to equip tools — not ad-hoc installs in chat.
- Treat **live code on disk** as authoritative; docs can lag.

## NEVER

- Invent format/lint “code-gate” hooks that reimplement house quality policy.
- Silence or skip LSP when servers are available (`features.lsp_tools = true` + project `.grok/lsp.json`).

Quality **policy** (MUST/NEVER wording) is authored via the **rules steward** into `.grok/rules/`. Language plugins only equip LSPs.
