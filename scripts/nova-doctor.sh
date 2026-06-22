#!/usr/bin/env bash
# nova-doctor.sh — diagnose Nova Cortex org/agent runtime and channel wiring.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/nova-doctor.sh --org <org> [--agent <agent>]

Examples:
  scripts/nova-doctor.sh --org nova-danut
  scripts/nova-doctor.sh --org nova-danut --agent boss
EOF
}

ORG=""
AGENT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org) ORG="${2:-}"; shift 2 ;;
    --agent) AGENT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$ORG" ]]; then
  echo "Missing --org." >&2
  usage
  exit 2
fi

CORTEXTOS_HOME="${CORTEXTOS_HOME:-$HOME/cortextos}"
ORG_DIR="$CORTEXTOS_HOME/orgs/$ORG"

if [[ ! -d "$ORG_DIR" ]]; then
  echo "Org not found: $ORG_DIR" >&2
  exit 1
fi

json_value() {
  local file="$1"
  local key="$2"
  node -e '
    const fs = require("fs");
    const [file, key] = process.argv.slice(1);
    const data = JSON.parse(fs.readFileSync(file, "utf8"));
    const value = key.split(".").reduce((acc, part) => acc && acc[part], data);
    if (value !== undefined && value !== null) console.log(value);
  ' "$file" "$key" 2>/dev/null || true
}

env_value() {
  local file="$1"
  local key="$2"
  if [[ -f "$file" ]]; then
    awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file"
  fi
}

mask_value() {
  local value="$1"
  if [[ -z "$value" ]]; then
    echo "missing"
  elif [[ ${#value} -le 10 ]]; then
    echo "set"
  else
    echo "${value:0:6}...${value: -4}"
  fi
}

expected_nova_runtime() {
  case "$1" in
    claude-code) echo "claude" ;;
    codex-app-server) echo "codex" ;;
    *) echo "" ;;
  esac
}

agents=()
if [[ -n "$AGENT" ]]; then
  agents+=("$AGENT")
else
  while IFS= read -r path; do
    agents+=("$(basename "$path")")
  done < <(find "$ORG_DIR/agents" -mindepth 1 -maxdepth 1 -type d | sort)
fi

echo "Nova Doctor"
echo "Org: $ORG"
echo "Path: $ORG_DIR"
echo ""

for agent in "${agents[@]}"; do
  agent_dir="$ORG_DIR/agents/$agent"
  config="$agent_dir/config.json"
  env_file="$agent_dir/.env"

  if [[ ! -d "$agent_dir" ]]; then
    echo "[$agent] missing at $agent_dir"
    continue
  fi

  runtime="$(json_value "$config" runtime)"
  model="$(json_value "$config" model)"
  channel="$(env_value "$env_file" NOVA_CONTROL_CHANNEL)"
  nova_runtime="$(env_value "$env_file" NOVA_AGENT_RUNTIME)"
  expected_runtime="$(expected_nova_runtime "$runtime")"

  echo "[$agent]"
  echo "  path: $agent_dir"
  echo "  cortextOS runtime: ${runtime:-missing}${model:+ ($model)}"
  echo "  Nova runtime label: ${nova_runtime:-missing}${expected_runtime:+ (expected: $expected_runtime)}"
  if [[ -n "$expected_runtime" && -n "$nova_runtime" && "$nova_runtime" != "$expected_runtime" ]]; then
    echo "  warning: NOVA_AGENT_RUNTIME should normally be '$expected_runtime' for '$runtime'"
  fi
  echo "  channel: ${channel:-missing}"

  case "$channel" in
    telegram)
      echo "  telegram BOT_TOKEN: $(mask_value "$(env_value "$env_file" BOT_TOKEN)")"
      echo "  telegram CHAT_ID: $(mask_value "$(env_value "$env_file" CHAT_ID)")"
      echo "  telegram ALLOWED_USER: $(mask_value "$(env_value "$env_file" ALLOWED_USER)")"
      ;;
    slack)
      echo "  slack SLACK_BOT_TOKEN: $(mask_value "$(env_value "$env_file" SLACK_BOT_TOKEN)")"
      echo "  slack SLACK_APP_TOKEN: $(mask_value "$(env_value "$env_file" SLACK_APP_TOKEN)")"
      echo "  slack SLACK_CHANNEL_ID: $(mask_value "$(env_value "$env_file" SLACK_CHANNEL_ID)")"
      echo "  slack SLACK_ALLOWED_USER: $(mask_value "$(env_value "$env_file" SLACK_ALLOWED_USER)")"
      ;;
    *)
      echo "  warning: NOVA_CONTROL_CHANNEL is missing or unknown"
      ;;
  esac

  if [[ -f "$agent_dir/.nova-runtime.json" ]]; then
    echo "  runtime manifest: present"
  else
    echo "  runtime manifest: missing"
  fi
  echo ""
done

if command -v cortextos >/dev/null 2>&1; then
  echo "cortextos status:"
  (cd "$CORTEXTOS_HOME" && cortextos status) || true
else
  echo "cortextos status: cortextos command not found"
fi
