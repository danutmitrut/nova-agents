#!/usr/bin/env bash
# nova-runtime-switch.sh — switch an existing Nova Cortex agent between Claude and Codex.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/nova-runtime-switch.sh --org <org> --agent <agent> --to <codex|claude> [--dry-run] [--yes] [--detach]

Examples:
  scripts/nova-runtime-switch.sh --org nova-danut --agent boss --to codex --dry-run
  scripts/nova-runtime-switch.sh --org nova-danut --agent boss --to claude --yes
  scripts/nova-runtime-switch.sh --org nova-danut --agent boss --to claude --yes --detach

What it preserves:
  .env, USER.md, IDENTITY.md, MEMORY.md, GOALS.md, HEARTBEAT.md, goals.json,
  SOUL.md, GUARDRAILS.md, SYSTEM.md

What it replaces from the target runtime template:
  AGENTS.md, TOOLS.md, ONBOARDING.md, runtime-specific plugin/skill folders,
  CLAUDE.md for Claude, and config runtime fields.
EOF
}

ORG=""
AGENT=""
TARGET=""
DRY_RUN=0
YES=0
DETACH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org) ORG="${2:-}"; shift 2 ;;
    --agent) AGENT="${2:-}"; shift 2 ;;
    --to) TARGET="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes|-y) YES=1; shift ;;
    --detach) DETACH=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$ORG" || -z "$AGENT" || -z "$TARGET" ]]; then
  echo "Missing --org, --agent, or --to." >&2
  usage
  exit 2
fi

if [[ "$DRY_RUN" -eq 0 && "$DETACH" -eq 0 && "${NOVA_RUNTIME_SWITCH_DETACHED:-}" != "1" ]]; then
  if [[ "${CTX_AGENT_NAME:-}" == "$AGENT" && "${CTX_ORG:-}" == "$ORG" ]]; then
    echo "Refusing self-switch without --detach. Re-run with --detach so the restart can finish after this agent stops." >&2
    exit 1
  fi
fi

case "$TARGET" in
  codex)
    TARGET_RUNTIME="codex-app-server"
    TARGET_AGENT_RUNTIME="codex"
    TARGET_MODEL="gpt-5-codex"
    ;;
  claude)
    TARGET_RUNTIME="claude-code"
    TARGET_AGENT_RUNTIME="claude"
    TARGET_MODEL=""
    ;;
  *)
    echo "--to must be codex or claude." >&2
    exit 2
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CORTEXTOS_HOME="${CORTEXTOS_HOME:-$HOME/cortextos}"
AGENT_DIR="$CORTEXTOS_HOME/orgs/$ORG/agents/$AGENT"
STATE_DIR="${CTX_ROOT:-$HOME/.cortextos/default}/state/$AGENT"

if [[ ! -d "$AGENT_DIR" ]]; then
  echo "Agent not found: $AGENT_DIR" >&2
  exit 1
fi

env_value() {
  local file="$1"
  local key="$2"
  if [[ -f "$file" ]]; then
    awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file"
  fi
}

require_env() {
  local key="$1"
  local value
  value="$(env_value "$AGENT_DIR/.env" "$key")"
  if [[ -z "$value" ]]; then
    echo "Missing required $key in $AGENT_DIR/.env" >&2
    exit 1
  fi
}

preflight() {
  command -v node >/dev/null 2>&1 || { echo "Missing node; cannot edit config.json safely." >&2; exit 1; }
  command -v cortextos >/dev/null 2>&1 || echo "warning: cortextos command not found; switch can edit files but cannot restart automatically" >&2

  if [[ "$TARGET" == "codex" ]]; then
    command -v codex >/dev/null 2>&1 || { echo "Missing codex CLI. Run nova-prereq for Codex or install/authenticate Codex first." >&2; exit 1; }
    if [[ -z "${OPENAI_API_KEY:-}" && ! -f "$HOME/.codex/auth.json" ]]; then
      echo "warning: Codex CLI exists, but no OPENAI_API_KEY or ~/.codex/auth.json was detected. Run 'codex' once to authenticate before switching." >&2
    fi
  else
    command -v claude >/dev/null 2>&1 || { echo "Missing claude CLI. Run nova-prereq for Claude or install/authenticate Claude Code first." >&2; exit 1; }
  fi

  channel="$(env_value "$AGENT_DIR/.env" NOVA_CONTROL_CHANNEL)"
  case "$channel" in
    telegram)
      require_env BOT_TOKEN
      require_env CHAT_ID
      require_env ALLOWED_USER
      ;;
    slack)
      require_env SLACK_BOT_TOKEN
      require_env SLACK_APP_TOKEN
      require_env SLACK_CHANNEL_ID
      require_env SLACK_ALLOWED_USER
      ;;
    *)
      echo "Missing or unknown NOVA_CONTROL_CHANNEL in $AGENT_DIR/.env" >&2
      exit 1
      ;;
  esac
}

preflight

if [[ "$AGENT" == "boss" || "$AGENT" == "orchestrator" ]]; then
  if [[ "$TARGET" == "codex" ]]; then
    TEMPLATE="$REPO_DIR/templates/nova-cortex-orchestrator-codex"
    TEMPLATE_NAME="nova-cortex-orchestrator-codex"
  else
    TEMPLATE="$REPO_DIR/templates/nova-cortex-orchestrator"
    TEMPLATE_NAME="nova-cortex-orchestrator"
  fi
else
  if [[ "$TARGET" == "codex" ]]; then
    TEMPLATE="$REPO_DIR/templates/nova-cortex-analyst-codex"
    TEMPLATE_NAME="nova-cortex-analyst-codex"
  else
    TEMPLATE="$REPO_DIR/templates/nova-cortex-analyst"
    TEMPLATE_NAME="nova-cortex-analyst"
  fi
fi

if [[ ! -d "$TEMPLATE" ]]; then
  echo "Template not found: $TEMPLATE" >&2
  exit 1
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
run_id="$timestamp-$$"
backup_dir="$AGENT_DIR/.nova-backups/runtime-switch-$run_id"
handoff_dir="$AGENT_DIR/memory/handoffs"
handoff_file="$handoff_dir/runtime-switch-$run_id.md"

current_runtime="$(node -e 'const fs=require("fs"); const p=process.argv[1]; const j=JSON.parse(fs.readFileSync(p,"utf8")); console.log(j.runtime||"")' "$AGENT_DIR/config.json" 2>/dev/null || true)"

if [[ "$DETACH" -eq 1 && "$DRY_RUN" -eq 0 ]]; then
  if [[ "${NOVA_RUNTIME_SWITCH_DETACHED:-}" != "1" ]]; then
    log_dir="${TMPDIR:-/tmp}/nova-runtime-switch"
    mkdir -p "$log_dir"
    detached_ts="$(date -u +%Y%m%dT%H%M%SZ)"
    log_file="$log_dir/${ORG}-${AGENT}-${detached_ts}.log"
    status_file="$log_dir/${ORG}-${AGENT}-${detached_ts}.status"
    : > "$log_file"
    cat > "$status_file" <<EOF
status=queued
org=$ORG
agent=$AGENT
target=$TARGET
log=$log_file
created_at=$detached_ts
EOF
    (
      sleep 3
      {
        echo "status=running"
        echo "org=$ORG"
        echo "agent=$AGENT"
        echo "target=$TARGET"
        echo "log=$log_file"
        echo "started_at=$(date -u +%Y%m%dT%H%M%SZ)"
      } > "$status_file"
      if NOVA_RUNTIME_SWITCH_DETACHED=1 NOVA_RUNTIME_SWITCH_STATUS_FILE="$status_file" bash "$0" --org "$ORG" --agent "$AGENT" --to "$TARGET" --yes >"$log_file" 2>&1; then
        {
          echo "status=complete"
          echo "org=$ORG"
          echo "agent=$AGENT"
          echo "target=$TARGET"
          echo "log=$log_file"
          echo "completed_at=$(date -u +%Y%m%dT%H%M%SZ)"
        } > "$status_file"
      else
        rc=$?
        {
          echo "status=failed"
          echo "org=$ORG"
          echo "agent=$AGENT"
          echo "target=$TARGET"
          echo "exit_code=$rc"
          echo "log=$log_file"
          echo "failed_at=$(date -u +%Y%m%dT%H%M%SZ)"
        } > "$status_file"
        exit "$rc"
      fi
    ) </dev/null >/dev/null 2>&1 &
    detached_pid=$!
    echo "Preflight passed. Detached runtime switch queued."
    echo "PID: $detached_pid"
    echo "Log: $log_file"
    echo "Status: $status_file"
    disown 2>/dev/null || true
    exit 0
  fi
fi

echo "Nova Runtime Switch"
echo "Org: $ORG"
echo "Agent: $AGENT"
echo "Current runtime: ${current_runtime:-unknown}"
echo "Target runtime: $TARGET_RUNTIME"
echo "Template: $TEMPLATE_NAME"
echo "Agent dir: $AGENT_DIR"
echo "Backup dir: $backup_dir"
echo "State dir: $STATE_DIR"
echo ""

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Dry run only. No files will be changed."
  echo ""
fi

if [[ "$DRY_RUN" -eq 0 && "$YES" -eq 0 ]]; then
  read -r -p "Continue with runtime switch? Type 'switch' to continue: " confirm
  if [[ "$confirm" != "switch" ]]; then
    echo "Aborted."
    exit 0
  fi
fi

run() {
  echo "+ $*"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    "$@"
  fi
}

run_cortextos() {
  echo "+ (cd $CORTEXTOS_HOME && $*)"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    (cd "$CORTEXTOS_HOME" && "$@")
  fi
}

copy_if_exists() {
  local source="$1"
  local destination="$2"
  if [[ -e "$source" ]]; then
    run cp -R "$source" "$destination"
  fi
}

if [[ "$DRY_RUN" -eq 0 ]]; then
  mkdir -p "$backup_dir" "$handoff_dir"
  cat > "$handoff_file" <<EOF
# Runtime switch handoff

- Time: $timestamp
- Org: $ORG
- Agent: $AGENT
- From runtime: ${current_runtime:-unknown}
- To runtime: $TARGET_RUNTIME
- Template: $TEMPLATE_NAME

This file marks an intentional runtime fallback/switch. Memory and channel
configuration are preserved; the interactive runtime session is restarted fresh.
EOF
fi

run cp -R "$AGENT_DIR/config.json" "$backup_dir/config.json"
copy_if_exists "$AGENT_DIR/.env" "$backup_dir/.env"
copy_if_exists "$AGENT_DIR/AGENTS.md" "$backup_dir/AGENTS.md"
copy_if_exists "$AGENT_DIR/CLAUDE.md" "$backup_dir/CLAUDE.md"
copy_if_exists "$AGENT_DIR/TOOLS.md" "$backup_dir/TOOLS.md"
copy_if_exists "$AGENT_DIR/ONBOARDING.md" "$backup_dir/ONBOARDING.md"
copy_if_exists "$AGENT_DIR/SOUL.md" "$backup_dir/SOUL.md"
copy_if_exists "$AGENT_DIR/SYSTEM.md" "$backup_dir/SYSTEM.md"
copy_if_exists "$AGENT_DIR/GUARDRAILS.md" "$backup_dir/GUARDRAILS.md"
copy_if_exists "$AGENT_DIR/plugins" "$backup_dir/plugins"

if command -v cortextos >/dev/null 2>&1; then
  echo "+ (cd $CORTEXTOS_HOME && cortextos stop $AGENT)"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    (cd "$CORTEXTOS_HOME" && cortextos stop "$AGENT" >/dev/null 2>&1) || true
  fi
else
  echo "warning: cortextos command not found; cannot stop/start agent automatically"
fi

for item in AGENTS.md TOOLS.md ONBOARDING.md; do
  if [[ -f "$TEMPLATE/$item" ]]; then
    run cp "$TEMPLATE/$item" "$AGENT_DIR/$item"
  fi
done

if [[ "$TARGET" == "claude" ]]; then
  copy_if_exists "$TEMPLATE/CLAUDE.md" "$AGENT_DIR/CLAUDE.md"
  if [[ "$DRY_RUN" -eq 0 ]]; then rm -rf "$AGENT_DIR/plugins"; fi
else
  if [[ "$DRY_RUN" -eq 0 ]]; then rm -f "$AGENT_DIR/CLAUDE.md"; fi
  copy_if_exists "$TEMPLATE/plugins" "$AGENT_DIR/plugins"
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
  node - "$AGENT_DIR/config.json" "$TEMPLATE/config.json" "$TARGET_RUNTIME" "$TARGET_MODEL" "$AGENT" <<'NODE'
const fs = require("fs");
const [file, templateFile, runtime, model, agent] = process.argv.slice(2);
const data = JSON.parse(fs.readFileSync(file, "utf8"));
const template = JSON.parse(fs.readFileSync(templateFile, "utf8"));
data.agent_name = agent;
data.enabled = true;
data.runtime = runtime;
if (model) data.model = model;
else delete data.model;
if (Array.isArray(template.crons)) data.crons = template.crons;
if (template.ecosystem) data.ecosystem = template.ecosystem;
else delete data.ecosystem;
fs.writeFileSync(file, JSON.stringify(data, null, 2) + "\n");
NODE

  if [[ -f "$AGENT_DIR/.env" ]]; then
    if grep -q '^NOVA_AGENT_RUNTIME=' "$AGENT_DIR/.env"; then
      sed "s|^NOVA_AGENT_RUNTIME=.*|NOVA_AGENT_RUNTIME=$TARGET_AGENT_RUNTIME|" "$AGENT_DIR/.env" > "$AGENT_DIR/.env.tmp"
      mv "$AGENT_DIR/.env.tmp" "$AGENT_DIR/.env"
    else
      echo "NOVA_AGENT_RUNTIME=$TARGET_AGENT_RUNTIME" >> "$AGENT_DIR/.env"
    fi
    chmod 600 "$AGENT_DIR/.env"
  fi

  cat > "$AGENT_DIR/.nova-runtime.json" <<EOF
{
  "agent": "$AGENT",
  "org": "$ORG",
  "runtime": "$TARGET_AGENT_RUNTIME",
  "cortext_runtime": "$TARGET_RUNTIME",
  "template": "$TEMPLATE_NAME",
  "last_switched_at": "$timestamp",
  "backup": "$backup_dir"
}
EOF
fi

if [[ -d "$STATE_DIR" ]]; then
  copy_if_exists "$STATE_DIR/codex-app-server-thread.json" "$backup_dir/codex-app-server-thread.json"
  copy_if_exists "$STATE_DIR/claude-code-session.json" "$backup_dir/claude-code-session.json"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    rm -f "$STATE_DIR/codex-app-server-thread.json" "$STATE_DIR/claude-code-session.json"
    echo "runtime switch $timestamp" > "$STATE_DIR/.force-fresh"
  fi
fi

if command -v cortextos >/dev/null 2>&1; then
  echo "+ (cd $CORTEXTOS_HOME && cortextos enable $AGENT --org $ORG)"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    (cd "$CORTEXTOS_HOME" && cortextos enable "$AGENT" --org "$ORG" >/dev/null 2>&1) || true
  fi
  run_cortextos cortextos start "$AGENT"
fi

echo ""
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Dry run complete."
else
  echo "Runtime switch complete."
  echo "Run: scripts/nova-doctor.sh --org '$ORG' --agent '$AGENT'"
fi
