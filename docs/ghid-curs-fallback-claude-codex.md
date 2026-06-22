# Ghid curs: fallback Claude ↔ Codex

Acest ghid este pentru instalările Nova Cortex folosite la curs, unde pornim de obicei cu:

- Orchestrator pe Claude Code;
- canal de lucru pe Telegram;
- fallback disponibil pe Codex/OpenAI.

Scopul este simplu: dacă Claude Pro intră în limită sau devine indisponibil, cursantul poate muta orchestratorul pe Codex fără să reconstruiască flota.

## Ideea pe scurt

Agentul are două părți:

- identitatea lui: nume, rol, memorie, goals, canal Telegram;
- motorul din spate: Claude sau Codex.

Fallback-ul schimbă motorul, dar păstrează identitatea și canalul.

Conversația live nu se mută perfect între motoare. Agentul repornește curat, dar cu memoria și configurația păstrate.

## Ce pregătim înainte de curs

Pe calculatorul unde rulează Nova Cortex, cursantul trebuie să aibă autentificate ambele runtime-uri.

Pentru Claude:

```bash
claude
```

Pentru Codex:

```bash
codex
```

Alternativ, pentru Codex se poate folosi `OPENAI_API_KEY`, dacă instalarea este făcută pe cheie API.

Verificare rapidă:

```bash
command -v claude
command -v codex
```

Dacă una dintre comenzi nu întoarce o cale, runtime-ul respectiv nu este instalat sau nu este în `PATH`.

## Procedura recomandată din Telegram

Cursantul lucrează normal cu orchestratorul în Telegram.

Când vrea diagnostic:

```text
Rulează nova-doctor pentru tine.
```

Orchestratorul trebuie să verifice:

- ce runtime folosește acum;
- ce canal are configurat;
- dacă Telegram are `BOT_TOKEN`, `CHAT_ID`, `ALLOWED_USER`;
- dacă există manifest runtime;
- ce vede `cortextos status`.

Pentru simulare, fără modificări:

```text
Fă dry-run de fallback pentru tine pe Codex.
```

Dry-run-ul nu schimbă nimic. Arată ce ar urma să se întâmple.

Dacă raportul este curat, switch real:

```text
Execută fallback pentru tine pe Codex cu detach.
```

`detach` este important pentru self-switch. Agentul pornește un proces separat care termină schimbarea după ce el se oprește.

La switch real cu `detach`, comanda afișează imediat:

- `PID`: procesul separat;
- `Log`: fișierul unde se scrie execuția;
- `Status`: fișierul scurt cu `queued`, `running`, `complete` sau `failed`.

Dacă Telegram nu primește imediat confirmare, verifică statusul sau rulează `nova-doctor` după câteva secunde.

## Procedura din terminal

Intră în repo:

```bash
cd ~/nova-agents
```

Diagnostic:

```bash
bash scripts/nova-doctor.sh --org nova-danut-mitrut --agent orchestrator
```

Dry-run Claude → Codex:

```bash
bash scripts/nova-runtime-switch.sh --org nova-danut-mitrut --agent orchestrator --to codex --dry-run
```

Switch real Claude → Codex:

```bash
bash scripts/nova-runtime-switch.sh --org nova-danut-mitrut --agent orchestrator --to codex --yes --detach
```

Comanda va afișa un fișier `Status:` în `/tmp/nova-runtime-switch/` sau în `$TMPDIR/nova-runtime-switch/`. Verificare:

```bash
cat <calea-din-Status>
```

Revenire Codex → Claude:

```bash
bash scripts/nova-runtime-switch.sh --org nova-danut-mitrut --agent orchestrator --to claude --yes --detach
```

După switch, verifică:

```bash
bash scripts/nova-doctor.sh --org nova-danut-mitrut --agent orchestrator
```

## Ce face switch-ul real

Scriptul:

- oprește agentul;
- creează backup în folderul agentului;
- păstrează `.env`, memoria, identitatea, goals, canalul Telegram, `SOUL.md`, `GUARDRAILS.md` și `SYSTEM.md`;
- aplică template-ul runtime-ului țintă;
- actualizează `config.json`;
- schimbă `NOVA_AGENT_RUNTIME`;
- curăță sesiunea veche;
- repornește agentul.

## Reguli de siguranță

Nu face switch real fără dry-run înainte.

Nu face self-switch fără `--detach`.

Nu comuta pe Codex dacă `codex` nu este instalat/autentificat.

Nu comuta pe Claude dacă `claude` nu este instalat/autentificat.

Nu porni două instanțe active ale aceluiași agent cu același nume.

## Formulări simple pentru cursanți

Diagnostic:

```text
Rulează nova-doctor pentru tine.
```

Simulare:

```text
Fă dry-run de fallback pentru tine pe Codex.
```

Switch real:

```text
Execută fallback pentru tine pe Codex cu detach.
```

Revenire:

```text
Execută fallback pentru tine pe Claude cu detach.
```

## Pentru instructor

Înainte de demonstrație:

```bash
cd ~/nova-agents
bash scripts/nova-doctor.sh --org nova-danut-mitrut --agent orchestrator
bash scripts/nova-runtime-switch.sh --org nova-danut-mitrut --agent orchestrator --to codex --dry-run
```

În timpul demonstrației, arată întâi comenzile din Telegram. Terminalul rămâne varianta de control manual dacă agentul nu răspunde.

Pentru instalări noi, ghidul complet tehnic este în:

```text
docs/runtime-fallback.md
```
