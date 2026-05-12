#!/usr/bin/env bash
# nova-init.sh — Set up your first Nova Cortex agents.
#
# Runs the prereq check, then guides the student through Nova Cortex setup:
#   - Picks a workspace name (org)
#   - Wires the Telegram bot for the Nova Cortex Orchestrator
#   - Spawns the Orchestrator (the Analyst comes online during /onboarding)
#   - Hands off to /onboarding inside Telegram
#
# Mirrors the stock cortextOS install: Orchestrator first, Analyst spawned by the
# Orchestrator during onboarding using a second BotFather token. Specialist agents
# are added later by the user (Nova Academy course teaches how).
#
# Assumes cortextOS is installed (will run nova-prereq.sh first if not).

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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── Welcome screen ───────────────────────────────────────────────────────
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
echo -e "  ${BOLD}Welcome to Nova Cortex${RESET}"
echo -e "  ${DIM}Multi-agent AI workforce for your business${RESET}"
echo ""
echo -e "  ${DIM}Powered by cortextOS engine (https://github.com/grandamenium/cortextos)${RESET}"
echo ""

# ─── Run prereq check if cortextOS is missing ────────────────────────────
if ! command -v cortextos >/dev/null 2>&1; then
  nova_say "First, let's make sure your toolbox is ready..."
  if [[ -f "$SCRIPT_DIR/nova-prereq.sh" ]]; then
    bash "$SCRIPT_DIR/nova-prereq.sh"
  else
    nova_fail "cortextOS is not installed and nova-prereq.sh is not next to this script. Run nova-prereq.sh manually first."
  fi
fi

# ─── Wizard ───────────────────────────────────────────────────────────────
nova_step "Setting up your Nova Cortex workspace"

echo ""
echo -e "${BOLD}Step 1 of 2:${RESET} What's your name?"
nova_dim "Used to label your private workspace (e.g. \"nova-dan\"). Lowercase, no spaces."
read -r -p "  → " NOVA_USER
NOVA_USER=$(echo "$NOVA_USER" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
if [[ -z "$NOVA_USER" ]]; then
  nova_fail "A name is required. Please re-run nova-init.sh."
fi
ORG="nova-$NOVA_USER"
nova_ok "Workspace name: ${BOLD}$ORG${RESET}"

echo ""
echo -e "${BOLD}Step 2 of 2:${RESET} Your Telegram bot token for the Nova Cortex Orchestrator"
nova_dim "If you don't have one: open Telegram, message @BotFather, send /newbot, follow prompts."
nova_dim "BotFather will give you a token that looks like 123456:AAxxxxxxxxxxxx — paste it below."
nova_dim "You'll need a SECOND token later for the Analyst — the Orchestrator will ask for it during /onboarding."
read -r -p "  → " BOT_TOKEN
if [[ -z "$BOT_TOKEN" || ! "$BOT_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
  nova_fail "That doesn't look like a valid Telegram bot token. Format should be: 123456:AAxx... Re-run nova-init.sh."
fi
nova_ok "Bot token captured (will be saved locally, never shared)."

# ─── Install Nova Cortex templates into cortextOS templates dir ───────────
nova_step "Installing Nova Cortex agent templates"

# cortextOS looks for templates in $CTX_FRAMEWORK_ROOT/templates/ — by default that's $HOME/cortextos/templates/.
CORTEXTOS_HOME="${CORTEXTOS_DIR:-$HOME/cortextos}"
CORTEXTOS_TEMPLATES="$CORTEXTOS_HOME/templates"
if [[ ! -d "$CORTEXTOS_TEMPLATES" ]]; then
  nova_fail "cortextOS templates directory not found at $CORTEXTOS_TEMPLATES — install may be incomplete. Run 'cortextos doctor'."
fi

NOVA_TEMPLATES_SRC="$SCRIPT_DIR/templates"
if [[ ! -d "$NOVA_TEMPLATES_SRC" ]]; then
  nova_fail "Nova Cortex templates not found at $NOVA_TEMPLATES_SRC — re-clone the nova-agents repo."
fi

# Copy each Nova Cortex template into cortextOS templates dir (overwrites old versions on re-run).
for tmpl in "$NOVA_TEMPLATES_SRC"/nova-cortex-*; do
  [[ -d "$tmpl" ]] || continue
  TMPL_NAME=$(basename "$tmpl")
  cp -R "$tmpl" "$CORTEXTOS_TEMPLATES/"
  nova_ok "Installed template: $TMPL_NAME"
done

# ─── Run cortextOS commands with branded narration ────────────────────────
nova_step "Building your Nova Cortex team"

nova_say "Creating workspace..."
cortextos init "$ORG" >/dev/null 2>&1 || nova_fail "Could not create workspace. Run 'cortextos doctor' to diagnose."
nova_ok "Workspace \"$ORG\" ready"

nova_say "Spawning Nova Cortex Orchestrator (your chief of staff)..."
cortextos add-agent boss --template nova-cortex-orchestrator --org "$ORG" >/dev/null 2>&1 \
  || nova_fail "Orchestrator template not found at $CORTEXTOS_TEMPLATES/nova-cortex-orchestrator/. Templates copy step may have failed — re-run the script."
nova_ok "Nova Cortex Orchestrator created"

nova_say "Wiring Telegram for your Orchestrator..."
AGENT_ENV="$HOME/cortextos/orgs/$ORG/agents/boss/.env"
if [[ -f "$AGENT_ENV" ]]; then
  # Write BOT_TOKEN into the agent's env file (chmod 600 protects it).
  if grep -q '^BOT_TOKEN=' "$AGENT_ENV"; then
    sed -i '' "s|^BOT_TOKEN=.*|BOT_TOKEN=$BOT_TOKEN|" "$AGENT_ENV"
  else
    echo "BOT_TOKEN=$BOT_TOKEN" >> "$AGENT_ENV"
  fi
  chmod 600 "$AGENT_ENV"
  nova_ok "Telegram token saved (locally, owner-readable only)"
else
  nova_warn "Agent .env file not found at expected path — open the dashboard to wire Telegram manually."
fi

# ─── Final screen ────────────────────────────────────────────────────────
echo ""
echo -e "${PURPLE}╭────────────────────────────────────────────────╮${RESET}"
echo -e "${PURPLE}│${RESET}  ${BOLD}Nova Cortex is ready.${RESET}                         ${PURPLE}│${RESET}"
echo -e "${PURPLE}╰────────────────────────────────────────────────╯${RESET}"
echo ""
echo -e "${BOLD}Next steps:${RESET}"
echo ""
echo "  1. Start your Orchestrator (one-time):"
echo -e "       ${CYAN}cortextos start boss${RESET}"
echo ""
echo "  2. Open Telegram and find the bot you just connected."
echo "     Send it any message (e.g. \"hello\") so it learns your chat."
echo ""
echo "  3. Send your Orchestrator this command to complete setup:"
echo -e "       ${CYAN}/onboarding${RESET}"
echo ""
echo "     It will walk you through identity, working hours, autonomy rules,"
echo "     then ask you for a SECOND BotFather token to bring the Analyst online."
echo ""
echo "  4. After the Analyst is online, your Orchestrator can help you add"
echo "     specialist agents (CFO, marketer, ops, research — your call)."
echo ""
echo -e "  ${DIM}Workspace: $ORG  •  cortextOS engine running locally on this machine.${RESET}"
echo ""
