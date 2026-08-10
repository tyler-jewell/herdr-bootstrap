#!/usr/bin/env sh
# Herdr machine bootstrap — idempotent install/update of herdr, Node/npx, Grok,
# the herdr agent skill, agent-native skill symlinks (#1874 / PR #1883), and
# Grok integration hooks.
#
# Usage:
#   sh install.sh [--skip-node] [--skip-grok] [--skip-skills] [--skip-integrations] [--dry-run]
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
DRY_RUN=0

NODE_VERSION="${NODE_VERSION:-22.18.0}"
HERDR_INSTALL_DIR="${HERDR_INSTALL_DIR:-$HOME/.local/bin}"
NODE_PREFIX="${NODE_PREFIX:-$HOME/.local/node}"
LOCAL_BIN="${LOCAL_BIN:-$HOME/.local/bin}"
SHARE_HERDR="${SHARE_HERDR:-$HOME/.local/share/herdr}"
APPLY_SKILLS_SYMLINK_WORKAROUND="${APPLY_SKILLS_SYMLINK_WORKAROUND:-1}"

# shellcheck disable=SC2034
for arg in "$@"; do
  case "$arg" in
    --skip-node) SKIP_NODE=1 ;;
    --skip-grok) SKIP_GROK=1 ;;
    --skip-skills) SKIP_SKILLS=1 ;;
    --skip-integrations) SKIP_INTEGRATIONS=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
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
}

# --- #1874 / PR #1883 workaround ---

link_skill_native_dirs() {
  if [ "$APPLY_SKILLS_SYMLINK_WORKAROUND" != 1 ]; then
    log "skip skills symlink workaround (APPLY_SKILLS_SYMLINK_WORKAROUND=0)"
    return 0
  fi

  CANONICAL="$HOME/.agents/skills/herdr"
  if [ ! -d "$CANONICAL" ]; then
    warn "no canonical skill at $CANONICAL; skip native-dir links"
    return 0
  fi

  log "linking agent-native skill dirs → $CANONICAL (skills#1874 / PR#1883 workaround)"

  # Grok is not in skills CLI agent table — always include it.
  # Do not use --agent '*'; only these dirs.
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
      echo "Workaround applied: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "Bug: https://github.com/vercel-labs/skills/issues/1874"
      echo "Fix PR: https://github.com/vercel-labs/skills/pull/1883"
      echo "Canonical: $CANONICAL"
    } >"$note"
  fi

  for dir in "$@"; do
    if [ "$DRY_RUN" = 1 ]; then
      log "[dry-run] would link $dir/herdr"
      continue
    fi
    mkdir -p "$dir"
    if command -v python3 >/dev/null 2>&1; then
      rel="$(python3 -c "import os; print(os.path.relpath('$CANONICAL', '$dir'))")"
    else
      rel="$CANONICAL"
    fi
    # if existing real dir with same SKILL.md, replace with symlink
    target="$dir/herdr"
    if [ -d "$target" ] && [ ! -L "$target" ]; then
      if [ -f "$target/SKILL.md" ] && cmp -s "$target/SKILL.md" "$CANONICAL/SKILL.md" 2>/dev/null; then
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

Docs: https://herdr.dev/docs/  |  Plugins: https://herdr.dev/plugins/  |  Blog: https://herdr.dev/blog/
Source: https://github.com/herdrdev/herdr
EOF
