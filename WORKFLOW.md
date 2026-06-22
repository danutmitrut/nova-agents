# Nova Agents Working Protocol

Acest repo are o regula simpla: lucram doar din copia canonica si verificam starea reala inainte de concluzii.

## Repo canonic

- Foloseste: `/Users/danmitrut/nova-agents`
- Remote: `https://github.com/danutmitrut/nova-agents.git`
- Branch principal: `main`

Nu folosi pentru lucru curent:

- `/Users/danmitrut/PROIECTE AI/nova-agents`

Acea copie poate ramane in urma si poate arata o realitate veche, de exemplu Telegram-only, chiar daca repo-ul canonic are Slack native.

## Verificare obligatorie inainte de raspunsuri despre repo

Ruleaza din repo-ul canonic:

```bash
pwd
git status --short
git log --oneline --decorate -3
git remote -v
```

Daca intrebarea este despre ce exista pe GitHub, verifica si:

```bash
gh repo view danutmitrut/nova-agents --json defaultBranchRef,pushedAt,url
git status -sb
```

## Reguli de lucru

1. Inainte de orice modificare, confirma folderul de lucru.
2. Nu compara o copie locala veche cu GitHub si nu trage concluzii din ea.
3. Dupa modificari, ruleaza `git diff --stat` si `git status --short`.
4. Pentru schimbari care trebuie distribuite cursantilor, commit + push se fac doar din repo-ul canonic.
5. Daca problema tine de engine, modifica si impinge `cortextos`, nu doar `nova-agents`.

## Repo-uri separate

`nova-agents` este wizardul, documentatia si template-urile Nova Cortex.

`cortextos` este engine-ul: daemon, CLI, Slack/Telegram runtime, `cortextos enable`, `cortextos start`.

Daca wizardul scrie corect credentialele Slack dar agentul tot nu porneste, verifica `cortextos`, nu doar `nova-agents`.

## Slack si Telegram

Instalarile noi Nova pot folosi Telegram sau Slack.

Slack native este modul implicit pentru Slack. Bridge-ul Slack este fallback legacy si se porneste doar cu:

```bash
NOVA_SLACK_MODE=bridge
```

Pentru Slack native, `.env` trebuie sa contina:

```text
NOVA_CONTROL_CHANNEL=slack
SLACK_BOT_TOKEN=...
SLACK_APP_TOKEN=...
SLACK_CHANNEL_ID=...
SLACK_ALLOWED_USER=...
```

Pentru Telegram, `.env` trebuie sa contina:

```text
NOVA_CONTROL_CHANNEL=telegram
BOT_TOKEN=...
CHAT_ID=...
ALLOWED_USER=...
```

## Checklist pentru buguri de instalare

1. Verifica repo-ul canonic.
2. Verifica daca bugul e in `nova-agents` sau in `cortextos`.
3. Verifica ce branch/commit este pe GitHub.
4. Reproduce pe o instalare curata sau pe un org nou.
5. Fixeaza local.
6. Ruleaza testul minim.
7. Commit + push.
8. Noteaza pe scurt ce s-a schimbat si ce trebuie sa faca un cursant.
