# Nova Cortex

**Multi-agent AI workforce for your business.** A curated team of always-on Claude Code agents — Orchestrator + Analyst — controlled from Telegram, running on your own machine. Specialist agents (CFO, marketer, ops, research, anything you need) you spawn yourself once the core is online.

Built on top of the [cortextOS engine](https://github.com/grandamenium/cortextos) (open-source multi-agent framework, MIT).

---

## What you get out of the box

- **Nova Cortex Orchestrator** — your chief of staff. Sends morning + evening briefings, cascades daily goals to your team, monitors fleet health, surfaces approvals to you.
- **Nova Cortex Analyst** — the orchestrator's analytical partner. Monitors system health, runs the theta-wave improvement cycle, detects anomalies, tracks KPIs across your fleet.
- **Telegram control** — message your team from anywhere, they keep working overnight.
- **Persistent state** — auto-restart on crash, conversation memory across sessions, knowledge base (RAG) shared across agents.

Specialist agents (anything domain-specific you need) are added later — the Orchestrator helps you spawn them on demand once the core pair is online. Nova Academy's course walks through this.

---

## Quick start

### 1. Install

**Mac or Linux** (Ubuntu/Debian) terminal:

```bash
git clone https://github.com/<your-fork>/nova-agents.git
cd nova-agents
bash nova-init.sh
```

**Windows** PowerShell (native — not WSL):

```powershell
git clone https://github.com/<your-fork>/nova-agents.git
cd nova-agents
.\nova-init.ps1
```

> WSL2 is not supported. Nova Cortex runs natively on Windows via PowerShell — the cortextOS engine and Claude Code's PTY have edge cases under WSL that don't have clean fixes.

Both wizards will:
1. Run the prereq script if needed — installs Node.js 20+, Claude Code CLI, cortextOS engine, PM2 (and Homebrew on Mac, `jq` on Linux).
2. Walk you through a 3-step wizard: workspace name → Telegram bot token → handshake (you send a message to the bot, the wizard reads the `chat_id` + your `user_id` automatically).
3. Install the Nova Cortex templates, spawn your Orchestrator, wire up Telegram, and auto-start the agent.

You'll need **two BotFather tokens** total: one for the Orchestrator (asked here), one for the Analyst (asked later by the Orchestrator during `/onboarding`). Create both ahead of time from `@BotFather` on Telegram if you want a smooth flow.

Before running the wizard, you'll also need to run `claude` interactively once to log in to Claude Code (the wizard reminds you if you haven't).

### 2. Send a message

Open Telegram → find the bot you connected → say `hello`. Then send:

```
/onboarding
```

The Orchestrator will walk you through identity, working hours, autonomy rules, daily goal cascade — and then ask you for the second BotFather token to bring the Analyst online. After that, you have a working 2-agent team and the Orchestrator can help you add specialist agents whenever you're ready.

### Restarting the Orchestrator later

If you ever need to manually restart the agent:

```bash
# Mac/Linux:
cd ~/cortextos && cortextos start boss

# Windows PowerShell:
cd $env:USERPROFILE\cortextos; cortextos start boss
```

---

## What's in this repo

| Path | Purpose |
|------|---------|
| `nova-prereq.sh` | Mac/Linux prereq checker — auto-installs Homebrew (Mac), jq, Node 20+, Claude Code, cortextOS, PM2. Idempotent. |
| `nova-prereq.ps1` | Windows-native equivalent (PowerShell 5.1+). Installs Node via `winget`, Claude Code + cortextOS + PM2 via npm. Idempotent. |
| `nova-init.sh` | Mac/Linux student wizard. Picks workspace name + Telegram token, then provisions the Orchestrator. |
| `nova-init.ps1` | Windows-native wizard (PowerShell). Same 3-step flow as the bash version. |
| `templates/nova-cortex-orchestrator/` | Branded Orchestrator template — installed into `$HOME/cortextos/templates/` by either init script. |
| `templates/nova-cortex-analyst/` | Branded Analyst template — installed alongside, spawned by the Orchestrator during `/onboarding`. |
| `LICENSE` | MIT, with cortextOS attribution. |

---

## Customizing

Want to fork this for your own brand?

1. Rename each `templates/nova-cortex-*` directory to `templates/<your-brand>-*`.
2. Patch the brand surfaces: `IDENTITY.md`, the `CLAUDE.md` header, the boot message in `ONBOARDING.md` Step 1, and the identity template in Step 18 (orchestrator only).
3. Update `nova-init.sh` to install your renamed templates + adjust the wizard text.
4. Update the orchestrator's `ONBOARDING.md` Step 26 to spawn your renamed analyst template (`--template <your-brand>-analyst`).
5. Drop the `LICENSE` attribution to your own name (keep the cortextOS notice — that's the MIT obligation).

---

## Engine & attribution

Nova Cortex is a **branding + curated-templates layer** on top of [cortextOS](https://github.com/grandamenium/cortextos). The actual multi-agent runtime, daemon, bus, knowledge base, and Telegram integration all come from cortextOS — an open-source framework by Cortext LLC (MIT licensed).

We don't fork cortextOS. We pin to its releases and ship our templates on top. That means cortextOS updates flow downstream automatically.

- cortextOS source: https://github.com/grandamenium/cortextos
- cortextOS license: MIT, Copyright (c) 2026 Cortext LLC
- Nova Cortex license: MIT, Copyright (c) 2026 Nova Academy

---

## Status

This is the bootstrap repo for the Nova Academy course on agent orchestration. The Orchestrator + Analyst templates are production-grade and identical in capability to the cortextOS originals; the Nova Cortex layer adds brand and wraps the install in a friendly wizard. Specialist agents are intentionally not pre-built — the course teaches you how to spawn them yourself.

Issues, ideas, PRs welcome.
