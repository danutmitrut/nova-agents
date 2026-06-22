# Runtime fallback Claude/Codex

Nova Cortex supports two agent runtimes:

- `codex` / `codex-app-server`
- `claude` / `claude-code`

The install wizard already lets a student choose the runtime before creating the first agents. Runtime fallback is the separate maintenance flow used after an org already exists.

## Why a switch needs a procedure

Switching runtime is not just changing a model name. Claude and Codex use different runtime files, session state, skill discovery, and restart behavior. The safe rule is:

1. preserve identity, memory, goals, and channel credentials;
2. replace the runtime-specific shell from the matching template;
3. restart the agent fresh;
4. verify with doctor.

## Diagnose first

Run:

```bash
cd ~/nova-agents
bash scripts/nova-doctor.sh --org nova-danut
```

For one agent:

```bash
bash scripts/nova-doctor.sh --org nova-danut --agent boss
```

The doctor reports:

- agent folder;
- configured runtime;
- cortextOS runtime from `config.json`;
- Nova runtime label from `.env` (`claude` or `codex`);
- Telegram or Slack channel;
- required channel credentials, masked;
- cortextOS status.

## Dry run

Always dry-run before a production switch:

```bash
bash scripts/nova-runtime-switch.sh --org nova-danut --agent boss --to claude --dry-run
```

or:

```bash
bash scripts/nova-runtime-switch.sh --org nova-danut --agent boss --to codex --dry-run
```

## Switch

When the dry run looks correct:

```bash
bash scripts/nova-runtime-switch.sh --org nova-danut --agent boss --to claude --yes
```

The script:

- stops the agent;
- creates a backup under `.nova-backups/`;
- writes a handoff note under `memory/handoffs/`;
- preserves `.env`, memory, identity, goals, heartbeat, `SOUL.md`, `GUARDRAILS.md`, and `SYSTEM.md`;
- overlays the target runtime template;
- updates `config.json`;
- updates `NOVA_AGENT_RUNTIME` in `.env`;
- clears runtime session files so the agent starts cleanly;
- re-enables and restarts the agent.

## Agent-managed fallback

The doctor is not an agent. It is a local diagnostic script. However, the orchestrator or analyst can run it from their shell when asked by the user or when investigating a runtime/channel incident:

```bash
NOVA_AGENTS_REPO="${NOVA_AGENTS_REPO:-$HOME/nova-agents}"
bash "$NOVA_AGENTS_REPO/scripts/nova-doctor.sh" --org "$CTX_ORG" --agent "$CTX_AGENT_NAME"
```

The orchestrator may also diagnose another agent:

```bash
bash "$NOVA_AGENTS_REPO/scripts/nova-doctor.sh" --org "$CTX_ORG" --agent analyst
```

For another agent, the orchestrator can run a safe fallback sequence:

```bash
bash "$NOVA_AGENTS_REPO/scripts/nova-runtime-switch.sh" --org "$CTX_ORG" --agent analyst --to claude --dry-run
bash "$NOVA_AGENTS_REPO/scripts/nova-runtime-switch.sh" --org "$CTX_ORG" --agent analyst --to claude --yes
```

For self-fallback, the agent must use detached mode. Without detached mode, the script may stop the very process that is trying to finish the switch.

```bash
bash "$NOVA_AGENTS_REPO/scripts/nova-runtime-switch.sh" --org "$CTX_ORG" --agent "$CTX_AGENT_NAME" --to claude --yes --detach
```

Self-fallback should be treated as a controlled fresh restart: tell the user first, write a memory checkpoint, then run the detached switch.

Detached mode creates immediate feedback before the agent stops:

- `PID`: the background process;
- `Log`: full execution log;
- `Status`: short status file with `queued`, `running`, `complete`, or `failed`.

If the chat channel does not receive an immediate confirmation, inspect the `Status:` file or run `nova-doctor` after a few seconds.

## What is intentionally not preserved

The exact live conversation thread is not portable between runtimes. The switch preserves the agent's durable context, not the open runtime session. Treat fallback as a controlled fresh restart with memory intact.

## Recommended production policy

For live student demos or client work:

1. run `nova-doctor`;
2. run `nova-runtime-switch --dry-run`;
3. switch one agent first;
4. verify heartbeat and outbound channel;
5. switch the paired agent only after the first is healthy.

Do not run the same logical agent active in both runtimes with the same name. If you need a standby, use a different disabled name such as `boss-standby-claude`.

## Course scenario: Claude + Telegram, fallback to Codex

For the course, the common setup is:

- orchestrator runtime: Claude Code;
- control channel: Telegram;
- fallback target: Codex/OpenAI.

When Claude Pro hits usage limits, use this flow from Telegram:

1. Ask the orchestrator:

```text
Ruleaza nova-doctor pentru tine.
```

2. Ask for a dry run:

```text
Fa dry-run de fallback pentru tine pe Codex.
```

3. If the dry run is clean, ask for the real switch:

```text
Executa fallback pentru tine pe Codex cu detach.
```

The orchestrator should run:

```bash
NOVA_AGENTS_REPO="${NOVA_AGENTS_REPO:-$HOME/nova-agents}"
bash "$NOVA_AGENTS_REPO/scripts/nova-runtime-switch.sh" --org "$CTX_ORG" --agent "$CTX_AGENT_NAME" --to codex --yes --detach
```

The target runtime must already be installed and authenticated. For Codex fallback, run `codex` once on that machine/user before the course session, or provide `OPENAI_API_KEY`. The switch script checks that the `codex` CLI exists and warns if it cannot detect Codex auth.
