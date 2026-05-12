#!/usr/bin/env bash
# nova-prereq.sh — Nova Cortex prerequisites check + auto-install.
#
# Run before nova-init.sh. Detects OS, installs missing tools.
# Idempotent: safe to re-run; already-installed deps are skipped.
#
# Supported: macOS, Linux (Debian/Ubuntu via apt). Windows users must install
# WSL2 first and run this inside the Linux shell.

set -e

# ─── Branded output helpers ───────────────────────────────────────────────
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

nova_say()  { echo -e "${PURPLE}▸${RESET} $*"; }
nova_ok()   { echo -e "  ${GREEN}✓${RESET} $*"; }
nova_warn() { echo -e "  ${YELLOW}!${RESET} $*"; }
nova_fail() { echo -e "  ${RED}✗${RESET} $*" >&2; exit 1; }
nova_step() { echo ""; echo -e "${CYAN}─── $* ───${RESET}"; }
nova_dim()  { echo -e "    ${DIM}$*${RESET}"; }

# ─── Detect OS ────────────────────────────────────────────────────────────
nova_step "Detecting your system"

OS="unknown"
case "$(uname -s)" in
  Darwin*) OS="mac" ;;
  Linux*)  OS="linux" ;;
  MINGW*|CYGWIN*|MSYS*) OS="windows" ;;
esac

case "$OS" in
  mac)
    nova_ok "macOS detected"
    PKG_INSTALL="brew install"
    ;;
  linux)
    nova_ok "Linux detected"
    if command -v apt-get >/dev/null 2>&1; then
      PKG_INSTALL="sudo apt-get install -y"
    else
      nova_fail "Linux package manager not supported yet. Nova Cortex currently auto-installs only on apt-based Linux (Ubuntu/Debian)."
    fi
    ;;
  windows)
    nova_fail "Nova Cortex does not run natively on Windows. Please install WSL2 (https://learn.microsoft.com/windows/wsl/install) and run this script inside the Linux shell."
    ;;
  *)
    nova_fail "Unknown operating system. Nova Cortex supports macOS and Linux."
    ;;
esac

# ─── Homebrew (macOS only) ────────────────────────────────────────────────
if [[ "$OS" == "mac" ]]; then
  nova_step "Checking Homebrew (macOS package manager)"
  if command -v brew >/dev/null 2>&1; then
    nova_ok "Homebrew already installed ($(brew --version | head -1))"
  else
    nova_say "Homebrew not found. Installing now (this is the foundation tool — takes ~5 minutes)"
    nova_dim "macOS will ask for your password. This is normal — Homebrew needs admin permission."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Ensure brew is on PATH for the rest of this session (Apple Silicon installs to /opt/homebrew)
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
    command -v brew >/dev/null 2>&1 || nova_fail "Homebrew install succeeded but brew is not on PATH. Open a new terminal and re-run this script."
    nova_ok "Homebrew installed"
  fi
fi

# ─── jq (JSON parser used by Nova Cortex + cortextOS shell scripts) ──────────────
nova_step "Checking jq (JSON tool)"
if command -v jq >/dev/null 2>&1; then
  nova_ok "jq already installed ($(jq --version))"
else
  nova_say "Installing jq..."
  $PKG_INSTALL jq
  nova_ok "jq installed"
fi

# ─── Node.js 20+ ──────────────────────────────────────────────────────────
nova_step "Checking Node.js (runtime for Nova Cortex agents)"
node_ok=0
if command -v node >/dev/null 2>&1; then
  NODE_MAJOR=$(node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo "0")
  if [[ "$NODE_MAJOR" -ge 20 ]]; then
    nova_ok "Node.js $(node --version) — meets requirement (>=20)"
    node_ok=1
  else
    nova_warn "Node.js $(node --version) is older than v20 — upgrading"
  fi
fi

if [[ $node_ok -eq 0 ]]; then
  nova_say "Installing Node.js 20+..."
  if [[ "$OS" == "mac" ]]; then
    brew install node@20
    brew link --overwrite node@20 || true
  else
    # Node v20 via NodeSource on apt-based systems
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
  fi
  nova_ok "Node.js installed ($(node --version))"
fi

# ─── Claude Code CLI ──────────────────────────────────────────────────────
nova_step "Checking Claude Code CLI (your AI agents need this to think)"
if command -v claude >/dev/null 2>&1; then
  nova_ok "Claude Code already installed ($(claude --version 2>/dev/null | head -1))"
else
  nova_say "Installing Claude Code CLI..."
  npm install -g @anthropic-ai/claude-code
  nova_ok "Claude Code installed"
  nova_dim "You will need to authenticate with 'claude' (one-time) before agents can talk to Anthropic."
fi

# ─── cortextOS engine ─────────────────────────────────────────────────────
nova_step "Checking cortextOS (the engine Nova Cortex runs on)"
if command -v cortextos >/dev/null 2>&1; then
  nova_ok "cortextOS already installed ($(cortextos --version 2>/dev/null | head -1 || echo 'version unknown'))"
else
  nova_say "Installing cortextOS engine..."
  nova_dim "Powered by cortextOS — open-source multi-agent framework by Cortext LLC (MIT). https://github.com/grandamenium/cortextos"
  curl -fsSL https://raw.githubusercontent.com/grandamenium/cortextos/main/install.mjs | node
  if ! command -v cortextos >/dev/null 2>&1; then
    nova_fail "cortextOS installed but the 'cortextos' command is not on PATH yet. Open a new terminal window and re-run this script."
  fi
  nova_ok "cortextOS engine installed"
fi

# ─── Final summary ────────────────────────────────────────────────────────
echo ""
echo -e "${PURPLE}╭──────────────────────────────────────────╮${RESET}"
echo -e "${PURPLE}│${RESET}  ${BOLD}Nova Cortex toolbox ready${RESET}                      ${PURPLE}│${RESET}"
echo -e "${PURPLE}╰──────────────────────────────────────────╯${RESET}"
echo ""
echo "Versions confirmed:"
echo "  Node.js:        $(node --version)"
echo "  Claude Code:    $(claude --version 2>/dev/null | head -1 || echo 'installed')"
echo "  cortextOS:      $(cortextos --version 2>/dev/null | head -1 || echo 'installed')"
echo "  jq:             $(jq --version)"
echo ""
echo "Next: run ${BOLD}bash nova-init.sh${RESET} to set up your first Nova Cortex agents."
echo ""
