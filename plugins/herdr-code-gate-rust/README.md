# herdr-code-gate-rust

Herdr plugin: **strict Rust** quality gate when a `Cargo.toml` project is in play.

## Checks (fail on any)

1. **No suppressions** — `#[allow]`, `#![allow]`, `#[expect(...)]` in `.rs`
2. **No weakening config** — e.g. `cap-lints = "allow"` in `.cargo/config*`, clippy.toml `allow =`
3. **`cargo fmt --all -- --check`**
4. **`cargo clippy --all-targets -- -D warnings -D clippy::all -D clippy::pedantic`**
5. **`cargo check --all-targets`** (with `RUSTFLAGS=-Dwarnings`)

## Cheap vs force

- Auto **hook** (agent `done`/`idle`): runs only if `.rs` count/size under limits.
- Manual: `check --force` always runs.

## Usage

```bash
cd plugins/herdr-code-gate-rust
go build -o bin/herdr-code-gate-rust ./cmd/herdr-code-gate-rust
herdr plugin link "$PWD"

herdr-code-gate-rust check --current
herdr-code-gate-rust check --current --fix   # cargo fmt --all then re-check
```

Herdr actions: **Rust code gate (current space)**.
