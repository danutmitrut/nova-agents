#!/usr/bin/env bash
# nova-init.sh — Configurează primii tăi agenți Nova Cortex.
#
# Rulează verificarea de prereq, apoi ghidează studentul prin setup-ul Nova Cortex:
#   - Alege un nume de workspace (org)
#   - Alege canalul de control: Telegram sau Slack
#   - Pornește Orchestratorul (Analystul vine online în /onboarding)
#   - Predă către /onboarding în canalul ales
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

# ─── Refuză să ruleze sub WSL2 ───────────────────────────────────────────
# Nova Cortex nu mai suporta WSL2 (cortextOS upstream foloseste PowerShell pe
# Windows nativ — vezi nova-init.ps1). WSL2 introduce probleme de PATH inherit,
# OS keyring, PTY interop care nu au fix curat. Cere user-ului sa foloseasca
# PowerShell nativ pe Windows in loc.
if grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
  echo ""
  echo -e "  ${RED}✗${RESET} Detectez WSL2 (Windows Subsystem for Linux)."
  echo ""
  echo "  Nova Cortex nu mai ruleaza pe WSL2 — sunt prea multe edge case-uri (PATH"
  echo "  inherit din Windows, OS keyring inaccesibil din PTY, etc)."
  echo ""
  echo -e "  ${BOLD}Pe Windows, foloseste varianta nativa PowerShell:${RESET}"
  echo ""
  echo -e "      ${CYAN}# In PowerShell (NU WSL):${RESET}"
  echo -e "      ${CYAN}cd \$HOME${RESET}"
  echo -e "      ${CYAN}git clone https://github.com/danutmitrut/nova-agents.git${RESET}"
  echo -e "      ${CYAN}cd nova-agents${RESET}"
  echo -e "      ${CYAN}.\\nova-init.ps1${RESET}"
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

if [[ -z "${NOVA_AGENT_RUNTIME:-}" ]]; then
  echo -e "${BOLD}Runtime AI:${RESET} Cu ce vrei să ruleze agenții Nova Cortex?"
  nova_dim "Pentru cursul nou recomandat: Codex/OpenAI. Claude rămâne suportat pentru compatibilitate."
  echo "  1) Codex / OpenAI (recomandat)"
  echo "  2) Claude Code"
  read -r -p "  → Alege 1 sau 2 [1]: " RUNTIME_CHOICE
  RUNTIME_CHOICE="${RUNTIME_CHOICE:-1}"
  case "$RUNTIME_CHOICE" in
    1) NOVA_AGENT_RUNTIME="codex" ;;
    2) NOVA_AGENT_RUNTIME="claude" ;;
    *) nova_fail "Alegere invalidă. Reia nova-init.sh și alege 1 sau 2." ;;
  esac
fi
case "$NOVA_AGENT_RUNTIME" in
  codex) CORTEXT_RUNTIME="codex-app-server"; ORCH_TEMPLATE="nova-cortex-orchestrator-codex"; ANALYST_TEMPLATE="nova-cortex-analyst-codex" ;;
  claude) CORTEXT_RUNTIME="claude-code"; ORCH_TEMPLATE="nova-cortex-orchestrator"; ANALYST_TEMPLATE="nova-cortex-analyst" ;;
  *) nova_fail "NOVA_AGENT_RUNTIME trebuie să fie 'codex' sau 'claude'." ;;
esac
nova_ok "Runtime ales: ${BOLD}$NOVA_AGENT_RUNTIME${RESET}"

# ─── Rulează prereq idempotent ───────────────────────────────────────────
nova_say "Întâi ne asigurăm că toolbox-ul tău e gata..."
if [[ -f "$SCRIPT_DIR/nova-prereq.sh" ]]; then
  NOVA_AGENT_RUNTIME="$NOVA_AGENT_RUNTIME" bash "$SCRIPT_DIR/nova-prereq.sh"
else
  nova_fail "nova-prereq.sh nu e lângă acest script. Rulează nova-prereq.sh manual întâi."
fi

# ─── Wizard ───────────────────────────────────────────────────────────────
nova_step "Configurăm workspace-ul tău Nova Cortex"

echo ""
echo -e "${BOLD}Pasul 1 din 3:${RESET} Care e numele tău?"
nova_dim "Folosit ca etichetă pentru workspace-ul tău privat (ex: \"nova-dan\"). Litere mici, fără spații."
read -r -p "  → " NOVA_USER
NOVA_USER=$(echo "$NOVA_USER" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
if [[ -z "$NOVA_USER" ]]; then
  nova_fail "Numele e obligatoriu. Reia nova-init.sh."
fi
ORG="nova-$NOVA_USER"
nova_ok "Nume workspace: ${BOLD}$ORG${RESET}"

echo ""
echo -e "${BOLD}Pasul 2 din 4:${RESET} Unde vrei să controlezi Nova Cortex?"
nova_dim "Telegram este calea clasică. Slack pornește un bridge Socket Mode separat, util pentru echipe și curs."
echo "  1) Telegram"
echo "  2) Slack"
read -r -p "  → Alege 1 sau 2 [1]: " CHANNEL_CHOICE
CHANNEL_CHOICE="${CHANNEL_CHOICE:-1}"
case "$CHANNEL_CHOICE" in
  1) NOVA_CONTROL_CHANNEL="telegram" ;;
  2) NOVA_CONTROL_CHANNEL="slack" ;;
  *) nova_fail "Alegere invalidă. Reia nova-init.sh și alege 1 sau 2." ;;
esac
nova_ok "Canal ales: ${BOLD}$NOVA_CONTROL_CHANNEL${RESET}"

if [[ "$NOVA_CONTROL_CHANNEL" == "telegram" ]]; then
  echo ""
  echo -e "${BOLD}Pasul 3 din 4:${RESET} Tokenul de bot Telegram pentru Nova Cortex Orchestrator"
  nova_dim "Dacă nu ai unul: deschide Telegram, scrie la @BotFather, trimite /newbot, urmează pașii."
  nova_dim "BotFather îți va da un token care arată ca 123456:AAxxxxxxxxxxxx — paste-uiește-l mai jos."
  nova_dim "Vei avea nevoie de un AL DOILEA token mai târziu pentru Analyst — Orchestratorul ți-l va cere în /onboarding."
  read -r -p "  → " BOT_TOKEN
  if [[ -z "$BOT_TOKEN" || ! "$BOT_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
    nova_fail "Acela nu pare un token valid de bot Telegram. Format așteptat: 123456:AAxx... Reia nova-init.sh."
  fi
  nova_ok "Token capturat (se salvează local, nu se share-uiește niciodată)."

  # ─── Pasul 4: Handshake Telegram (capturare CHAT_ID + ALLOWED_USER) ─────
  # cortextOS refuza sa porneasca polling-ul Telegram daca .env nu are
  # CHAT_ID si ALLOWED_USER setate (gate de securitate in agent-manager.ts).
  # Le obtinem automat din /getUpdates dupa ce userul trimite primul mesaj.
  echo ""
  echo -e "${BOLD}Pasul 4 din 4:${RESET} Deschide bot-ul în Telegram"
  nova_dim "Bot-ul tău are deja tokenul. Pe Telegram caută numele lui (cel pe care l-ai dat la BotFather)."
  nova_dim "Trimite-i ${BOLD}/start${RESET}, apoi orice mesaj (ex: \"salut\"). Apoi întoarce-te aici și apasă Enter."
  read -r -p "  → Apasă Enter când ai trimis mesajul... "

  nova_say "Caut mesajul tău în coada bot-ului..."
  # Filtreaza la ultimul update care contine un .message complet (nu callback, edited,
  # channel post, etc) — pe acestea nu putem citi chat/from uniform.
  TG_FILTER='[.result[] | select(.message.chat.id and .message.from.id)] | last | .message'
  TG_UPDATES=$(curl -s --max-time 10 "https://api.telegram.org/bot$BOT_TOKEN/getUpdates" || echo "")
  CHAT_ID=$(echo "$TG_UPDATES" | jq -r "$TG_FILTER.chat.id // empty" 2>/dev/null)
  USER_ID=$(echo "$TG_UPDATES" | jq -r "$TG_FILTER.from.id // empty" 2>/dev/null)

  # Retry o data daca prima incercare a esuat — userul poate intarzia cu mesajul
  if [[ -z "$CHAT_ID" || "$CHAT_ID" == "null" ]]; then
    nova_warn "Nu am gasit mesaj. Verifica ca ai trimis ${BOLD}/start${RESET} și apoi un mesaj PLAIN (nu butoane) la bot."
    read -r -p "  → Reincearca acum (Enter)... "
    TG_UPDATES=$(curl -s --max-time 10 "https://api.telegram.org/bot$BOT_TOKEN/getUpdates" || echo "")
    CHAT_ID=$(echo "$TG_UPDATES" | jq -r "$TG_FILTER.chat.id // empty" 2>/dev/null)
    USER_ID=$(echo "$TG_UPDATES" | jq -r "$TG_FILTER.from.id // empty" 2>/dev/null)
  fi

  if [[ -z "$CHAT_ID" || "$CHAT_ID" == "null" || -z "$USER_ID" || "$USER_ID" == "null" ]]; then
    nova_fail "Tot nu am putut citi mesajul din coada bot-ului. Verifica tokenul si retrimite mesajul. Reia nova-init.sh."
  fi
  nova_ok "Bot conectat (chat ${CHAT_ID})"
else
  echo ""
  echo -e "${BOLD}Pasul 3 din 4:${RESET} Conectare Slack"
  nova_dim "Creează o Slack App cu Socket Mode activ."
  nova_dim "Bot scopes minime: app_mentions:read, channels:history, chat:write, files:read, im:history, im:read."
  nova_dim "Bot events: app_mention, message.channels, message.im. După scope/events: Reinstall to Workspace."
  nova_dim "Ai nevoie de Bot Token (xoxb-...), App Token (xapp-..., scope connections:write) și Channel ID (C...)."
  read -r -p "  → SLACK_BOT_TOKEN: " SLACK_BOT_TOKEN
  read -r -p "  → SLACK_APP_TOKEN: " SLACK_APP_TOKEN
  read -r -p "  → SLACK_CHANNEL_ID pentru canalul dedicat (ex: C123...): " SLACK_CHANNEL_ID
  read -r -p "  → SLACK_ALLOWED_USER opțional (ex: U123..., Enter pentru orice user din workspace): " SLACK_ALLOWED_USER
  if [[ -z "$SLACK_BOT_TOKEN" || ! "$SLACK_BOT_TOKEN" =~ ^xoxb- ]]; then
    nova_fail "SLACK_BOT_TOKEN trebuie să înceapă cu xoxb-. Reia nova-init.sh."
  fi
  if [[ -z "$SLACK_APP_TOKEN" || ! "$SLACK_APP_TOKEN" =~ ^xapp- ]]; then
    nova_fail "SLACK_APP_TOKEN trebuie să înceapă cu xapp-. Reia nova-init.sh."
  fi
  if [[ -z "$SLACK_CHANNEL_ID" || ! "$SLACK_CHANNEL_ID" =~ ^C[A-Z0-9]+$ ]]; then
    nova_fail "SLACK_CHANNEL_ID trebuie să înceapă cu C (ex: C123ABC). Reia nova-init.sh."
  fi
  nova_ok "Token-uri Slack capturate (se salvează local, nu se share-uiesc niciodată)."

  echo ""
  echo -e "${BOLD}Pasul 4 din 4:${RESET} După instalare, vei invita app-ul Slack în canal"
  nova_dim "În Slack: invită app-ul în canalul dedicat și scrie direct /onboarding, fără @."
  nova_dim "Dacă scrii în alt canal, folosește @numele-app-ului; bridge-ul ascultă fără @ doar în canalul dedicat."
fi

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

# `cortextos init` foloseste process.cwd() ca projectRoot (upstream cortextOS,
# init.ts:15). Daca rulam wizard-ul din alt director decat $CORTEXTOS_HOME,
# org-ul ajunge in cwd/orgs/ in loc de ~/cortextos/orgs/, iar daemon-ul nu-l
# vede la `cortextos start`. cd-uim explicit + exportam CTX_FRAMEWORK_ROOT
# (respectat de add-agent.ts) ca sa fortam ambele comenzi sa scrie in locul
# corect, indiferent de unde a fost lansat scriptul.
export CTX_FRAMEWORK_ROOT="$CORTEXTOS_HOME"
cd "$CORTEXTOS_HOME"

nova_say "Creez workspace-ul..."
cortextos init "$ORG" >/dev/null 2>&1 || nova_fail "Nu am putut crea workspace-ul. Rulează 'cortextos doctor' pentru diagnostic."
nova_ok "Workspace \"$ORG\" gata"

nova_say "Pornesc Nova Cortex Orchestrator (chief of staff-ul tău)..."
if [[ "$NOVA_AGENT_RUNTIME" == "codex" ]]; then
  cortextos add-agent boss --template "$ORCH_TEMPLATE" --org "$ORG" --runtime "$CORTEXT_RUNTIME" >/dev/null 2>&1 \
    || nova_fail "Template-ul Orchestrator Codex nu există la $CORTEXTOS_TEMPLATES/$ORCH_TEMPLATE/. Pasul de copiere template-uri probabil a eșuat — re-rulează scriptul."
else
  cortextos add-agent boss --template "$ORCH_TEMPLATE" --org "$ORG" >/dev/null 2>&1 \
    || nova_fail "Template-ul Orchestrator nu există la $CORTEXTOS_TEMPLATES/$ORCH_TEMPLATE/. Pasul de copiere template-uri probabil a eșuat — re-rulează scriptul."
fi
nova_ok "Nova Cortex Orchestrator creat"

cd "$SCRIPT_DIR"

nova_say "Conectez canalul de control pentru Orchestratorul tău..."
AGENT_ENV="$CORTEXTOS_HOME/orgs/$ORG/agents/boss/.env"
if [[ -f "$AGENT_ENV" ]]; then
  upsert_env() {
    local key="$1"
    local value="$2"
    if grep -q "^${key}=" "$AGENT_ENV"; then
      sed "s|^${key}=.*|${key}=${value}|" "$AGENT_ENV" > "$AGENT_ENV.tmp" && mv "$AGENT_ENV.tmp" "$AGENT_ENV"
    else
      echo "${key}=${value}" >> "$AGENT_ENV"
    fi
  }
  upsert_env "NOVA_CONTROL_CHANNEL" "$NOVA_CONTROL_CHANNEL"
  upsert_env "NOVA_AGENT_RUNTIME" "$NOVA_AGENT_RUNTIME"
  upsert_env "NOVA_ANALYST_TEMPLATE" "$ANALYST_TEMPLATE"
  if [[ "$NOVA_CONTROL_CHANNEL" == "telegram" ]]; then
    # Scrie BOT_TOKEN, CHAT_ID, ALLOWED_USER în .env. cortextos refuza sa
    # porneasca polling-ul Telegram fara toate trei (agent-manager.ts:234).
    upsert_env "BOT_TOKEN" "$BOT_TOKEN"
    upsert_env "CHAT_ID" "$CHAT_ID"
    upsert_env "ALLOWED_USER" "$USER_ID"
  else
    upsert_env "NOVA_SLACK_BRIDGE_AGENT" "slack"
  fi
  chmod 600 "$AGENT_ENV"
  nova_ok "Config canal salvată (local, citibilă doar de proprietar)"
else
  nova_warn "Fișierul .env al agentului nu există la calea așteptată — deschide dashboard-ul ca să configurezi canalul manual."
fi

# ─── Pornește Orchestratorul ──────────────────────────────────────────────
# `cortextos start` foloseste process.cwd() ca sa gaseasca dist/daemon.js
# (upstream start.ts:28). Wizard-ul ramane in $CORTEXTOS_HOME din pasul de
# init/add-agent — nu mai cd-uim. Asta porneste daemon-ul via PM2 si
# inregistreaza boss in enabled-agents.json.
nova_step "Pornesc Orchestratorul tău"
cd "$CORTEXTOS_HOME"
nova_say "Pornesc daemon-ul + boss..."
if cortextos start boss >/dev/null 2>&1; then
  nova_ok "Boss e online"
else
  nova_warn "Auto-start a eșuat. Pornește manual: cd ~/cortextos && cortextos start boss"
fi
cd "$SCRIPT_DIR"

if [[ "$NOVA_CONTROL_CHANNEL" == "slack" ]]; then
  nova_step "Pornesc Slack bridge"
  SLACK_BRIDGE_DIR="$SCRIPT_DIR/slack-bridge"
  if [[ ! -d "$SLACK_BRIDGE_DIR" ]]; then
    nova_fail "Slack bridge lipsește de la $SLACK_BRIDGE_DIR — re-clonează repo-ul nova-agents."
  fi

  cat > "$SLACK_BRIDGE_DIR/.env" <<EOF
SLACK_BOT_TOKEN=$SLACK_BOT_TOKEN
SLACK_APP_TOKEN=$SLACK_APP_TOKEN
SLACK_ALLOWED_USER=$SLACK_ALLOWED_USER
SLACK_DEFAULT_CHANNEL=$SLACK_CHANNEL_ID
SLACK_LISTEN_CHANNELS=$SLACK_CHANNEL_ID
SLACK_BRIDGE_STATE=$CORTEXTOS_HOME/slack-bridge-state.json
SLACK_MEDIA_DIR=$CORTEXTOS_HOME/orgs/$ORG/agents/boss/slack-media
SLACK_MAX_FILE_BYTES=104857600
NOVA_TARGET_AGENT=boss
NOVA_BRIDGE_AGENT=slack
CTX_ORG=$ORG
CTX_FRAMEWORK_ROOT=$CORTEXTOS_HOME
CTX_PROJECT_ROOT=$CORTEXTOS_HOME
CTX_INSTANCE_ID=default
EOF
  chmod 600 "$SLACK_BRIDGE_DIR/.env"

  nova_say "Instalez dependințele Slack bridge..."
  (cd "$SLACK_BRIDGE_DIR" && npm install)
  nova_say "Pornesc bridge-ul cu PM2..."
  pm2 delete nova-slack-bridge >/dev/null 2>&1 || true
  (cd "$SLACK_BRIDGE_DIR" && pm2 start npm --name nova-slack-bridge -- start >/dev/null)
  pm2 save >/dev/null 2>&1 || true
  nova_ok "Slack bridge online"
fi

# ─── Ecran final ─────────────────────────────────────────────────────────
echo ""
echo -e "${PURPLE}╭────────────────────────────────────────────────╮${RESET}"
echo -e "${PURPLE}│${RESET}  ${BOLD}Nova Cortex e gata.${RESET}                           ${PURPLE}│${RESET}"
echo -e "${PURPLE}╰────────────────────────────────────────────────╯${RESET}"
echo ""
echo -e "${BOLD}Următorii pași:${RESET}"
echo ""
if [[ "$NOVA_CONTROL_CHANNEL" == "telegram" ]]; then
  echo "  1. Deschide Telegram și găsește botul pe care tocmai l-ai conectat."
  echo "     Trimite-i orice mesaj (ex: \"salut\") ca să-ți rețină chat-ul."
else
  echo "  1. Deschide Slack, invită app-ul în canalul dedicat și scrie direct:"
  echo "     salut"
fi
echo ""
echo "  2. Trimite Orchestratorului această comandă ca să termine setup-ul:"
echo -e "       ${CYAN}/onboarding${RESET}"
echo ""
echo "     Te va ghida prin identitate, program de lucru, reguli de autonomie,"
echo "     apoi te va ajuta să aduci Analystul online."
echo ""
echo "  3. După ce Analystul e online, Orchestratorul tău te poate ajuta să adaugi"
echo "     agenți specialiști (CFO, marketer, ops, research — tu alegi)."
echo ""
echo -e "  ${DIM}Pentru a reporni Orchestratorul oricând: ${CYAN}cd ~/cortextos && cortextos start boss${RESET}"
echo ""
echo -e "  ${DIM}Workspace: $ORG  •  motorul cortextOS rulează local pe această mașină.${RESET}"
echo ""
