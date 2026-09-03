# Nova Cortex

**Multi-agent AI workforce for your business.** A curated team of always-on agents — Orchestrator + Analyst — controlled from Telegram or Slack, running on your own machine or server. Mac/Linux installs can run on **Codex/OpenAI** (`codex-app-server`) or Claude Code; specialist agents (CFO, marketer, ops, research, storytelling, copywriting, anything you need) are spawned once the core is online.

Built on top of the [cortextOS engine](https://github.com/grandamenium/cortextos) (open-source multi-agent framework, MIT).

---

## What you get out of the box

- **Nova Cortex Orchestrator** — your chief of staff. Sends morning + evening briefings, cascades daily goals to your team, monitors fleet health, surfaces approvals to you.
- **Nova Cortex Analyst** — the orchestrator's analytical partner. Monitors system health, runs the theta-wave improvement cycle, detects anomalies, tracks KPIs across your fleet.
- **Codex/OpenAI runtime** — recommended for the course path; Claude Code remains supported as a compatibility option.
- **Telegram or Slack control** — message your team from anywhere, they keep working overnight.
- **Persistent state** — auto-restart on crash, conversation memory across sessions, knowledge base (RAG) shared across agents.

Specialist agents (anything domain-specific you need) are added later — the Orchestrator helps you spawn them on demand once the core pair is online. Nova Academy's course walks through this.

---

## Quick start

> **Windows local — în testare cu cursanții.** Noul installer este disponibil pentru testare, dar nu a fost încă validat pe Windows real (PowerShell 5.1/7, PM2/CA, mesaje Telegram și reboot). Rezultatele testelor locale nu înlocuiesc această validare. Folosește [protocolul Windows](docs/windows-test-plan.md); dacă apare un refuz, păstrează datele și raportează mesajul fără tokenuri sau fișiere `.env`.

Pentru curs, instalarea are trei decizii:

1. **Runtime:** Codex/OpenAI (recomandat) sau Claude Code.
2. **Locatie:** local pentru test/dezvoltare sau server pentru agenti always-on.
3. **Canal:** Telegram sau Slack.

Ghidul complet este in [`docs/installation-options.md`](docs/installation-options.md). Pentru Slack, foloseste si [`docs/slack-onboarding.md`](docs/slack-onboarding.md). Pentru fallback intre Claude si Codex dupa instalare, vezi [`docs/runtime-fallback.md`](docs/runtime-fallback.md); pentru varianta explicata pentru cursanti, vezi [`docs/ghid-curs-fallback-claude-codex.md`](docs/ghid-curs-fallback-claude-codex.md). Pentru recuperarea controlata a engine-ului, vezi [`docs/safe-engine-installer.md`](docs/safe-engine-installer.md); pentru validarea pe Windows, foloseste [`docs/windows-test-plan.md`](docs/windows-test-plan.md). Pentru modelul de permisiuni al agentilor si aprobari pe Telegram, vezi [`docs/permisiuni-agenti.md`](docs/permisiuni-agenti.md).

Pentru mentenanta repo-ului si debug pe instalari, vezi [`WORKFLOW.md`](WORKFLOW.md). Acolo este notata copia canonica de lucru si checklistul minim inainte de commit/push.

### 1. Install

**Mac or Linux** (Ubuntu/Debian) terminal:

```bash
git clone https://github.com/danutmitrut/nova-agents.git
cd nova-agents
bash nova-init.sh
```

**Windows** PowerShell (native — not WSL):

```powershell
# Open PowerShell as Administrator (required — see below)
git clone https://github.com/danutmitrut/nova-agents.git
cd nova-agents
.\nova-prereq.ps1   # verifică/instalează toolchain-ul și pregătește engine-ul pin-uit
.\nova-init.ps1     # wizard (can run from regular PowerShell after prereq passes)
```

> **PowerShell must be Administrator** when running `nova-prereq.ps1` — winget needs admin rights to install Visual Studio Build Tools, jq, and Python globally. After prereq, `nova-init.ps1` runs fine from a regular PowerShell. The script halts with clear instructions if started without admin.

> **WSL2 is not supported.** Nova Cortex runs natively on Windows via PowerShell — the cortextOS engine and Claude Code's PTY have edge cases under WSL that don't have clean fixes.

The Mac/Linux wizard will:
1. Ask which runtime you want: Codex/OpenAI (recommended) or Claude Code.
2. Run the prereq script — verifică/instalează Node.js 20+, runtime-ul ales (`codex` sau `claude`), PM2 (și Homebrew pe Mac, `jq` pe Linux), apoi pregătește engine-ul la pinul verificat.
3. Walk you through a wizard: workspace name → control channel → Telegram bot handshake or Slack Socket Mode tokens.
4. Install the Nova Cortex templates, spawn your Orchestrator, wire up the selected channel, and auto-start the agent.

The Windows PowerShell wizard offers the same four steps as the Mac/Linux one, including the Telegram or Slack choice.

For Telegram, you'll need **two BotFather tokens** total: one for the Orchestrator (asked here), one for the Analyst (asked later by the Orchestrator during `/onboarding`). Create both ahead of time from `@BotFather` on Telegram if you want a smooth flow.

For Slack, create a Slack app with Socket Mode enabled before running the wizard. You need:

- Bot token: `xoxb-...`
- App-level token: `xapp-...` with `connections:write`
- Channel ID for the dedicated control channel, e.g. `C123...`
- Bot scopes: `app_mentions:read`, `channels:history`, `chat:write`, `files:read`, `im:history`, `im:read`
- Bot events: `app_mention`, `message.channels`, `message.im`
- Unul sau mai multe Slack Member ID-uri autorizate, de forma `U...` sau `W...`, separate prin virgulă

After changing scopes or events in Slack, click **Reinstall to Workspace**. Without reinstalling, Slack will not deliver the new event types. Nova Cortex starts its Slack Socket Mode bridge automatically and writes `SLACK_ALLOWED_USER` as a comma-separated allowlist; only those members can command the agent.

For Codex/OpenAI, run `codex` interactively once to sign in with ChatGPT/OpenAI, or set `OPENAI_API_KEY` for the user running the agents. The wizard reminds you if this is missing.

For Claude Code, run `claude` interactively once to log in to Claude Code. The wizard reminds you if this is missing.

### 2. Send a message

Open your chosen channel:

- Telegram: find the bot you connected and say `hello`.
- Slack: invite the app to the dedicated control channel and write normally, or DM the app.

Then send:

```
/onboarding
```

The Orchestrator will walk you through identity, working hours, autonomy rules, daily goal cascade — and then ask you for the second BotFather token to bring the Analyst online. After that, you have a working 2-agent team and the Orchestrator can help you add specialist agents whenever you're ready.

### Restarting the Orchestrator later

Pentru o recuperare controlată, folosește helper-ul din checkout-ul Nova; el verifică engine-ul și cere confirmare înaintea unui restart al daemonului existent:

```bash
node scripts/nova-engine.mjs start --org NUME_ORG --channel telegram
```

Înlocuiește `telegram` cu `slack` când acesta este canalul configurat. Nu folosi `cortextos start boss` ca fallback și nu executa `pm2 save` direct: vezi ghidul de recuperare pentru refuzuri, CA și snapshot-uri PM2.

---

## What's in this repo

| Path | Purpose |
|------|---------|
| `nova-prereq.sh` | Mac/Linux prereq checker — instalează/verifică Homebrew (Mac), jq, Node 20+, runtime-ul ales și PM2; apoi aplică verificarea strictă a engine-ului. Poate refuza o reluare pentru a păstra starea existentă. |
| `nova-prereq.ps1` | Echivalent Windows (PowerShell 5.1+): instalează/verifică toolchain-ul și apoi verifică strict engine-ul; o reluare poate necesita intervenție, nu continuă automat. |
| `nova-init.sh` | Mac/Linux student wizard. Picks runtime + workspace name + Telegram or Slack, then provisions the Orchestrator. |
| `scripts/nova-doctor.sh` | Diagnoses installed orgs/agents: runtime, channel, credentials presence, and cortextOS status. |
| `scripts/nova-runtime-switch.sh` | Safely switches an existing agent between Claude and Codex with backup, template overlay, and fresh restart. |
| `templates/nova-cortex-orchestrator-codex/` | Codex/OpenAI Orchestrator template (`runtime: codex-app-server`, `model: gpt-5-codex`). |
| `templates/nova-cortex-analyst-codex/` | Codex/OpenAI Analyst template (`runtime: codex-app-server`, `model: gpt-5-codex`). |
| `slack-bridge/` | Slack Socket Mode bridge used by Nova Cortex installs. It supports a comma-separated multiuser allowlist. |
| `nova-init.ps1` | Windows-native wizard (PowerShell). Same flow as `nova-init.sh`: runtime + workspace name + Telegram or Slack. |
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

Nova Cortex is a **branding + curated-templates layer** on top of [cortextOS](https://github.com/grandamenium/cortextos). The actual multi-agent runtime, daemon, bus, knowledge base, and Telegram integration come from cortextOS — an open-source framework by Cortext LLC (MIT licensed). Nova Cortex supplies the Slack Socket Mode bridge, installation flow, and multiuser Slack access control.

Attribution for the original upstream project remains separate from the installer release source. Nova's safe installer currently pins a reviewed commit from the canonical installer fork; it does not follow `main` automatically and does not imply that the hotfix was merged upstream.

- original cortextOS upstream: https://github.com/grandamenium/cortextos
- original cortextOS license: MIT, Copyright (c) 2026 Cortext LLC
- canonical engine source used by this installer: https://github.com/danutmitrut/cortextos.git (pinned revision documented in `docs/safe-engine-installer.md`)
- Nova Cortex license: MIT, Copyright (c) 2026 Nova Academy

---

## Status

This is the bootstrap repo for the Nova Academy course on agent orchestration. The Orchestrator + Analyst templates are production-grade and identical in capability to the cortextOS originals; the Nova Cortex layer adds brand and wraps the install in a friendly wizard. Specialist agents are intentionally not pre-built — the course teaches you how to spawn them yourself.

Issues, ideas, PRs welcome.
