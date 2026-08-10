#!/usr/bin/env sh
# Herdr machine bootstrap — idempotent install/update of herdr, WezTerm (outer
# terminal, Herdr-compatible, required default terminal), Node/npx, Grok, agent
# skills (herdr, llm-wiki, docs-wiki), agent-native skill symlinks (#1874 /
# PR #1883), Grok integration hooks, global Herdr + WezTerm config sync, and
# plugins.
#
# Usage:
#   sh install.sh [--skip-node] [--skip-grok] [--skip-skills] [--skip-integrations] [--skip-plugin] [--skip-wezterm] [--skip-herdr-config-sync] [--skip-wezterm-config-sync] [--dry-run]
#   # or: curl -fsSL <raw-url-of-this-repo>/install.sh | sh
#
# Plugins: clones/pulls https://github.com/tyler-jewell/herdr-plugins (all subdirs
# with herdr-plugin.toml), builds each (Go/Rust), and `herdr plugin link`s them.
# Override: HERDR_PLUGINS_ROOT, HERDR_PLUGINS_GIT_URL, HERDR_PLUGINS_REF.
#
# WezTerm is the required outer terminal (not optional preference):
#   - install binary + Herdr-tuned config
#   - register as default terminal where the OS allows (no sudo)
#   - export TERMINAL=wezterm in shell rc
#   --skip-wezterm is the only escape hatch (break-glass / CI)
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
SKIP_LUA_LS=0
SKIP_GROK_CONFIG_SYNC=0
SKIP_HERDR_CONFIG_SYNC=0
SKIP_WEZTERM=0
SKIP_WEZTERM_CONFIG_SYNC=0
DRY_RUN=0

# WezTerm release tag (stable). Override: WEZTERM_VERSION=...
WEZTERM_VERSION="${WEZTERM_VERSION:-20240203-110809-5046fc22}"
WEZTERM_GITHUB="https://github.com/wezterm/wezterm/releases/download"

NODE_VERSION="${NODE_VERSION:-22.18.0}"
HERDR_INSTALL_DIR="${HERDR_INSTALL_DIR:-$HOME/.local/bin}"
NODE_PREFIX="${NODE_PREFIX:-$HOME/.local/node}"
LOCAL_BIN="${LOCAL_BIN:-$HOME/.local/bin}"
SHARE_HERDR="${SHARE_HERDR:-$HOME/.local/share/herdr}"
APPLY_SKILLS_SYMLINK_WORKAROUND="${APPLY_SKILLS_SYMLINK_WORKAROUND:-1}"

# Resolve repo root when install.sh is run from a clone (not curl|sh).
# Handles: ./install.sh, sh install.sh, sh ./install.sh, /path/to/install.sh
# curl|sh has no script file → BOOTSTRAP_ROOT stays empty (skip clone-only steps).
BOOTSTRAP_ROOT=""
if [ -f "$0" ]; then
  BOOTSTRAP_ROOT="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
  if [ ! -f "$BOOTSTRAP_ROOT/AGENTS.md" ]; then
    BOOTSTRAP_ROOT=""
  fi
fi

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
    --skip-lua-ls) SKIP_LUA_LS=1 ;;
    --skip-grok-config-sync) SKIP_GROK_CONFIG_SYNC=1 ;;
    --skip-herdr-config-sync) SKIP_HERDR_CONFIG_SYNC=1 ;;
    --skip-wezterm) SKIP_WEZTERM=1 ;;
    --skip-wezterm-config-sync) SKIP_WEZTERM_CONFIG_SYNC=1 ;;
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

# Progress on stderr so $(fn) path-returns stay clean.
log()  { printf '==> %s\n' "$*" >&2; }
warn() { printf '!!  %s\n' "$*" >&2; }
die()  { printf 'XX  %s\n' "$*" >&2; exit 1; }

run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '[dry-run] %s\n' "$*" >&2
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

  # Karpathy pattern skill (literacy); operational docs-wiki skill comes from herdr-plugins monorepo
  log "installing llm-wiki pattern skill (ar9av/obsidian-wiki --skill llm-wiki -g)"
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] would run: npx --yes skills add ar9av/obsidian-wiki --skill llm-wiki -g -y"
  else
    npx --yes skills add ar9av/obsidian-wiki --skill llm-wiki -g -y || \
      warn "llm-wiki skills add failed (non-fatal)"
  fi
  # docs-wiki skill: installed from herdr-plugins after monorepo pull (install_herdr_plugins)
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

# --- Herdr plugins (public monorepo tyler-jewell/herdr-plugins) ---
# Always clone/pull the monorepo, then build + link every plugin subdir.

HERDR_PLUGINS_GIT_URL="${HERDR_PLUGINS_GIT_URL:-https://github.com/tyler-jewell/herdr-plugins.git}"
HERDR_PLUGINS_REF="${HERDR_PLUGINS_REF:-main}"
# Managed checkout when no override / sibling:
HERDR_PLUGINS_CACHE="${HERDR_PLUGINS_CACHE:-$HOME/.local/share/herdr-bootstrap/herdr-plugins}"

# ensure_herdr_plugins_repo → prints absolute path to monorepo checkout (or fails)
ensure_herdr_plugins_repo() {
  dest=""
  if [ -n "${HERDR_PLUGINS_ROOT:-}" ]; then
    dest="$HERDR_PLUGINS_ROOT"
  elif [ -n "$BOOTSTRAP_ROOT" ] && [ -d "$BOOTSTRAP_ROOT/../herdr-plugins/.git" ]; then
    dest="$(CDPATH= cd -- "$BOOTSTRAP_ROOT/../herdr-plugins" && pwd)"
  elif [ -d "$HOME/herdr-plugins/.git" ]; then
    dest="$HOME/herdr-plugins"
  else
    dest="$HERDR_PLUGINS_CACHE"
  fi

  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] would ensure git clone/pull $HERDR_PLUGINS_GIT_URL → $dest (ref=$HERDR_PLUGINS_REF)"
    printf '%s\n' "$dest"
    return 0
  fi

  if ! command -v git >/dev/null 2>&1; then
    warn "git not on PATH; cannot pull herdr-plugins monorepo"
    if [ -d "$dest" ] && find "$dest" -maxdepth 2 -name herdr-plugin.toml 2>/dev/null | grep -q .; then
      printf '%s\n' "$dest"
      return 0
    fi
    return 1
  fi

  if [ -d "$dest/.git" ]; then
    log "updating herdr-plugins: $dest (fetch $HERDR_PLUGINS_REF)"
    (
      CDPATH= cd -- "$dest" || exit 1
      git fetch --quiet origin 2>/dev/null || git fetch --quiet 2>/dev/null || true
      # Prefer checkout/pull of configured ref; leave local dirty work alone with soft pull
      if git show-ref --verify --quiet "refs/remotes/origin/$HERDR_PLUGINS_REF" 2>/dev/null; then
        git checkout -q "$HERDR_PLUGINS_REF" 2>/dev/null || true
        git pull --ff-only --quiet origin "$HERDR_PLUGINS_REF" 2>/dev/null || \
          git pull --ff-only --quiet 2>/dev/null || \
          warn "git pull herdr-plugins failed (using local tree)"
      else
        git pull --ff-only --quiet 2>/dev/null || warn "git pull herdr-plugins failed (using local tree)"
      fi
    ) || warn "herdr-plugins update had issues; continuing with $dest"
  elif [ -d "$dest" ] && [ ! -d "$dest/.git" ]; then
    warn "$dest exists but is not a git repo; using as-is (set HERDR_PLUGINS_ROOT to override)"
  else
    log "cloning herdr-plugins → $dest"
    mkdir -p "$(dirname "$dest")"
    if ! git clone --depth 1 --branch "$HERDR_PLUGINS_REF" \
        "$HERDR_PLUGINS_GIT_URL" "$dest" 2>/dev/null; then
      # branch may not exist on shallow; try default branch
      git clone --depth 1 "$HERDR_PLUGINS_GIT_URL" "$dest" || {
        warn "git clone herdr-plugins failed: $HERDR_PLUGINS_GIT_URL"
        return 1
      }
    fi
  fi

  if ! find "$dest" -maxdepth 2 -name herdr-plugin.toml 2>/dev/null | grep -q .; then
    warn "no herdr-plugin.toml under $dest"
    return 1
  fi
  printf '%s\n' "$dest"
}

link_plugin_dir() {
  plug="$1"
  [ -d "$plug" ] || return 1
  herdr plugin link "$plug" 2>/dev/null || \
    herdr plugin link "$plug" --yes 2>/dev/null || \
    warn "herdr plugin link failed: $plug"
}

# Build one plugin directory (Go or Rust) from heuristics + common layouts.
build_one_plugin() {
  plug="$1"
  name="$(basename "$plug")"
  log "building plugin: $name ($plug)"

  if [ -f "$plug/go.mod" ]; then
    if ! command -v go >/dev/null 2>&1; then
      warn "go not on PATH; skip Go plugin $name"
      return 1
    fi
    mkdir -p "$plug/bin"
    built=0
    if [ -d "$plug/cmd" ]; then
      for cmd_dir in "$plug/cmd"/*; do
        [ -d "$cmd_dir" ] || continue
        bin="$(basename "$cmd_dir")"
        if (cd "$plug" && go build -o "bin/$bin" "./cmd/$bin"); then
          ln -sfn "$plug/bin/$bin" "$LOCAL_BIN/$bin"
          built=1
        else
          warn "go build failed: $name / $bin"
        fi
      done
    fi
    if [ "$built" = 0 ]; then
      # single-package main at root
      if [ -f "$plug/main.go" ]; then
        if (cd "$plug" && go build -o "bin/$name" .); then
          ln -sfn "$plug/bin/$name" "$LOCAL_BIN/$name"
          built=1
        fi
      fi
    fi
    [ "$built" = 1 ] || return 1
    return 0
  fi

  if [ -f "$plug/Cargo.toml" ]; then
    if ! command -v cargo >/dev/null 2>&1; then
      warn "cargo not on PATH; skip Rust plugin $name"
      return 1
    fi
    (cd "$plug" && cargo build --release) || {
      warn "cargo build --release failed: $name"
      return 1
    }
    # Symlink release binaries that look like CLIs
    if [ -d "$plug/target/release" ]; then
      for bin in "$plug/target/release"/*; do
        [ -f "$bin" ] && [ -x "$bin" ] || continue
        b="$(basename "$bin")"
        case "$b" in
          *.d|*.rlib|*.so|*.dylib|*.a) continue ;;
          build|deps|examples|incremental|native) continue ;;
        esac
        # skip if looks like a directory leaked
        [ -d "$bin" ] && continue
        ln -sfn "$bin" "$LOCAL_BIN/$b" 2>/dev/null || true
      done
    fi
    return 0
  fi

  # Manifest-only / script plugin — still linkable if commands exist
  log "no go.mod/Cargo.toml in $name; linking as-is (manifest commands must work)"
  return 0
}

install_herdr_plugins() {
  if [ "$SKIP_PLUGIN" = 1 ]; then
    log "skip plugins (--skip-plugin)"
    return 0
  fi
  if ! command -v herdr >/dev/null 2>&1; then
    warn "herdr not on PATH; skip plugins"
    return 0
  fi

  plugins_root=""
  if ! plugins_root="$(ensure_herdr_plugins_repo)"; then
    warn "could not obtain herdr-plugins monorepo from $HERDR_PLUGINS_GIT_URL"
    return 0
  fi
  log "herdr-plugins monorepo: $plugins_root"

  # Pin wiki policy for docs-wiki
  if [ -n "$BOOTSTRAP_ROOT" ] && [ -f "$BOOTSTRAP_ROOT/policy/llm-wiki.toml" ]; then
    if [ "$DRY_RUN" = 0 ]; then
      mkdir -p "$HOME/.config/herdr-bootstrap"
      cp -f "$BOOTSTRAP_ROOT/policy/llm-wiki.toml" "$HOME/.config/herdr-bootstrap/llm-wiki.toml"
      log "pinned wiki policy → ~/.config/herdr-bootstrap/llm-wiki.toml"
    fi
  fi

  # Agent skills shipped with the monorepo (not in herdr-bootstrap)
  install_skills_from_monorepo "$plugins_root"

  # Discover every first-level subdir with herdr-plugin.toml and install all
  count=0
  linked=0
  for toml in "$plugins_root"/*/herdr-plugin.toml; do
    [ -f "$toml" ] || continue
    plug="$(CDPATH= cd -- "$(dirname "$toml")" && pwd)"
    count=$((count + 1))
    if [ "$DRY_RUN" = 1 ]; then
      log "[dry-run] would build + herdr plugin link $plug"
      continue
    fi
    if build_one_plugin "$plug"; then
      if link_plugin_dir "$plug"; then
        linked=$((linked + 1))
      fi
    else
      # still try link if binaries already present from prior build
      link_plugin_dir "$plug" || true
    fi
  done

  if [ "$count" = 0 ]; then
    warn "no plugins found under $plugins_root/*/herdr-plugin.toml"
  else
    log "herdr-plugins: processed $count plugin(s) (linked/attempted from $plugins_root)"
  fi

  # Re-link native skill dirs after monorepo skills land (docs-wiki, …)
  if [ "$SKIP_SKILLS" != 1 ]; then
    link_skill_native_dirs
  fi

  # Keybindings for jewell.docs-wiki / jewell.agent-browser live in config/herdr/config.toml (sync_herdr_config).
}

# Install agent skills from monorepo skills/<name>/SKILL.md → ~/.agents/skills/<name>
install_skills_from_monorepo() {
  plugins_root="$1"
  skills_dir="$plugins_root/skills"
  if [ ! -d "$skills_dir" ]; then
    log "no skills/ tree in monorepo (ok if none shipped yet)"
    return 0
  fi
  if [ "$SKIP_SKILLS" = 1 ]; then
    log "skip monorepo skills (--skip-skills)"
    return 0
  fi
  for skill_src in "$skills_dir"/*; do
    [ -d "$skill_src" ] || continue
    [ -f "$skill_src/SKILL.md" ] || continue
    name="$(basename "$skill_src")"
    dest="$HOME/.agents/skills/$name"
    log "installing monorepo skill $name → $dest"
    if [ "$DRY_RUN" = 1 ]; then
      log "[dry-run] would copy $skill_src → $dest"
      continue
    fi
    mkdir -p "$dest"
    if command -v rsync >/dev/null 2>&1; then
      rsync -a --delete "$skill_src/" "$dest/"
    else
      rm -rf "$dest"
      mkdir -p "$dest"
      cp -R "$skill_src/." "$dest/"
    fi
  done
}

# --- rust-analyzer (Grok Rust LSP) ---

# True if rust-analyzer on PATH actually runs (cargo/bin/rust-analyzer → rustup stub can fail).
rust_analyzer_ok() {
  command -v rust-analyzer >/dev/null 2>&1 || return 1
  rust-analyzer --version >/dev/null 2>&1
}

install_rust_analyzer() {
  if [ "$SKIP_RUST_ANALYZER" = 1 ]; then
    log "skip rust-analyzer (--skip-rust-analyzer)"
    return 0
  fi
  if rust_analyzer_ok; then
    log "rust-analyzer present: $(command -v rust-analyzer) ($(rust-analyzer --version 2>/dev/null | head -1))"
    return 0
  fi
  log "installing rust-analyzer"
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] would install rust-analyzer"
    return 0
  fi
  mkdir -p "$LOCAL_BIN"
  if command -v rustup >/dev/null 2>&1; then
    rustup component add rust-analyzer || warn "rustup component add rust-analyzer failed"
    # rustup's ~/.cargo/bin/rust-analyzer is a proxy; link the real toolchain binary into LOCAL_BIN
    # so PATH ($LOCAL_BIN first) always hits a working binary.
    ra_real="$(rustup which rust-analyzer 2>/dev/null || true)"
    if [ -n "$ra_real" ] && [ -x "$ra_real" ]; then
      ln -sfn "$ra_real" "$LOCAL_BIN/rust-analyzer"
      export PATH="$LOCAL_BIN:$PATH"
      if rust_analyzer_ok; then
        log "rust-analyzer linked: $LOCAL_BIN/rust-analyzer → $ra_real"
        return 0
      fi
    fi
  fi
  if command -v brew >/dev/null 2>&1; then
    brew install rust-analyzer || warn "brew install rust-analyzer failed"
    if rust_analyzer_ok; then
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
    gunzip -c "$tmp" >"$LOCAL_BIN/rust-analyzer" || {
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
  export PATH="$LOCAL_BIN:$PATH"
  rust_analyzer_ok || warn "rust-analyzer still not working on PATH"
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

# --- lua-language-server (Grok Lua LSP / WezTerm config) ---

install_lua_language_server() {
  if [ "$SKIP_LUA_LS" = 1 ]; then
    log "skip lua-language-server (--skip-lua-ls)"
    return 0
  fi
  if command -v lua-language-server >/dev/null 2>&1; then
    log "lua-language-server present: $(command -v lua-language-server)"
    return 0
  fi
  log "installing lua-language-server (LuaLS)"
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] would install lua-language-server"
    return 0
  fi

  # Prefer brew when available
  if command -v brew >/dev/null 2>&1; then
    brew install lua-language-server || warn "brew install lua-language-server failed"
    if command -v lua-language-server >/dev/null 2>&1; then
      log "lua-language-server via brew: $(command -v lua-language-server)"
      return 0
    fi
  fi

  arch="$(uname -m)"
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "$os-$arch" in
    darwin-arm64|darwin-aarch64) asset_triple="darwin-arm64" ;;
    darwin-x86_64) asset_triple="darwin-x64" ;;
    linux-x86_64|linux-amd64) asset_triple="linux-x64" ;;
    linux-arm64|linux-aarch64) asset_triple="linux-arm64" ;;
    *)
      warn "no portable lua-language-server asset for $os-$arch; install from https://github.com/LuaLS/lua-language-server/releases"
      return 0
      ;;
  esac

  # Pin via LUALS_VERSION or resolve latest tag from GitHub API
  ver="${LUALS_VERSION:-}"
  if [ -z "$ver" ]; then
    ver="$(curl -fsSL https://api.github.com/repos/LuaLS/lua-language-server/releases/latest \
      | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name',''))" 2>/dev/null || true)"
  fi
  if [ -z "$ver" ]; then
    ver="3.19.0"
    warn "could not resolve latest lua-language-server; falling back to $ver"
  fi
  # tag may be "3.19.0" without v
  ver="${ver#v}"

  asset="lua-language-server-${ver}-${asset_triple}.tar.gz"
  url="https://github.com/LuaLS/lua-language-server/releases/download/${ver}/${asset}"
  share="${SHARE_LUALS:-$HOME/.local/share/lua-language-server}"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/luals.XXXXXX")"

  log "downloading $asset"
  if ! curl -fsSL "$url" -o "$tmp/$asset"; then
    rm -rf "$tmp"
    warn "download lua-language-server failed: $url"
    return 0
  fi
  mkdir -p "$share"
  # Replace previous portable tree
  rm -rf "$share/bin" "$share/locale" "$share/meta" "$share/script" 2>/dev/null || true
  # Extract (tarball roots at bin/, locale/, …)
  tar -xzf "$tmp/$asset" -C "$share" || {
    rm -rf "$tmp"
    warn "extract lua-language-server failed"
    return 0
  }
  rm -rf "$tmp"

  if [ ! -x "$share/bin/lua-language-server" ]; then
    warn "lua-language-server binary missing after extract ($share/bin)"
    return 0
  fi

  # Wrapper: the real binary resolves assets relative to its install tree;
  # a bare symlink from ~/.local/bin can break that on some platforms.
  mkdir -p "$LOCAL_BIN"
  cat >"$LOCAL_BIN/lua-language-server" <<EOF
#!/usr/bin/env sh
set -eu
exec "$share/bin/lua-language-server" "\$@"
EOF
  chmod +x "$LOCAL_BIN/lua-language-server"
  export PATH="$LOCAL_BIN:$PATH"
  log "installed $LOCAL_BIN/lua-language-server → $share (v$ver)"
  command -v lua-language-server >/dev/null 2>&1 || warn "lua-language-server still not on PATH"
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
  sync_grok_harness_surfaces
}

# Mirror versioned .grok/{rules,hooks,agents,personas} → ~/.grok/ (dotfiles shape)
sync_grok_harness_surfaces() {
  if [ -z "$BOOTSTRAP_ROOT" ] || [ ! -d "$BOOTSTRAP_ROOT/.grok" ]; then
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] would sync .grok/{rules,hooks,agents,personas} → ~/.grok/"
    return 0
  fi
  for surface in rules hooks agents personas; do
    src="$BOOTSTRAP_ROOT/.grok/$surface"
    dst="$HOME/.grok/$surface"
    if [ ! -d "$src" ]; then
      continue
    fi
    mkdir -p "$dst"
    if command -v rsync >/dev/null 2>&1; then
      rsync -a "$src/" "$dst/"
    else
      cp -R "$src/." "$dst/"
    fi
    log "synced .grok/$surface → ~/.grok/$surface"
  done
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

# --- WezTerm (outer terminal for Herdr) ---

# Ensure macOS WezTerm.app CLI tools are on PATH when installed as an app bundle.
ensure_wezterm_path() {
  if command -v wezterm >/dev/null 2>&1; then
    return 0
  fi
  for app in \
    "$HOME/Applications/WezTerm.app" \
    "/Applications/WezTerm.app"
  do
    if [ -x "$app/Contents/MacOS/wezterm" ]; then
      ln -sfn "$app/Contents/MacOS/wezterm" "$LOCAL_BIN/wezterm"
      if [ -x "$app/Contents/MacOS/wezterm-gui" ]; then
        ln -sfn "$app/Contents/MacOS/wezterm-gui" "$LOCAL_BIN/wezterm-gui"
      fi
      export PATH="$LOCAL_BIN:$PATH"
      log "linked wezterm CLI from $app → $LOCAL_BIN"
      return 0
    fi
  done
  return 1
}

install_wezterm_macos_portable() {
  # User-local app (no sudo). Prefer ~/Applications.
  apps_dir="$HOME/Applications"
  zip_name="WezTerm-macos-${WEZTERM_VERSION}.zip"
  url="${WEZTERM_GITHUB}/${WEZTERM_VERSION}/${zip_name}"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/wezterm-mac.XXXXXX")"
  log "downloading WezTerm macOS ${WEZTERM_VERSION}"
  if ! curl -fsSL "$url" -o "$tmp/$zip_name"; then
    rm -rf "$tmp"
    warn "WezTerm macOS download failed: $url"
    return 1
  fi
  if ! command -v unzip >/dev/null 2>&1; then
    rm -rf "$tmp"
    warn "unzip not found; cannot extract WezTerm.app"
    return 1
  fi
  unzip -q "$tmp/$zip_name" -d "$tmp/extract" || {
    rm -rf "$tmp"
    warn "WezTerm zip extract failed"
    return 1
  }
  # Zip layout: WezTerm.app at top or under a versioned dir
  app_src="$(find "$tmp/extract" -maxdepth 3 -name 'WezTerm.app' -type d 2>/dev/null | head -n1)"
  if [ -z "$app_src" ] || [ ! -d "$app_src" ]; then
    rm -rf "$tmp"
    warn "WezTerm.app not found inside zip"
    return 1
  fi
  mkdir -p "$apps_dir"
  # Replace previous portable install atomically-ish
  rm -rf "$apps_dir/WezTerm.app"
  mv "$app_src" "$apps_dir/WezTerm.app"
  rm -rf "$tmp"
  # Clear quarantine when possible (first-open Gatekeeper friction)
  if command -v xattr >/dev/null 2>&1; then
    xattr -dr com.apple.quarantine "$apps_dir/WezTerm.app" 2>/dev/null || true
  fi
  ensure_wezterm_path || true
  log "installed $apps_dir/WezTerm.app"
  return 0
}

install_wezterm_linux_appimage() {
  # x86_64 AppImage (stable). No sudo.
  img_name="WezTerm-${WEZTERM_VERSION}-Ubuntu20.04.AppImage"
  url="${WEZTERM_GITHUB}/${WEZTERM_VERSION}/${img_name}"
  dest="$LOCAL_BIN/wezterm"
  share="$HOME/.local/share/wezterm"
  mkdir -p "$LOCAL_BIN" "$share"
  log "downloading WezTerm AppImage ${WEZTERM_VERSION}"
  tmp="$(mktemp "${TMPDIR:-/tmp}/wezterm-appimage.XXXXXX")"
  if ! curl -fsSL "$url" -o "$tmp"; then
    rm -f "$tmp"
    warn "WezTerm AppImage download failed: $url"
    return 1
  fi
  chmod +x "$tmp"
  mv "$tmp" "$share/WezTerm.AppImage"
  # Wrapper so FUSE-less hosts still run (APPIMAGE_EXTRACT_AND_RUN)
  cat >"$dest" <<'WRAP'
#!/usr/bin/env sh
set -eu
APPIMAGE="${HERDR_WEZTERM_APPIMAGE:-$HOME/.local/share/wezterm/WezTerm.AppImage}"
if [ ! -x "$APPIMAGE" ]; then
  echo "wezterm AppImage missing: $APPIMAGE" >&2
  exit 127
fi
export APPIMAGE_EXTRACT_AND_RUN="${APPIMAGE_EXTRACT_AND_RUN:-1}"
exec "$APPIMAGE" "$@"
WRAP
  chmod +x "$dest"
  log "installed AppImage → $share/WezTerm.AppImage (CLI $dest)"
  return 0
}

install_wezterm_linux_deb_extract() {
  # Extract .deb payload without root (aarch64 and x86_64 fallback).
  case "$ARCH" in
    arm64|aarch64)
      deb_name="wezterm-${WEZTERM_VERSION}.Ubuntu22.04.arm64.deb"
      ;;
    x86_64|amd64)
      deb_name="wezterm-${WEZTERM_VERSION}.Ubuntu22.04.deb"
      ;;
    *)
      warn "no portable WezTerm .deb for arch $ARCH"
      return 1
      ;;
  esac
  url="${WEZTERM_GITHUB}/${WEZTERM_VERSION}/${deb_name}"
  share="$HOME/.local/share/wezterm"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/wezterm-deb.XXXXXX")"
  log "downloading WezTerm .deb ${deb_name} (extract, no sudo)"
  if ! curl -fsSL "$url" -o "$tmp/wezterm.deb"; then
    rm -rf "$tmp"
    warn "WezTerm .deb download failed: $url"
    return 1
  fi
  (
    cd "$tmp" || exit 1
    if command -v ar >/dev/null 2>&1; then
      ar x wezterm.deb
    elif command -v bsdtar >/dev/null 2>&1; then
      bsdtar -xf wezterm.deb
    else
      warn "need ar or bsdtar to extract .deb"
      exit 1
    fi
    data="$(ls data.tar.* 2>/dev/null | head -n1)"
    [ -n "$data" ] || { warn "no data.tar in deb"; exit 1; }
    mkdir -p root
    case "$data" in
      *.xz) tar -xJf "$data" -C root ;;
      *.gz) tar -xzf "$data" -C root ;;
      *.zst)
        if command -v zstd >/dev/null 2>&1; then
          zstd -d "$data" -o data.tar && tar -xf data.tar -C root
        else
          warn "zstd required to extract $data"
          exit 1
        fi
        ;;
      *) tar -xf "$data" -C root ;;
    esac
  ) || {
    rm -rf "$tmp"
    return 1
  }
  bin_src="$tmp/root/usr/bin"
  if [ ! -x "$bin_src/wezterm" ]; then
    # some packages use libexec layout
    bin_src="$(find "$tmp/root" -type f -name wezterm 2>/dev/null | head -n1)"
    bin_src="$(dirname "${bin_src:-}")"
  fi
  if [ ! -x "$bin_src/wezterm" ]; then
    rm -rf "$tmp"
    warn "wezterm binary not found inside deb"
    return 1
  fi
  mkdir -p "$share/bin"
  # Copy tree of usr so shared libs next to bin stay relative if any
  if [ -d "$tmp/root/usr" ]; then
    rm -rf "$share/usr"
    cp -R "$tmp/root/usr" "$share/usr"
    ln -sfn "$share/usr/bin/wezterm" "$LOCAL_BIN/wezterm"
    [ -x "$share/usr/bin/wezterm-gui" ] && ln -sfn "$share/usr/bin/wezterm-gui" "$LOCAL_BIN/wezterm-gui"
  else
    cp -f "$bin_src/wezterm" "$share/bin/wezterm"
    chmod +x "$share/bin/wezterm"
    ln -sfn "$share/bin/wezterm" "$LOCAL_BIN/wezterm"
  fi
  rm -rf "$tmp"
  log "installed WezTerm from deb extract → $share"
  return 0
}

# Resolve absolute path to the wezterm CLI (for desktop Exec= and symlinks).
wezterm_cli_path() {
  if command -v wezterm >/dev/null 2>&1; then
    command -v wezterm
    return 0
  fi
  if [ -x "$LOCAL_BIN/wezterm" ]; then
    printf '%s\n' "$LOCAL_BIN/wezterm"
    return 0
  fi
  return 1
}

# Linux .desktop entry (GUI launchers + TerminalEmulator category).
# Idempotent; written for every Linux install path (brew / AppImage / deb).
write_wezterm_desktop_entry() {
  wt="$1"
  apps="$HOME/.local/share/applications"
  desktop="$apps/org.wezfurlong.wezterm.desktop"
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] would write $desktop Exec=$wt"
    return 0
  fi
  mkdir -p "$apps"
  cat >"$desktop" <<EOF
[Desktop Entry]
Name=WezTerm
Comment=Wez's Terminal Emulator (herdr-bootstrap required outer terminal)
TryExec=$wt
Exec=$wt %F
Icon=org.wezfurlong.wezterm
Terminal=false
Type=Application
Categories=System;TerminalEmulator;Utility;
StartupNotify=true
Keywords=shell;prompt;command;commandline;cmd;terminal;
EOF
  log "wrote desktop entry: $desktop"
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$apps" 2>/dev/null || true
  fi
}

# REQUIRED: make WezTerm the default outer terminal for this machine (no sudo).
# Part of install_wezterm — not a separate flag. Only --skip-wezterm skips this.
#
# Linux: .desktop + xdg-terminals.list + GNOME gsettings + $TERMINAL + user-local
#        x-terminal-emulator shadow on PATH.
# macOS: no OS-wide default-terminal API; ensure app registration + $TERMINAL.
#        Terminal.app cannot be fully replaced without invasive hacks.
prefer_wezterm_as_default_terminal() {
  log "registering WezTerm as required default outer terminal (user-local, no sudo)"

  wt=""
  if ! wt="$(wezterm_cli_path)"; then
    warn "wezterm not on PATH — cannot register as default terminal (install binary first)"
    return 0
  fi

  # Shell env: tools that spawn $TERMINAL (scripts, some editors/file managers)
  term_block='export TERMINAL=wezterm
# herdr-bootstrap: WezTerm is the required outer terminal for Herdr/agents'
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$rc" ] || [ "$rc" = "$HOME/.zshrc" ]; then
      append_once "$rc" "# >>> herdr-bootstrap terminal >>>" \
"$term_block
# <<< herdr-bootstrap terminal <<<"
    fi
  done
  export TERMINAL=wezterm

  if [ "$OS" = "darwin" ]; then
    # Prefer user-local app, then system Applications.
    app=""
    for candidate in \
      "$HOME/Applications/WezTerm.app" \
      "/Applications/WezTerm.app"
    do
      if [ -d "$candidate" ]; then
        app="$candidate"
        break
      fi
    done
    if [ -n "$app" ]; then
      lsreg="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
      if [ -x "$lsreg" ] && [ "$DRY_RUN" != 1 ]; then
        "$lsreg" -f "$app" 2>/dev/null || true
        log "registered WezTerm with Launch Services: $app"
      elif [ "$DRY_RUN" = 1 ]; then
        log "[dry-run] would lsregister $app"
      fi
    else
      warn "WezTerm.app not found under ~/Applications or /Applications — open WezTerm once after install"
    fi
    log "macOS has no system default-terminal API; TERMINAL=wezterm set; open WezTerm.app (not Terminal.app) for Herdr"
    return 0
  fi

  # --- Linux ---
  write_wezterm_desktop_entry "$wt"

  # FreeDesktop xdg-terminal-exec preference list (when present on the host)
  xdg_term_list="$HOME/.config/xdg-terminals.list"
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] would prefer org.wezfurlong.wezterm.desktop in $xdg_term_list"
  else
    mkdir -p "$(dirname "$xdg_term_list")"
    if [ ! -f "$xdg_term_list" ] || ! grep -qxF 'org.wezfurlong.wezterm.desktop' "$xdg_term_list" 2>/dev/null; then
      # Prepend so WezTerm wins over other entries already present
      tmp_list="$(mktemp "${TMPDIR:-/tmp}/xdg-terminals.XXXXXX")"
      printf '%s\n' 'org.wezfurlong.wezterm.desktop' >"$tmp_list"
      if [ -f "$xdg_term_list" ]; then
        grep -vxF 'org.wezfurlong.wezterm.desktop' "$xdg_term_list" >>"$tmp_list" || true
      fi
      mv "$tmp_list" "$xdg_term_list"
      log "preferred WezTerm in $xdg_term_list"
    fi
  fi

  # GNOME "Open in Terminal" and default terminal app
  if command -v gsettings >/dev/null 2>&1; then
    if [ "$DRY_RUN" = 1 ]; then
      log "[dry-run] would gsettings terminal exec → $wt"
    else
      gsettings set org.gnome.desktop.default-applications.terminal exec "$wt" 2>/dev/null && \
        log "GNOME default terminal exec → $wt" || true
      gsettings set org.gnome.desktop.default-applications.terminal exec-arg '' 2>/dev/null || true
    fi
  fi

  # KDE (optional; ignore failures)
  if command -v kwriteconfig5 >/dev/null 2>&1 && [ "$DRY_RUN" != 1 ]; then
    kwriteconfig5 --file kdeglobals --group General --key TerminalApplication wezterm 2>/dev/null || true
    kwriteconfig5 --file kdeglobals --group General --key TerminalService org.wezfurlong.wezterm.desktop 2>/dev/null || true
  elif command -v kwriteconfig6 >/dev/null 2>&1 && [ "$DRY_RUN" != 1 ]; then
    kwriteconfig6 --file kdeglobals --group General --key TerminalApplication wezterm 2>/dev/null || true
    kwriteconfig6 --file kdeglobals --group General --key TerminalService org.wezfurlong.wezterm.desktop 2>/dev/null || true
  fi

  # Shadow x-terminal-emulator for user shells (LOCAL_BIN first on PATH). No sudo
  # update-alternatives — print hint if system alternative still wins for absolute paths.
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] would ln -sfn $wt $LOCAL_BIN/x-terminal-emulator"
  else
    mkdir -p "$LOCAL_BIN"
    ln -sfn "$wt" "$LOCAL_BIN/x-terminal-emulator"
    log "linked $LOCAL_BIN/x-terminal-emulator → $wt (user PATH)"
  fi

  log "WezTerm registered as default terminal (Linux user session)"
}

install_wezterm_binary() {
  if command -v wezterm >/dev/null 2>&1; then
    log "wezterm present: $(wezterm --version 2>/dev/null || command -v wezterm)"
    return 0
  fi
  ensure_wezterm_path && command -v wezterm >/dev/null 2>&1 && {
    log "wezterm present after app link: $(wezterm --version 2>/dev/null || true)"
    return 0
  }

  # Package managers (user-local brew preferred)
  if command -v brew >/dev/null 2>&1; then
    log "installing WezTerm via Homebrew"
    if [ "$DRY_RUN" = 1 ]; then
      log "[dry-run] would: brew install wezterm (cask/formula)"
      return 0
    fi
    if [ "$OS" = "darwin" ]; then
      brew install --cask wezterm || warn "brew cask wezterm failed"
    else
      # Linuxbrew: fully-qualified tap/formula (core cask is macOS-only)
      brew tap wezterm/wezterm-linuxbrew 2>/dev/null || true
      brew install wezterm/wezterm-linuxbrew/wezterm || warn "brew wezterm (linux) failed"
    fi
    ensure_wezterm_path || true
    export PATH="$LOCAL_BIN:$PATH"
    if command -v wezterm >/dev/null 2>&1; then
      log "wezterm installed via brew: $(wezterm --version 2>/dev/null || true)"
      return 0
    fi
  fi

  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] would download portable WezTerm for $OS/$ARCH"
    return 0
  fi

  log "installing portable WezTerm (no sudo) for $OS/$ARCH"
  if [ "$OS" = "darwin" ]; then
    install_wezterm_macos_portable || warn "portable macOS WezTerm install failed"
  else
    # Prefer AppImage on x86_64; deb-extract on aarch64 (or AppImage fallback fails).
    case "$ARCH" in
      x86_64|amd64)
        install_wezterm_linux_appimage || install_wezterm_linux_deb_extract || \
          warn "portable Linux WezTerm install failed"
        ;;
      arm64|aarch64)
        install_wezterm_linux_deb_extract || warn "portable Linux aarch64 WezTerm install failed"
        ;;
      *)
        warn "unsupported arch for portable WezTerm: $ARCH — install from https://wezterm.org/"
        ;;
    esac
  fi

  export PATH="$LOCAL_BIN:$PATH"
  if command -v wezterm >/dev/null 2>&1; then
    log "wezterm ready: $(wezterm --version 2>/dev/null || command -v wezterm)"
  else
    warn "wezterm not on PATH after install — see https://wezterm.org/  config will still sync"
  fi
}

sync_wezterm_config() {
  if [ "$SKIP_WEZTERM_CONFIG_SYNC" = 1 ]; then
    log "skip wezterm config sync (--skip-wezterm-config-sync)"
    return 0
  fi
  if [ -z "$BOOTSTRAP_ROOT" ] || [ ! -f "$BOOTSTRAP_ROOT/config/wezterm/wezterm.lua" ]; then
    warn "no config/wezterm/wezterm.lua (run install from herdr-bootstrap clone)"
    return 0
  fi
  sync_bin="$BOOTSTRAP_ROOT/bin/sync-wezterm-config"
  if [ ! -f "$sync_bin" ]; then
    warn "missing bin/sync-wezterm-config"
    return 0
  fi
  log "syncing config/wezterm → ~/.config/wezterm (Herdr-compatible outer terminal)"
  if [ "$DRY_RUN" = 1 ]; then
    python3 "$sync_bin" --dry-run || warn "sync-wezterm-config dry-run failed"
    return 0
  fi
  python3 "$sync_bin" || warn "sync-wezterm-config failed"
}

install_wezterm() {
  if [ "$SKIP_WEZTERM" = 1 ]; then
    log "skip wezterm (--skip-wezterm) — break-glass only; WezTerm is required for Herdr/agents"
    return 0
  fi
  install_wezterm_binary
  sync_wezterm_config
  prefer_wezterm_as_default_terminal
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
  if command -v docs-wiki >/dev/null 2>&1; then
    printf '  OK  docs-wiki CLI\n'
  else
    printf '  MISS docs-wiki CLI (build plugin from monorepo)\n'
  fi
  # LSP triad: must be present, runnable, and wired for Grok
  if rust_analyzer_ok; then
    printf '  OK  rust-analyzer -> %s (%s)\n' "$(command -v rust-analyzer)" "$(rust-analyzer --version 2>/dev/null | head -1)"
  else
    printf '  MISS rust-analyzer (Rust LSP — install/fix broken binary)\n'
    ok=0
  fi
  if command -v gopls >/dev/null 2>&1 && gopls version >/dev/null 2>&1; then
    printf '  OK  gopls -> %s\n' "$(command -v gopls)"
  else
    printf '  MISS gopls (Go LSP)\n'
    ok=0
  fi
  if command -v lua-language-server >/dev/null 2>&1 && lua-language-server --version >/dev/null 2>&1; then
    printf '  OK  lua-language-server -> %s\n' "$(command -v lua-language-server)"
  else
    printf '  MISS lua-language-server (Lua LSP)\n'
    ok=0
  fi
  if [ -f "$HOME/.grok/config.toml" ] && grep -q 'lsp_tools\s*=\s*true' "$HOME/.grok/config.toml" 2>/dev/null; then
    printf '  OK  ~/.grok/config.toml lsp_tools=true\n'
  else
    printf '  MISS ~/.grok lsp_tools (run bin/sync-grok-config)\n'
    ok=0
  fi
  if [ -f "$HOME/.grok/lsp.json" ] && \
     grep -q '"rust"' "$HOME/.grok/lsp.json" 2>/dev/null && \
     grep -q '"go"' "$HOME/.grok/lsp.json" 2>/dev/null && \
     grep -q '"lua"' "$HOME/.grok/lsp.json" 2>/dev/null; then
    printf '  OK  ~/.grok/lsp.json (rust + go + lua)\n'
  else
    printf '  MISS ~/.grok/lsp.json incomplete (sync project .grok/lsp.json)\n'
    ok=0
  fi
  if [ -n "$BOOTSTRAP_ROOT" ] && [ -f "$BOOTSTRAP_ROOT/.grok/lsp.json" ]; then
    if grep -q '"rust"' "$BOOTSTRAP_ROOT/.grok/lsp.json" 2>/dev/null && \
       grep -q '"go"' "$BOOTSTRAP_ROOT/.grok/lsp.json" 2>/dev/null && \
       grep -q '"lua"' "$BOOTSTRAP_ROOT/.grok/lsp.json" 2>/dev/null; then
      printf '  OK  project .grok/lsp.json (rust + go + lua)\n'
    else
      printf '  MISS project .grok/lsp.json incomplete (need rust + go + lua)\n'
      ok=0
    fi
  fi
  if [ -n "$BOOTSTRAP_ROOT" ] && [ -f "$BOOTSTRAP_ROOT/.grok/config.yaml" ]; then
    printf '  OK  project .grok/config.yaml (source of truth)\n'
  fi
  if [ -n "$BOOTSTRAP_ROOT" ] && [ -f "$BOOTSTRAP_ROOT/config/herdr/config.toml" ]; then
    printf '  OK  project config/herdr/config.toml (Herdr global source of truth)\n'
  elif [ -z "$BOOTSTRAP_ROOT" ]; then
    printf '  SKIP project config/herdr (no clone root; curl|sh or non-repo invoke)\n'
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
     grep -q 'jewell.agent-browser' "$HOME/.config/herdr/config.toml" 2>/dev/null; then
    printf '  OK  ~/.config/herdr/config.toml agent-browser keybindings\n'
  else
    printf '  MISS agent-browser keybindings in global config\n'
  fi
  if [ "$SKIP_WEZTERM" = 1 ]; then
    printf '  SKIP wezterm (--skip-wezterm break-glass)\n'
  else
    if command -v wezterm >/dev/null 2>&1; then
      printf '  OK  wezterm -> %s\n' "$(command -v wezterm)"
      wezterm --version 2>/dev/null | sed 's/^/       /' || true
    else
      printf '  MISS wezterm (required outer terminal; re-run without --skip-wezterm)\n'
      ok=0
    fi
    if [ -f "$HOME/.config/wezterm/wezterm.lua" ] && \
       grep -q 'enable_kitty_keyboard' "$HOME/.config/wezterm/wezterm.lua" 2>/dev/null; then
      printf '  OK  ~/.config/wezterm/wezterm.lua (kitty keyboard for Herdr/agents)\n'
    else
      printf '  MISS ~/.config/wezterm (run bin/sync-wezterm-config)\n'
    fi
    if [ -n "$BOOTSTRAP_ROOT" ] && [ -f "$BOOTSTRAP_ROOT/config/wezterm/wezterm.lua" ]; then
      printf '  OK  project config/wezterm/wezterm.lua (source of truth)\n'
    elif [ -z "$BOOTSTRAP_ROOT" ]; then
      printf '  SKIP project config/wezterm (no clone root)\n'
    else
      printf '  MISS project config/wezterm/wezterm.lua\n'
    fi
    # Default-terminal registration (required path)
    if grep -F '# >>> herdr-bootstrap terminal >>>' "$HOME/.zshrc" >/dev/null 2>&1 || \
       grep -F '# >>> herdr-bootstrap terminal >>>' "$HOME/.bashrc" >/dev/null 2>&1; then
      printf '  OK  shell TERMINAL=wezterm (herdr-bootstrap terminal block)\n'
    else
      printf '  MISS shell TERMINAL=wezterm (re-run install_wezterm / install.sh)\n'
    fi
    if [ "$OS" != "darwin" ]; then
      if [ -f "$HOME/.local/share/applications/org.wezfurlong.wezterm.desktop" ]; then
        printf '  OK  Linux desktop entry org.wezfurlong.wezterm.desktop\n'
      else
        printf '  MISS Linux WezTerm .desktop (default terminal registration)\n'
      fi
      if [ -L "$LOCAL_BIN/x-terminal-emulator" ] || [ -x "$LOCAL_BIN/x-terminal-emulator" ]; then
        printf '  OK  %s/x-terminal-emulator → wezterm\n' "$LOCAL_BIN"
      else
        printf '  MISS %s/x-terminal-emulator (user default terminal shadow)\n' "$LOCAL_BIN"
      fi
    fi
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
install_wezterm
install_grok
install_skill
link_skill_native_dirs
install_herdr_plugins
install_rust_analyzer
install_gopls
install_lua_language_server
sync_grok_config
sync_herdr_config
install_integrations
verify

cat <<'EOF'

Bootstrap complete.

Next steps:
  1. Open a new shell (source ~/.zshrc) so TERMINAL=wezterm is active
  2. Open WezTerm (required outer terminal; Herdr-compatible config in ~/.config/wezterm)
     macOS: open WezTerm.app (Terminal.app is not replaced by the OS)
     Linux: desktop entry + GNOME/KDE hooks + x-terminal-emulator shadow are set
  3. If needed: grok login
  4. From WezTerm (not nested inside Herdr):  herdr
  5. Start your agent in a pane (e.g. grok)
  6. First-run walkthrough: https://herdr.dev/agent-guide.md
  7. Project wiki: docs/ + skill docs-wiki; doctor: docs-wiki doctor
  8. Grok config source of truth: .grok/config.yaml → bin/sync-grok-config
  9. Herdr global config: config/herdr/config.toml → bin/sync-herdr-config
 10. WezTerm config: config/wezterm/wezterm.lua → bin/sync-wezterm-config
 11. LSP: .grok/lsp.json (rust-analyzer + gopls + lua-language-server) + lsp_tools in ~/.grok/config.toml

Docs: https://herdr.dev/docs/  |  Plugins: https://herdr.dev/plugins/  |  Blog: https://herdr.dev/blog/
Source: https://github.com/herdrdev/herdr
Wiki rules: docs/ (see docs/index.md)  |  policy/llm-wiki.toml
EOF
