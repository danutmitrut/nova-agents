#!/usr/bin/env bash
# nova-prereq.sh — Verificare prerequisites Nova Cortex + auto-install.
#
# Rulează înainte de nova-init.sh. Detectează OS, instalează tool-urile lipsă.
# Idempotent: safe de rerulat; dependențele deja instalate sunt sărite.
#
# Suportat: macOS, Linux (Debian/Ubuntu via apt). Userii Windows trebuie să
# instaleze WSL2 întâi și să ruleze acest script în shell-ul Linux.

set -e

# ─── Helper-i de output branded ───────────────────────────────────────────
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

# ─── Detectează OS ────────────────────────────────────────────────────────
nova_step "Detectez sistemul tău"

OS="unknown"
case "$(uname -s)" in
  Darwin*) OS="mac" ;;
  Linux*)  OS="linux" ;;
  MINGW*|CYGWIN*|MSYS*) OS="windows" ;;
esac

case "$OS" in
  mac)
    nova_ok "macOS detectat"
    PKG_INSTALL="brew install"
    ;;
  linux)
    nova_ok "Linux detectat"
    if command -v apt-get >/dev/null 2>&1; then
      PKG_INSTALL="sudo apt-get install -y"
    else
      nova_fail "Package manager Linux nu e încă suportat. Nova Cortex auto-instalează deocamdată doar pe Linux apt-based (Ubuntu/Debian)."
    fi
    ;;
  windows)
    nova_fail "Nova Cortex nu rulează nativ pe Windows. Instalează WSL2 (https://learn.microsoft.com/windows/wsl/install) și rulează acest script în shell-ul Linux."
    ;;
  *)
    nova_fail "Sistem de operare necunoscut. Nova Cortex suportă macOS și Linux."
    ;;
esac

# ─── Homebrew (doar macOS) ────────────────────────────────────────────────
if [[ "$OS" == "mac" ]]; then
  nova_step "Verific Homebrew (package manager pentru macOS)"
  if command -v brew >/dev/null 2>&1; then
    nova_ok "Homebrew deja instalat ($(brew --version | head -1))"
  else
    nova_say "Homebrew nu există. Îl instalez acum (tool de bază — ~5 minute)"
    nova_dim "macOS îți va cere parola. E normal — Homebrew are nevoie de permisiuni admin."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Asigură că brew e pe PATH în restul sesiunii (Apple Silicon: /opt/homebrew)
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
    command -v brew >/dev/null 2>&1 || nova_fail "Instalarea Homebrew a reușit dar brew nu e pe PATH. Deschide un terminal nou și rulează din nou acest script."
    nova_ok "Homebrew instalat"
  fi
fi

# ─── jq (parser JSON folosit de Nova Cortex + cortextOS shell scripts) ────
nova_step "Verific jq (tool JSON)"
if command -v jq >/dev/null 2>&1; then
  nova_ok "jq deja instalat ($(jq --version))"
else
  nova_say "Instalez jq..."
  $PKG_INSTALL jq
  nova_ok "jq instalat"
fi

# ─── Node.js 20+ ──────────────────────────────────────────────────────────
nova_step "Verific Node.js (runtime pentru agenții Nova Cortex)"
node_ok=0
if command -v node >/dev/null 2>&1; then
  NODE_MAJOR=$(node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo "0")
  if [[ "$NODE_MAJOR" -ge 20 ]]; then
    nova_ok "Node.js $(node --version) — îndeplinește cerința (>=20)"
    node_ok=1
  else
    nova_warn "Node.js $(node --version) e mai vechi decât v20 — fac upgrade"
  fi
fi

if [[ $node_ok -eq 0 ]]; then
  nova_say "Instalez Node.js 20+..."
  if [[ "$OS" == "mac" ]]; then
    brew install node@20
    brew link --overwrite node@20 || true
  else
    # Node v20 via NodeSource pe sisteme apt-based
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
  fi
  nova_ok "Node.js instalat ($(node --version))"
fi

# ─── Claude Code CLI ──────────────────────────────────────────────────────
nova_step "Verific Claude Code CLI (agenții AI au nevoie ca să gândească)"
if command -v claude >/dev/null 2>&1; then
  nova_ok "Claude Code deja instalat ($(claude --version 2>/dev/null | head -1))"
else
  nova_say "Instalez Claude Code CLI..."
  npm install -g @anthropic-ai/claude-code
  nova_ok "Claude Code instalat"
  nova_dim "Va trebui să te autentifici cu 'claude' (o singură dată) înainte ca agenții să vorbească cu Anthropic."
fi

# ─── cortextOS engine ─────────────────────────────────────────────────────
nova_step "Verific cortextOS (motorul pe care rulează Nova Cortex)"
if command -v cortextos >/dev/null 2>&1; then
  nova_ok "cortextOS deja instalat ($(cortextos --version 2>/dev/null | head -1 || echo 'versiune necunoscută'))"
else
  nova_say "Instalez motorul cortextOS..."
  nova_dim "Powered by cortextOS — framework open-source multi-agent de la Cortext LLC (MIT)."
  curl -fsSL https://raw.githubusercontent.com/grandamenium/cortextos/main/install.mjs | node

  # cortextOS install.mjs face `npm link` fără sudo. Pe Node instalat via apt unde
  # npm prefix=/usr (scrie cere root), link-ul eșuează silent și `cortextos` nu
  # ajunge pe PATH. Detectează cazul ăsta și re-rulează cu sudo ca studenții să
  # nu cadă din wizard.
  if ! command -v cortextos >/dev/null 2>&1; then
    nova_warn "cortextOS instalat dar 'cortextos' nu e încă pe PATH."
    nova_dim "Cauză probabilă: npm link are nevoie de sudo când npm prefix=/usr."
    CORTEXTOS_DIR="${CORTEXTOS_DIR:-$HOME/cortextos}"
    if [[ -d "$CORTEXTOS_DIR" ]]; then
      nova_say "Re-link cu sudo (s-ar putea să-ți ceară parola Linux)..."
      (cd "$CORTEXTOS_DIR" && sudo npm link)
      # `sudo npm link` poate scrie symlink-ul mid-shell; verifică direct și
      # via command -v, pentru că command -v cache-uiește.
      hash -r 2>/dev/null || true
      if ! command -v cortextos >/dev/null 2>&1; then
        nova_fail "cortextos tot lipsește de pe PATH după sudo npm link. Deschide un terminal nou și re-rulează; dacă tot eșuează, rulează manual: cd $CORTEXTOS_DIR && sudo npm link"
      fi
    else
      nova_fail "Directorul de instalare cortextOS nu există la $CORTEXTOS_DIR. Re-rulează install-ul cortextOS: curl -fsSL https://raw.githubusercontent.com/grandamenium/cortextos/main/install.mjs | node"
    fi
  fi
  nova_ok "Motorul cortextOS instalat și linkat"
fi

# ─── PM2 (manager de proces pentru daemon — cortextOS depinde de el) ──────
# cortextOS install.mjs încearcă să instaleze PM2 via `npm install -g pm2` fără
# sudo. Aceeași eroare EACCES ca npm link când npm prefix=/usr. Fără PM2,
# `cortextos start <agent>` nu poate porni daemon-ul, deci sistemul nu intră
# în online. Auto-instalează cu sudo dacă lipsește.
nova_step "Verific PM2 (manager de proces pentru daemon)"
if command -v pm2 >/dev/null 2>&1; then
  nova_ok "PM2 deja instalat ($(pm2 --version 2>/dev/null | head -1))"
else
  nova_say "PM2 lipsește — îl instalez global cu sudo..."
  nova_dim "PM2 ține agenții tăi vii 24/7. S-ar putea să-ți ceară parola Linux."
  sudo npm install -g pm2
  hash -r 2>/dev/null || true
  if ! command -v pm2 >/dev/null 2>&1; then
    nova_fail "Instalarea PM2 cu sudo a eșuat. Rulează manual: sudo npm install -g pm2"
  fi
  nova_ok "PM2 instalat ($(pm2 --version 2>/dev/null | head -1))"
fi

# ─── Python venv (Knowledge Base RAG depinde de el) ───────────────────────
# cortextOS bootstraps un venv Python în install.mjs pentru ChromaDB / RAG. Pe
# Debian/Ubuntu, modulul venv vine ca pachet apt separat (python3-venv sau
# python<MAJOR.MINOR>-venv). Dacă lipsește, ingestion-ul + query-ul KB sunt
# stricate — dar agenții în sine tot rulează. Best-effort install; nu eșuează
# tot wizard-ul dacă apt nu are pachetul potrivit.
if [[ "$OS" == "linux" ]]; then
  nova_step "Verific Python venv (dependență Knowledge Base)"
  if python3 -m venv --help >/dev/null 2>&1; then
    nova_ok "Modulul python3 venv disponibil"
  else
    PY_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || echo "")
    nova_say "Modulul python3 venv lipsește — instalez pachetul apt..."
    if [[ -n "$PY_VERSION" ]]; then
      sudo apt-get install -y "python${PY_VERSION}-venv" 2>/dev/null \
        || sudo apt-get install -y python3-venv 2>/dev/null \
        || nova_warn "Nu am putut instala python venv via apt. Knowledge Base (RAG) va fi dezactivat până se repară."
    else
      sudo apt-get install -y python3-venv 2>/dev/null \
        || nova_warn "Nu am putut instala python3-venv via apt. Knowledge Base (RAG) va fi dezactivat până se repară."
    fi
    python3 -m venv --help >/dev/null 2>&1 && nova_ok "Modulul python3 venv acum disponibil" \
      || nova_warn "Python venv tot lipsește — KB va fi dezactivat până când 'sudo apt install python3-venv' reușește."
  fi
fi

# ─── Sumar final ──────────────────────────────────────────────────────────
echo ""
echo -e "${PURPLE}╭──────────────────────────────────────────╮${RESET}"
echo -e "${PURPLE}│${RESET}  ${BOLD}Toolbox Nova Cortex gata${RESET}                      ${PURPLE}│${RESET}"
echo -e "${PURPLE}╰──────────────────────────────────────────╯${RESET}"
echo ""
echo "Versiuni confirmate:"
echo "  Node.js:        $(node --version)"
echo "  Claude Code:    $(claude --version 2>/dev/null | head -1 || echo 'instalat')"
echo "  cortextOS:      $(cortextos --version 2>/dev/null | head -1 || echo 'instalat')"
echo "  PM2:            $(pm2 --version 2>/dev/null | head -1 || echo 'instalat')"
echo "  jq:             $(jq --version)"
echo ""
echo "Următor: rulează ${BOLD}bash nova-init.sh${RESET} ca să configurezi primii agenți Nova Cortex."
echo ""
