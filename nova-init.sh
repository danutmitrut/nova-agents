#!/usr/bin/env bash
# nova-init.sh — Configurează primii tăi agenți Nova Cortex.
#
# Rulează verificarea de prereq, apoi ghidează studentul prin setup-ul Nova Cortex:
#   - Alege un nume de workspace (org)
#   - Conectează bot-ul Telegram pentru Nova Cortex Orchestrator
#   - Pornește Orchestratorul (Analystul vine online în /onboarding)
#   - Predă către /onboarding în Telegram
#
# Reflectă install-ul standard cortextOS: Orchestrator întâi, Analyst pornit de
# Orchestrator în timpul onboarding-ului folosind un al doilea token BotFather.
# Agenții specialiști se adaugă mai târziu de către user (cursul Nova Academy te învață cum).
#
# Presupune că cortextOS e instalat (va rula nova-prereq.sh întâi dacă nu).

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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── Refuză să ruleze dintr-un mount Windows sub WSL ──────────────────────
# Căile sub /mnt/c (sau /mnt/<literă>) sunt drive-uri Windows montate în Linux.
# Au permisiuni restricționate și I/O lent — git clone, npm install și state-ul
# cortextOS se strică subtil. Forțează studentul către o cale Linux nativă.
if [[ "$SCRIPT_DIR" =~ ^/mnt/[a-z]/ ]]; then
  echo ""
  echo -e "  ${RED}✗${RESET} Rulezi dintr-un folder montat din Windows:"
  echo -e "      ${DIM}$SCRIPT_DIR${RESET}"
  echo ""
  echo "  Această cale are permisiuni restricționate sub WSL și va eșua în timpul instalării."
  echo "  Rulează din home-ul tău Linux în loc:"
  echo ""
  echo -e "      ${CYAN}cd ~${RESET}"
  echo -e "      ${CYAN}git clone https://github.com/danutmitrut/nova-agents.git${RESET}"
  echo -e "      ${CYAN}cd nova-agents${RESET}"
  echo -e "      ${CYAN}bash nova-init.sh${RESET}"
  echo ""
  exit 1
fi

# ─── Ecran de bun venit ──────────────────────────────────────────────────
clear 2>/dev/null || true
echo -e "${PURPLE}"
cat <<'BANNER'
   ███╗   ██╗ ██████╗ ██╗   ██╗ █████╗      ██████╗ ██████╗ ██████╗ ████████╗███████╗██╗  ██╗
   ████╗  ██║██╔═══██╗██║   ██║██╔══██╗    ██╔════╝██╔═══██╗██╔══██╗╚══██╔══╝██╔════╝╚██╗██╔╝
   ██╔██╗ ██║██║   ██║██║   ██║███████║    ██║     ██║   ██║██████╔╝   ██║   █████╗   ╚███╔╝
   ██║╚██╗██║██║   ██║╚██╗ ██╔╝██╔══██║    ██║     ██║   ██║██╔══██╗   ██║   ██╔══╝   ██╔██╗
   ██║ ╚████║╚██████╔╝ ╚████╔╝ ██║  ██║    ╚██████╗╚██████╔╝██║  ██║   ██║   ███████╗██╔╝ ██╗
   ╚═╝  ╚═══╝ ╚═════╝   ╚═══╝  ╚═╝  ╚═╝     ╚═════╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝
BANNER
echo -e "${RESET}"
echo -e "  ${BOLD}Bun venit în Nova Cortex${RESET}"
echo -e "  ${DIM}Forța de muncă AI multi-agent pentru business-ul tău${RESET}"
echo ""
echo -e "  ${DIM}Powered by cortextOS engine${RESET}"
echo ""

# ─── Rulează prereq dacă cortextOS lipsește ──────────────────────────────
if ! command -v cortextos >/dev/null 2>&1; then
  nova_say "Întâi ne asigurăm că toolbox-ul tău e gata..."
  if [[ -f "$SCRIPT_DIR/nova-prereq.sh" ]]; then
    bash "$SCRIPT_DIR/nova-prereq.sh"
  else
    nova_fail "cortextOS nu e instalat și nova-prereq.sh nu e lângă acest script. Rulează nova-prereq.sh manual întâi."
  fi
fi

# ─── Wizard ───────────────────────────────────────────────────────────────
nova_step "Configurăm workspace-ul tău Nova Cortex"

echo ""
echo -e "${BOLD}Pasul 1 din 2:${RESET} Care e numele tău?"
nova_dim "Folosit ca etichetă pentru workspace-ul tău privat (ex: \"nova-dan\"). Litere mici, fără spații."
read -r -p "  → " NOVA_USER
NOVA_USER=$(echo "$NOVA_USER" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
if [[ -z "$NOVA_USER" ]]; then
  nova_fail "Numele e obligatoriu. Reia nova-init.sh."
fi
ORG="nova-$NOVA_USER"
nova_ok "Nume workspace: ${BOLD}$ORG${RESET}"

echo ""
echo -e "${BOLD}Pasul 2 din 2:${RESET} Tokenul de bot Telegram pentru Nova Cortex Orchestrator"
nova_dim "Dacă nu ai unul: deschide Telegram, scrie la @BotFather, trimite /newbot, urmează pașii."
nova_dim "BotFather îți va da un token care arată ca 123456:AAxxxxxxxxxxxx — paste-uiește-l mai jos."
nova_dim "Vei avea nevoie de un AL DOILEA token mai târziu pentru Analyst — Orchestratorul ți-l va cere în /onboarding."
read -r -p "  → " BOT_TOKEN
if [[ -z "$BOT_TOKEN" || ! "$BOT_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
  nova_fail "Acela nu pare un token valid de bot Telegram. Format așteptat: 123456:AAxx... Reia nova-init.sh."
fi
nova_ok "Token capturat (se salvează local, nu se share-uiește niciodată)."

# ─── Instalează template-urile Nova Cortex în directorul cortextOS ────────
nova_step "Instalez template-urile de agenți Nova Cortex"

# cortextOS caută template-uri în $CTX_FRAMEWORK_ROOT/templates/ — by default $HOME/cortextos/templates/.
CORTEXTOS_HOME="${CORTEXTOS_DIR:-$HOME/cortextos}"
CORTEXTOS_TEMPLATES="$CORTEXTOS_HOME/templates"
if [[ ! -d "$CORTEXTOS_TEMPLATES" ]]; then
  nova_fail "Directorul template-urilor cortextOS nu există la $CORTEXTOS_TEMPLATES — instalarea poate fi incompletă. Rulează 'cortextos doctor'."
fi

NOVA_TEMPLATES_SRC="$SCRIPT_DIR/templates"
if [[ ! -d "$NOVA_TEMPLATES_SRC" ]]; then
  nova_fail "Template-urile Nova Cortex lipsesc de la $NOVA_TEMPLATES_SRC — re-cloneaza repo-ul nova-agents."
fi

# Copiază fiecare template Nova Cortex în directorul cortextOS (suprascrie versiunile vechi la re-rulare).
for tmpl in "$NOVA_TEMPLATES_SRC"/nova-cortex-*; do
  [[ -d "$tmpl" ]] || continue
  TMPL_NAME=$(basename "$tmpl")
  cp -R "$tmpl" "$CORTEXTOS_TEMPLATES/"
  nova_ok "Template instalat: $TMPL_NAME"
done

# ─── Rulează comenzile cortextOS cu narațiune branded ────────────────────
nova_step "Construiesc echipa ta Nova Cortex"

nova_say "Creez workspace-ul..."
cortextos init "$ORG" >/dev/null 2>&1 || nova_fail "Nu am putut crea workspace-ul. Rulează 'cortextos doctor' pentru diagnostic."
nova_ok "Workspace \"$ORG\" gata"

nova_say "Pornesc Nova Cortex Orchestrator (chief of staff-ul tău)..."
cortextos add-agent boss --template nova-cortex-orchestrator --org "$ORG" >/dev/null 2>&1 \
  || nova_fail "Template-ul Orchestrator nu există la $CORTEXTOS_TEMPLATES/nova-cortex-orchestrator/. Pasul de copiere template-uri probabil a eșuat — re-rulează scriptul."
nova_ok "Nova Cortex Orchestrator creat"

nova_say "Conectez Telegram pentru Orchestratorul tău..."
AGENT_ENV="$HOME/cortextos/orgs/$ORG/agents/boss/.env"
if [[ -f "$AGENT_ENV" ]]; then
  # Scrie BOT_TOKEN în fișierul .env al agentului. Folosim temp+mv pentru
  # compatibilitate cross-platform (sed -i e diferit între BSD/macOS și GNU/Linux).
  if grep -q '^BOT_TOKEN=' "$AGENT_ENV"; then
    sed "s|^BOT_TOKEN=.*|BOT_TOKEN=$BOT_TOKEN|" "$AGENT_ENV" > "$AGENT_ENV.tmp" && mv "$AGENT_ENV.tmp" "$AGENT_ENV"
  else
    echo "BOT_TOKEN=$BOT_TOKEN" >> "$AGENT_ENV"
  fi
  chmod 600 "$AGENT_ENV"
  nova_ok "Token Telegram salvat (local, citibil doar de proprietar)"
else
  nova_warn "Fișierul .env al agentului nu există la calea așteptată — deschide dashboard-ul ca să configurezi Telegram manual."
fi

# ─── Ecran final ─────────────────────────────────────────────────────────
echo ""
echo -e "${PURPLE}╭────────────────────────────────────────────────╮${RESET}"
echo -e "${PURPLE}│${RESET}  ${BOLD}Nova Cortex e gata.${RESET}                           ${PURPLE}│${RESET}"
echo -e "${PURPLE}╰────────────────────────────────────────────────╯${RESET}"
echo ""
echo -e "${BOLD}Următorii pași:${RESET}"
echo ""
echo "  1. Pornește Orchestratorul (o singură dată):"
echo -e "       ${CYAN}cortextos start boss${RESET}"
echo ""
echo "  2. Deschide Telegram și găsește botul pe care tocmai l-ai conectat."
echo "     Trimite-i orice mesaj (ex: \"salut\") ca să-ți rețină chat-ul."
echo ""
echo "  3. Trimite Orchestratorului această comandă ca să termine setup-ul:"
echo -e "       ${CYAN}/onboarding${RESET}"
echo ""
echo "     Te va ghida prin identitate, program de lucru, reguli de autonomie,"
echo "     apoi îți va cere un AL DOILEA token BotFather ca să aducă Analystul online."
echo ""
echo "  4. După ce Analystul e online, Orchestratorul tău te poate ajuta să adaugi"
echo "     agenți specialiști (CFO, marketer, ops, research — tu alegi)."
echo ""
echo -e "  ${DIM}Workspace: $ORG  •  motorul cortextOS rulează local pe această mașină.${RESET}"
echo ""
