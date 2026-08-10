#!/usr/bin/env sh
# Herdr machine bootstrap — idempotent install/update of herdr, Node/npx, Grok,
# agent skills (herdr, llm-wiki pattern, docs-wiki), agent-native skill symlinks
# (#1874 / PR #1883), Grok integration hooks, global Herdr config sync, and plugins.
#
# Usage:
#   sh install.sh [--skip-node] [--skip-grok] [--skip-skills] [--skip-integrations] [--skip-plugin] [--skip-herdr-config-sync] [--dry-run]
#   # or: curl -fsSL <raw-url-of-this-repo>/install.sh | sh
#
# Safety:
#   - never runs bare `herdr` (TUI attach)
#   - never runs `herdr server stop`
#   - no sudo
#   - non-interactive (skills: -y / npx --yes)
#   - never uses --agent '*' (avoids polluting $HOME with empty agent trees)

set -eu

SKIP_NODE=0
SKIP_GROK=0
SKIP_SKILLS=0
SKIP_INTEGRATIONS=0
SKIP_PLUGIN=0
SKIP_RUST_ANALYZER=0
SKIP_GOPLS=0
SKIP_GROK_CONFIG_SYNC=0
SKIP_HERDR_CONFIG_SYNC=0
DRY_RUN=0

NODE_VERSION="${NODE_VERSION:-22.18.0}"
HERDR_INSTALL_DIR="${HERDR_INSTALL_DIR:-$HOME/.local/bin}"
NODE_PREFIX="${NODE_PREFIX:-$HOME/.local/node}"
LOCAL_BIN="${LOCAL_BIN:-$HOME/.local/bin}"
SHARE_HERDR="${SHARE_HERDR:-$HOME/.local/share/herdr}"
APPLY_SKILLS_SYMLINK_WORKAROUND="${APPLY_SKILLS_SYMLINK_WORKAROUND:-1}"

# Resolve repo root when install.sh is run from a clone (not curl|sh).
BOOTSTRAP_ROOT=""
case "$0" in
  */*) BOOTSTRAP_ROOT="$(CDPATH= cd -- "$(dirname "$0")" && pwd)" ;;
esac

# shellcheck disable=SC2034
for arg in "$@"; do
  case "$arg" in
    --skip-node) SKIP_NODE=1 ;;
    --skip-grok) SKIP_GROK=1 ;;
    --skip-skills) SKIP_SKILLS=1 ;;
    --skip-integrations) SKIP_INTEGRATIONS=1 ;;
    --skip-plugin) SKIP_PLUGIN=1 ;;
    --skip-rust-analyzer) SKIP_RUST_ANALYZER=1 ;;
    --skip-gopls) SKIP_GOPLS=1 ;;
    --skip-grok-config-sync) SKIP_GROK_CONFIG_SYNC=1 ;;
    --skip-herdr-config-sync) SKIP_HERDR_CONFIG_SYNC=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "unknown flag: $arg" >&2
      exit 2
      ;;
  esac
done

log()  { printf '==> %s\n' "$*"; }
warn() { printf '!!  %s\n' "$*" >&2; }
die()  { printf 'XX  %s\n' "$*" >&2; exit 1; }

run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '[dry-run] %s\n' "$*"
    return 0
  fi
  "$@"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

append_once() {
  # append_once <file> <marker> <block>
  file="$1"
  marker="$2"
  block="$3"
  if [ "$DRY_RUN" = 1 ]; then
    printf '[dry-run] ensure marker %s in %s\n' "$marker" "$file"
    return 0
  fi
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if grep -F "$marker" "$file" >/dev/null 2>&1; then
    return 0
  fi
  printf '\n%s\n%s\n' "$marker" "$block" >>"$file"
}

# --- platform ---

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$OS" in
  darwin|linux) ;;
  *) die "unsupported OS: $OS (this bootstrap supports macOS and Linux)" ;;
esac

case "$ARCH" in
  arm64|aarch64)
    NODE_ARCH="arm64"
    HERDR_ARCH="aarch64"
    GROK_ARCH="aarch64"
    ;;
  x86_64|amd64)
    NODE_ARCH="x64"
    HERDR_ARCH="x86_64"
    GROK_ARCH="x86_64"
    ;;
  *)
    die "unsupported arch: $ARCH"
    ;;
esac

if [ "$OS" = "darwin" ]; then
  NODE_PLATFORM="darwin"
else
  NODE_PLATFORM="linux"
fi

export PATH="$LOCAL_BIN:$HOME/.grok/bin:$PATH"

log "Herdr bootstrap starting (os=$OS arch=$ARCH)"
if [ "${HERDR_ENV:-}" = "1" ]; then
  warn "HERDR_ENV=1: running inside a Herdr pane — will install tools but never attach TUI or stop the server"
fi

need_cmd curl
need_cmd tar
need_cmd uname

mkdir -p "$LOCAL_BIN" "$SHARE_HERDR"

# --- PATH scaffolding ---

path_block='export PATH="$HOME/.local/bin:$PATH"'
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  if [ -f "$rc" ] || [ "$rc" = "$HOME/.zshrc" ]; then
    append_once "$rc" "# >>> herdr-bootstrap local-bin >>>" \
"$path_block
# <<< herdr-bootstrap local-bin <<<"
  fi
done

# --- Node ---

install_node() {
  if [ "$SKIP_NODE" = 1 ]; then
    log "skip node (--skip-node)"
    return 0
  fi

  if command -v node >/dev/null 2>&1 && command -v npx >/dev/null 2>&1; then
    major="$(node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo 0)"
    if [ "$major" -ge 20 ] 2>/dev/null; then
      log "node already present: $(node -v) ($(command -v node))"
      return 0
    fi
    warn "node $(node -v) is older than 20; upgrading portable Node $NODE_VERSION"
  else
    log "installing portable Node $NODE_VERSION → $NODE_PREFIX"
  fi

  tarball="node-v${NODE_VERSION}-${NODE_PLATFORM}-${NODE_ARCH}.tar.gz"
  url="https://nodejs.org/dist/v${NODE_VERSION}/${tarball}"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/herdr-node.XXXXXX")"

  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] would download $url"
    rm -rf "$tmp"
    return 0
  fi

  curl -fsSL "$url" -o "$tmp/$tarball"
  tar -xzf "$tmp/$tarball" -C "$tmp"
  extracted="$tmp/node-v${NODE_VERSION}-${NODE_PLATFORM}-${NODE_ARCH}"
  if [ ! -d "$extracted" ]; then
    rm -rf "$tmp"
    die "node tarball layout unexpected"
  fi

  rm -rf "$NODE_PREFIX"
  mkdir -p "$(dirname "$NODE_PREFIX")"
  mv "$extracted" "$NODE_PREFIX"
  rm -rf "$tmp"

  ln -sfn "$NODE_PREFIX/bin/node" "$LOCAL_BIN/node"
  ln -sfn "$NODE_PREFIX/bin/npm"  "$LOCAL_BIN/npm"
  ln -sfn "$NODE_PREFIX/bin/npx"  "$LOCAL_BIN/npx"

  log "node installed: $($LOCAL_BIN/node -v)"
}

# --- Herdr ---

install_herdr() {
  if command -v herdr >/dev/null 2>&1; then
    log "herdr present: $(herdr --version 2>/dev/null || true) — updating"
    if [ "$DRY_RUN" = 1 ]; then
      log "[dry-run] would run: herdr update"
    else
      # never --handoff; never server stop
      herdr update || warn "herdr update failed; leaving existing binary"
    fi
  else
    log "installing herdr via official installer → $HERDR_INSTALL_DIR"
    if [ "$DRY_RUN" = 1 ]; then
      log "[dry-run] would run: curl -fsSL https://herdr.dev/install.sh | sh"
    else
      HERDR_INSTALL_DIR="$HERDR_INSTALL_DIR" curl -fsSL https://herdr.dev/install.sh | sh
    fi
  fi

  command -v herdr >/dev/null 2>&1 || [ -x "$HERDR_INSTALL_DIR/herdr" ] \
    || die "herdr binary not found after install"
  export PATH="$HERDR_INSTALL_DIR:$PATH"

  # completions
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] would write herdr zsh completion"
  else
    if herdr completion zsh >"$SHARE_HERDR/herdr.zsh" 2>/dev/null; then
      append_once "$HOME/.zshrc" "# >>> herdr-bootstrap completion >>>" \
'[[ -f ~/.local/share/herdr/herdr.zsh ]] && source ~/.local/share/herdr/herdr.zsh
# <<< herdr-bootstrap completion <<<'
    fi
  fi
}

# --- Grok ---

install_grok() {
  if [ "$SKIP_GROK" = 1 ]; then
    log "skip grok (--skip-grok)"
    return 0
  fi

  if command -v grok >/dev/null 2>&1; then
    log "grok present: $(grok --version 2>/dev/null || true)"
    if command -v grok >/dev/null 2>&1 && grok update --help >/dev/null 2>&1; then
      if [ "$DRY_RUN" = 1 ]; then
        log "[dry-run] would run: grok update"
      else
        grok update 2>/dev/null || warn "grok update not available or failed; leaving existing binary"
      fi
    fi
    return 0
  fi

  log "installing Grok CLI via official installer"
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] would run: curl -fsSL https://x.ai/cli/install.sh | bash"
    return 0
  fi
  curl -fsSL https://x.ai/cli/install.sh | bash
  export PATH="$HOME/.grok/bin:$PATH"
}

# --- Skill ---

install_skill() {
  if [ "$SKIP_SKILLS" = 1 ]; then
    log "skip skills (--skip-skills)"
    return 0
  fi

  if ! command -v npx >/dev/null 2>&1; then
    warn "npx missing; cannot install herdr skill (install Node first)"
    return 0
  fi

  log "installing herdr skill (canonical ~/.agents/skills/herdr)"
  # Correct command — never: npx skill install herdr
  # Never: --agent '*' (home pollution)
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] would run: npx --yes skills add herdrdev/herdr --skill herdr -g -y"
  else
    # skills CLI may exit non-zero for unsupported agents even on partial success
    npx --yes skills add herdrdev/herdr --skill herdr -g -y || \
      warn "skills add returned non-zero (often Eve/PromptScript); checking canonical path"
  fi

  if [ ! -f "$HOME/.agents/skills/herdr/SKILL.md" ]; then
    warn "canonical skill missing; falling back to raw SKILL.md"
    if [ "$DRY_RUN" = 0 ]; then
      mkdir -p "$HOME/.agents/skills/herdr"
      curl -fsSL \
        https://raw.githubusercontent.com/herdrdev/herdr/master/skills/herdr/SKILL.md \
        -o "$HOME/.agents/skills/herdr/SKILL.md" || warn "fallback skill download failed"
    fi
  fi

  # Karpathy pattern skill (literacy); house docs-wiki is operational truth for docs/*
  log "installing llm-wiki pattern skill (ar9av/obsidian-wiki --skill llm-wiki -g)"
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] would run: npx --yes skills add ar9av/obsidian-wiki --skill llm-wiki -g -y"
  else
    npx --yes skills add ar9av/obsidian-wiki --skill llm-wiki -g -y || \
      warn "llm-wiki skills add failed (non-fatal)"
  fi

  install_docs_wiki_skill
}

install_docs_wiki_skill() {
  # House skill: search/update per-repo docs/* (from this bootstrap tree when present)
  src=""
  if [ -n "$BOOTSTRAP_ROOT" ] && [ -f "$BOOTSTRAP_ROOT/skills/docs-wiki/SKILL.md" ]; then
    src="$BOOTSTRAP_ROOT/skills/docs-wiki"
  fi
  dest="$HOME/.agents/skills/docs-wiki"
  if [ -z "$src" ]; then
    warn "docs-wiki skill source not found (run install from herdr-bootstrap clone)"
    return 0
  fi
  log "installing house docs-wiki skill → $dest"
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] would copy $src → $dest"
    return 0
  fi
  mkdir -p "$dest"
  # copy tree (portable)
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$src/" "$dest/"
  else
    rm -rf "$dest"
    mkdir -p "$dest"
    cp -R "$src/." "$dest/"
  fi
}

# --- #1874 / PR #1883 workaround ---

# link_one_skill_native <skill-name>  e.g. herdr | docs-wiki | llm-wiki
link_one_skill_native() {
  skill_name="$1"
  CANONICAL="$HOME/.agents/skills/$skill_name"
  if [ ! -f "$CANONICAL/SKILL.md" ]; then
    warn "no canonical skill at $CANONICAL; skip native links for $skill_name"
    return 0
  fi

  log "linking agent-native skill dirs → $CANONICAL ($skill_name)"

  set -- \
    "$HOME/.codex/skills" \
    "$HOME/.cursor/skills" \
    "$HOME/.claude/skills" \
    "$HOME/.gemini/skills" \
    "$HOME/.gemini/antigravity/skills" \
    "$HOME/.gemini/antigravity-cli/skills" \
    "$HOME/.config/opencode/skills" \
    "$HOME/.config/amp/agents/skills" \
    "$HOME/.codeium/windsurf/skills" \
    "$HOME/.grok/skills"

  note="$SHARE_HERDR/skills-pr-1883-workaround.txt"
  if [ "$DRY_RUN" = 0 ]; then
    {
      echo "Workaround applied: $(date -u +%Y-%m-%dT%H:%M:%SZ) skill=$skill_name"
      echo "Bug: https://github.com/vercel-labs/skills/issues/1874"
      echo "Fix PR: https://github.com/vercel-labs/skills/pull/1883"
      echo "Canonical: $CANONICAL"
    } >>"$note"
  fi

  for dir in "$@"; do
    if [ "$DRY_RUN" = 1 ]; then
      log "[dry-run] would link $dir/$skill_name"
      continue
    fi
    mkdir -p "$dir"
    if command -v python3 >/dev/null 2>&1; then
      rel="$(python3 -c "import os; print(os.path.relpath('$CANONICAL', '$dir'))")"
    else
      rel="$CANONICAL"
    fi
    target="$dir/$skill_name"
    if [ -d "$target" ] && [ ! -L "$target" ]; then
      if [ -f "$target/SKILL.md" ] && [ -f "$CANONICAL/SKILL.md" ] && \
        cmp -s "$target/SKILL.md" "$CANONICAL/SKILL.md" 2>/dev/null; then
        rm -rf "$target"
      else
        warn "keeping non-matching real dir: $target"
        continue
      fi
    fi
    ln -sfn "$rel" "$target"
    echo "linked: $target -> $rel" >>"$note"
  done
}

link_skill_native_dirs() {
  if [ "$APPLY_SKILLS_SYMLINK_WORKAROUND" != 1 ]; then
    log "skip skills symlink workaround (APPLY_SKILLS_SYMLINK_WORKAROUND=0)"
    return 0
  fi
  # Do not use --agent '*'; only explicit dirs inside link_one_skill_native.
  link_one_skill_native herdr
  link_one_skill_native docs-wiki
  # llm-wiki name depends on package layout; try common names
  if [ -d "$HOME/.agents/skills/llm-wiki" ]; then
    link_one_skill_native llm-wiki
  fi
}

# --- Go plugin herdr-docs-wiki ---

install_docs_wiki_plugin() {
  if [ "$SKIP_PLUGIN" = 1 ]; then
    log "skip docs-wiki plugin (--skip-plugin)"
    return 0
  fi
  if [ -z "$BOOTSTRAP_ROOT" ] || [ ! -d "$BOOTSTRAP_ROOT/plugins/herdr-docs-wiki" ]; then
    warn "plugin sources missing (run install from herdr-bootstrap clone)"
    return 0
  fi
  if ! command -v go >/dev/null 2>&1; then
    warn "go not on PATH; skip herdr-docs-wiki plugin build (install Go ≥1.22)"
    return 0
  fi
  if ! command -v herdr >/dev/null 2>&1; then
    warn "herdr not on PATH; skip plugin link"
    return 0
  fi

  plug="$BOOTSTRAP_ROOT/plugins/herdr-docs-wiki"
  log "building herdr-docs-wiki plugin"
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] would go build + herdr plugin link $plug"
    return 0
  fi
  mkdir -p "$plug/bin"
  (cd "$plug" && go build -o bin/herdr-docs-wiki ./cmd/herdr-docs-wiki) || {
    warn "go build failed"
    return 0
  }
  ln -sfn "$plug/bin/herdr-docs-wiki" "$LOCAL_BIN/herdr-docs-wiki"
  ln -sfn "$plug/bin/herdr-docs-wiki" "$LOCAL_BIN/herdr-doctor"
  # link plugin into Herdr (idempotent)
  herdr plugin link "$plug" 2>/dev/null || \
    herdr plugin link "$plug" --yes 2>/dev/null || \
    warn "herdr plugin link failed (is server compatible? try: herdr plugin link $plug)"

  # Keybindings for docs-wiki (and maps, kitty, …) live in versioned
  # config/herdr/config.toml and are applied by sync_herdr_config.
  install_code_gate_plugins
  try_link_maps_plugin
}

# Link jewell.maps from sibling herdr-plugins monorepo when present.
try_link_maps_plugin() {
  if [ "$SKIP_PLUGIN" = 1 ]; then
    return 0
  fi
  if ! command -v herdr >/dev/null 2>&1; then
    return 0
  fi
  maps=""
  if [ -n "$BOOTSTRAP_ROOT" ] && [ -f "$BOOTSTRAP_ROOT/../herdr-plugins/maps/herdr-plugin.toml" ]; then
    maps="$(CDPATH= cd -- "$BOOTSTRAP_ROOT/../herdr-plugins/maps" && pwd)"
  elif [ -f "$HOME/herdr-plugins/maps/herdr-plugin.toml" ]; then
    maps="$HOME/herdr-plugins/maps"
  fi
  if [ -z "$maps" ]; then
    return 0
  fi
  log "linking maps plugin from $maps"
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] would: herdr plugin link $maps"
    return 0
  fi
  if [ -x "$maps/target/release/map-axi" ] || command -v cargo >/dev/null 2>&1; then
    if [ ! -x "$maps/target/release/map-axi" ] && command -v cargo >/dev/null 2>&1; then
      (cd "$maps" && cargo build --release) || warn "maps cargo build failed"
    fi
  fi
  herdr plugin link "$maps" 2>/dev/null || \
    herdr plugin link "$maps" --yes 2>/dev/null || \
    warn "herdr plugin link maps failed"
}

# --- Per-language code gates (Rust / Go) ---

install_code_gate_plugins() {
  if [ "$SKIP_PLUGIN" = 1 ]; then
    return 0
  fi
  if [ -z "$BOOTSTRAP_ROOT" ]; then
    return 0
  fi
  if ! command -v go >/dev/null 2>&1 || ! command -v herdr >/dev/null 2>&1; then
    warn "go/herdr missing; skip code-gate plugins"
    return 0
  fi

  # staticcheck for Go gate
  if ! command -v staticcheck >/dev/null 2>&1; then
    log "installing staticcheck (Go code gate)"
    if [ "$DRY_RUN" = 0 ]; then
      mkdir -p "$LOCAL_BIN"
      GOBIN="$LOCAL_BIN" go install honnef.co/go/tools/cmd/staticcheck@latest || \
        warn "staticcheck install failed"
    fi
  fi

  for name in herdr-code-gate-rust herdr-code-gate-go; do
    plug="$BOOTSTRAP_ROOT/plugins/$name"
    if [ ! -d "$plug" ]; then
      warn "missing $plug"
      continue
    fi
    log "building $name"
    if [ "$DRY_RUN" = 1 ]; then
      log "[dry-run] would build/link $name"
      continue
    fi
    mkdir -p "$plug/bin"
    (cd "$plug" && go build -o "bin/$name" "./cmd/$name") || {
      warn "go build $name failed"
      continue
    }
    ln -sfn "$plug/bin/$name" "$LOCAL_BIN/$name"
    herdr plugin link "$plug" 2>/dev/null || \
      herdr plugin link "$plug" --yes 2>/dev/null || \
      warn "herdr plugin link $name failed"
  done
}

# --- rust-analyzer (Grok Rust LSP) ---

install_rust_analyzer() {
  if [ "$SKIP_RUST_ANALYZER" = 1 ]; then
    log "skip rust-analyzer (--skip-rust-analyzer)"
    return 0
  fi
  if command -v rust-analyzer >/dev/null 2>&1; then
    log "rust-analyzer present: $(command -v rust-analyzer)"
    return 0
  fi
  log "installing rust-analyzer"
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] would install rust-analyzer"
    return 0
  fi
  if command -v rustup >/dev/null 2>&1; then
    rustup component add rust-analyzer || warn "rustup component add rust-analyzer failed"
    if command -v rust-analyzer >/dev/null 2>&1; then
      return 0
    fi
  fi
  if command -v brew >/dev/null 2>&1; then
    brew install rust-analyzer || warn "brew install rust-analyzer failed"
    if command -v rust-analyzer >/dev/null 2>&1; then
      return 0
    fi
  fi
  # Portable binary into ~/.local/bin
  arch="$(uname -m)"
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "$os-$arch" in
    darwin-arm64|darwin-aarch64) asset="rust-analyzer-aarch64-apple-darwin.gz" ;;
    darwin-x86_64) asset="rust-analyzer-x86_64-apple-darwin.gz" ;;
    linux-x86_64|linux-amd64) asset="rust-analyzer-x86_64-unknown-linux-gnu.gz" ;;
    linux-arm64|linux-aarch64) asset="rust-analyzer-aarch64-unknown-linux-gnu.gz" ;;
    *)
      warn "no portable rust-analyzer asset for $os-$arch; install manually"
      return 0
      ;;
  esac
  url="https://github.com/rust-lang/rust-analyzer/releases/latest/download/$asset"
  tmp="$(mktemp)"
  if curl -fsSL "$url" -o "$tmp"; then
    mkdir -p "$LOCAL_BIN"
    gunzip -c "$tmp" >"$LOCAL_BIN/rust-analyzer" || {
      # some releases may already be uncompressed naming
      warn "gunzip failed; trying raw copy"
      cp "$tmp" "$LOCAL_BIN/rust-analyzer" 2>/dev/null || true
    }
    chmod +x "$LOCAL_BIN/rust-analyzer"
    rm -f "$tmp"
    log "installed $LOCAL_BIN/rust-analyzer"
  else
    warn "download rust-analyzer failed: $url"
    rm -f "$tmp"
  fi
  command -v rust-analyzer >/dev/null 2>&1 || warn "rust-analyzer still not on PATH"
}

# --- gopls (Grok Go LSP) ---

install_gopls() {
  if [ "$SKIP_GOPLS" = 1 ]; then
    log "skip gopls (--skip-gopls)"
    return 0
  fi
  if command -v gopls >/dev/null 2>&1; then
    log "gopls present: $(command -v gopls)"
    return 0
  fi
  log "installing gopls"
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] would install gopls"
    return 0
  fi
  if ! command -v go >/dev/null 2>&1; then
    warn "go not on PATH; cannot install gopls (install Go first)"
    return 0
  fi
  mkdir -p "$LOCAL_BIN"
  # Install into user-local bin so PATH picks it up without GOPATH/bin puzzles
  if GOBIN="$LOCAL_BIN" go install golang.org/x/tools/gopls@latest; then
    log "installed $LOCAL_BIN/gopls"
  else
    warn "go install gopls failed"
  fi
  command -v gopls >/dev/null 2>&1 || warn "gopls still not on PATH (ensure $LOCAL_BIN is on PATH)"
}

# --- Sync project .grok/config.yaml → ~/.grok (full override of managed local config) ---

sync_grok_config() {
  if [ "$SKIP_GROK_CONFIG_SYNC" = 1 ]; then
    log "skip grok config sync (--skip-grok-config-sync)"
    return 0
  fi
  if [ -z "$BOOTSTRAP_ROOT" ] || [ ! -f "$BOOTSTRAP_ROOT/.grok/config.yaml" ]; then
    warn "no project .grok/config.yaml (run install from herdr-bootstrap clone)"
    return 0
  fi
  sync_bin="$BOOTSTRAP_ROOT/bin/sync-grok-config"
  if [ ! -f "$sync_bin" ]; then
    warn "missing bin/sync-grok-config"
    return 0
  fi
  log "syncing project .grok/config.yaml → ~/.grok/config.yaml + config.toml"
  if [ "$DRY_RUN" = 1 ]; then
    python3 "$sync_bin" --dry-run || warn "sync-grok-config dry-run failed"
    return 0
  fi
  python3 "$sync_bin" || warn "sync-grok-config failed"
  # ensure project lsp.json is present (committed file)
  if [ -f "$BOOTSTRAP_ROOT/.grok/lsp.json" ]; then
    log "project LSP config: $BOOTSTRAP_ROOT/.grok/lsp.json"
  fi
}

# --- Sync versioned global Herdr config → ~/.config/herdr/config.toml ---

sync_herdr_config() {
  if [ "$SKIP_HERDR_CONFIG_SYNC" = 1 ]; then
    log "skip herdr global config sync (--skip-herdr-config-sync)"
    return 0
  fi
  if [ -z "$BOOTSTRAP_ROOT" ] || [ ! -f "$BOOTSTRAP_ROOT/config/herdr/config.toml" ]; then
    warn "no config/herdr/config.toml (run install from herdr-bootstrap clone)"
    return 0
  fi
  sync_bin="$BOOTSTRAP_ROOT/bin/sync-herdr-config"
  if [ ! -f "$sync_bin" ]; then
    warn "missing bin/sync-herdr-config"
    return 0
  fi
  log "syncing config/herdr/config.toml → ~/.config/herdr/config.toml (all agents)"
  if [ "$DRY_RUN" = 1 ]; then
    python3 "$sync_bin" --dry-run || warn "sync-herdr-config dry-run failed"
    return 0
  fi
  python3 "$sync_bin" || warn "sync-herdr-config failed"
}

# --- Integrations ---

install_integrations() {
  if [ "$SKIP_INTEGRATIONS" = 1 ]; then
    log "skip integrations (--skip-integrations)"
    return 0
  fi

  if ! command -v herdr >/dev/null 2>&1; then
    warn "herdr not on PATH; skip integrations"
    return 0
  fi

  try_integration() {
    name="$1"
    marker="$2"
    [ -e "$marker" ] || return 0
    log "herdr integration install $name"
    if [ "$DRY_RUN" = 1 ]; then
      return 0
    fi
    herdr integration install "$name" >/dev/null 2>&1 || warn "integration install $name failed"
  }

  # Grok first (primary on this bootstrap)
  try_integration grok "$HOME/.grok"
  try_integration claude "$HOME/.claude"
  try_integration codex "$HOME/.codex"
  try_integration cursor "$HOME/.cursor"
  try_integration copilot "$HOME/.copilot"
  try_integration opencode "$HOME/.config/opencode"
  try_integration pi "$HOME/.pi/agent"
  try_integration devin "$HOME/.config/devin"
  try_integration droid "$HOME/.factory"
  try_integration kimi "$HOME/.kimi-code"
  try_integration hermes "$HOME/.hermes"
  try_integration qodercli "$HOME/.qoder"
}

# --- verify ---

verify() {
  log "verification"
  ok=1
  for c in herdr node npx; do
    if command -v "$c" >/dev/null 2>&1; then
      printf '  OK  %s -> %s\n' "$c" "$(command -v "$c")"
    else
      printf '  MISS %s\n' "$c"
      ok=0
    fi
  done
  if command -v grok >/dev/null 2>&1; then
    printf '  OK  grok -> %s\n' "$(command -v grok)"
  else
    printf '  MISS grok (optional if --skip-grok)\n'
  fi

  if [ -f "$HOME/.agents/skills/herdr/SKILL.md" ]; then
    printf '  OK  canonical skill\n'
  else
    printf '  MISS canonical skill\n'
    [ "$SKIP_SKILLS" = 1 ] || ok=0
  fi
  if [ -f "$HOME/.grok/skills/herdr/SKILL.md" ]; then
    printf '  OK  grok skill path\n'
  else
    printf '  MISS grok skill path\n'
  fi
  if [ -f "$HOME/.agents/skills/docs-wiki/SKILL.md" ]; then
    printf '  OK  docs-wiki skill\n'
  else
    printf '  MISS docs-wiki skill\n'
  fi
  if [ -f "$HOME/.grok/skills/docs-wiki/SKILL.md" ] || [ -L "$HOME/.grok/skills/docs-wiki" ]; then
    printf '  OK  grok docs-wiki path\n'
  else
    printf '  MISS grok docs-wiki path\n'
  fi
  if command -v herdr-docs-wiki >/dev/null 2>&1 || command -v herdr-doctor >/dev/null 2>&1; then
    printf '  OK  herdr-docs-wiki CLI\n'
  else
    printf '  MISS herdr-docs-wiki CLI (build plugin from clone)\n'
  fi
  if command -v rust-analyzer >/dev/null 2>&1; then
    printf '  OK  rust-analyzer -> %s\n' "$(command -v rust-analyzer)"
  else
    printf '  MISS rust-analyzer (Rust LSP)\n'
  fi
  if command -v gopls >/dev/null 2>&1; then
    printf '  OK  gopls -> %s\n' "$(command -v gopls)"
  else
    printf '  MISS gopls (Go LSP)\n'
  fi
  if [ -f "$HOME/.grok/config.toml" ] && grep -q 'lsp_tools\s*=\s*true' "$HOME/.grok/config.toml" 2>/dev/null; then
    printf '  OK  ~/.grok/config.toml lsp_tools=true\n'
  else
    printf '  MISS ~/.grok lsp_tools (run bin/sync-grok-config)\n'
  fi
  if [ -n "$BOOTSTRAP_ROOT" ] && [ -f "$BOOTSTRAP_ROOT/.grok/lsp.json" ]; then
    if grep -q '"rust"' "$BOOTSTRAP_ROOT/.grok/lsp.json" 2>/dev/null && \
       grep -q '"go"' "$BOOTSTRAP_ROOT/.grok/lsp.json" 2>/dev/null; then
      printf '  OK  project .grok/lsp.json (rust + go)\n'
    else
      printf '  MISS project .grok/lsp.json incomplete (need rust + go)\n'
    fi
  fi
  if [ -n "$BOOTSTRAP_ROOT" ] && [ -f "$BOOTSTRAP_ROOT/.grok/config.yaml" ]; then
    printf '  OK  project .grok/config.yaml (source of truth)\n'
  fi
  if [ -n "$BOOTSTRAP_ROOT" ] && [ -f "$BOOTSTRAP_ROOT/config/herdr/config.toml" ]; then
    printf '  OK  project config/herdr/config.toml (Herdr global source of truth)\n'
  else
    printf '  MISS project config/herdr/config.toml\n'
    ok=0
  fi
  if [ -f "$HOME/.config/herdr/config.toml" ] && \
     grep -q 'kitty_graphics\s*=\s*true' "$HOME/.config/herdr/config.toml" 2>/dev/null; then
    printf '  OK  ~/.config/herdr/config.toml kitty_graphics=true\n'
  else
    printf '  MISS ~/.config/herdr kitty_graphics (run bin/sync-herdr-config)\n'
  fi
  if [ -f "$HOME/.config/herdr/config.toml" ] && \
     grep -q 'jewell.maps' "$HOME/.config/herdr/config.toml" 2>/dev/null; then
    printf '  OK  ~/.config/herdr/config.toml maps keybindings\n'
  else
    printf '  MISS herdr maps keybindings in global config\n'
  fi

  if command -v herdr >/dev/null 2>&1; then
    herdr --version 2>/dev/null | sed 's/^/  /' || true
  fi
  if command -v node >/dev/null 2>&1; then
    printf '  node %s\n' "$(node -v)"
  fi

  if [ "$ok" = 0 ]; then
    die "verification failed"
  fi
}

# --- main ---

install_node
install_herdr
install_grok
install_skill
link_skill_native_dirs
install_docs_wiki_plugin
install_rust_analyzer
install_gopls
sync_grok_config
sync_herdr_config
install_integrations
verify

cat <<'EOF'

Bootstrap complete.

Next steps:
  1. Open a new terminal (or: source ~/.zshrc)
  2. If needed: grok login
  3. From a normal terminal (not nested):  herdr
  4. Start your agent in a pane (e.g. grok)
  5. First-run walkthrough: https://herdr.dev/agent-guide.md
  6. Project wiki: docs/ + skill docs-wiki; doctor: herdr-docs-wiki doctor
  7. Grok config source of truth: .grok/config.yaml → bin/sync-grok-config
  8. Herdr global config source of truth: config/herdr/config.toml → bin/sync-herdr-config
  9. LSP: .grok/lsp.json (rust-analyzer + gopls) + lsp_tools in ~/.grok/config.toml

Docs: https://herdr.dev/docs/  |  Plugins: https://herdr.dev/plugins/  |  Blog: https://herdr.dev/blog/
Source: https://github.com/herdrdev/herdr
Wiki rules: docs/ (see docs/index.md)  |  policy/llm-wiki.toml
EOF
