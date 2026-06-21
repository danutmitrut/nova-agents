# Nova Cortex Installation Guide

Ghidul de instalare pentru curs trebuie sa porneasca din trei decizii, in ordinea asta:

1. Runtime agenti: Codex/OpenAI sau Claude Code
2. Locul instalarii: local sau server
3. Canalul de control: Telegram sau Slack

Aceste decizii schimba doar drumul de setup. Dupa instalare, rezultatul este acelasi: un Orchestrator `boss`, apoi un Analyst creat din onboarding.

## 1. Alege runtime-ul: Codex/OpenAI sau Claude Code

### Codex/OpenAI

Recomandat pentru drumul nou de curs.

Foloseste:

```bash
NOVA_AGENT_RUNTIME=codex
```

Autentificare:

```bash
codex
```

Cand login-ul este gata, iesi cu:

```text
/exit
```

Important: autentificarea Codex/OpenAI este per user de sistem. Daca agentii ruleaza ca user `nova`, autentificarea se face ca `nova`, nu ca `root`.

### Claude Code

Ramas suportat pentru compatibilitate si pentru instalari existente.

Foloseste:

```bash
NOVA_AGENT_RUNTIME=claude
```

Autentificare:

```bash
claude
```

Cand login-ul este gata, apasa Enter / iesi din Claude Code.

Important: si Claude Code se autentifica per user de sistem. Daca agentii ruleaza ca `nova`, autentificarea se face ca `nova`.

## 2. Alege unde instalezi: local sau server

### Varianta locala

Se foloseste pentru test rapid, demo sau dezvoltare.

Rulezi pe laptopul tau:

```bash
git clone https://github.com/danutmitrut/nova-agents.git
cd nova-agents
bash nova-init.sh
```

Wizard-ul va intreba runtime-ul si canalul de control.

Avantaje:

- pornire rapida
- usor de modificat codul
- bun pentru dezvoltare

Limite:

- agentii stau online doar cat laptopul ramane pornit
- nu este ideal pentru cursanti care vor agenti always-on

### Varianta server

Recomandata pentru curs si pentru agenti always-on.

Fiecare cursant trebuie sa foloseasca serverul lui sau un server alocat lui. Nu folosim serverul trainerului si nu refolosim token-uri intre cursanti.

Pe server, intra initial ca `root`:

```bash
ssh root@IP_SERVER_CURSANT
```

Creeaza userul pentru agenti:

```bash
adduser nova
usermod -aG sudo nova
mkdir -p /opt/nova-agents
chown -R nova:nova /opt/nova-agents
```

Intra ca user `nova`:

```bash
su - nova
```

Cloneaza repo-ul:

```bash
cd /opt
git clone https://github.com/danutmitrut/nova-agents.git
cd /opt/nova-agents
```

Autentifica runtime-ul ales ca user `nova`:

```bash
codex
```

sau:

```bash
claude
```

Apoi ruleaza instalarea:

```bash
NOVA_AGENT_RUNTIME=codex bash nova-prereq.sh
NOVA_AGENT_RUNTIME=codex bash nova-init.sh
```

Pentru Claude:

```bash
NOVA_AGENT_RUNTIME=claude bash nova-prereq.sh
NOVA_AGENT_RUNTIME=claude bash nova-init.sh
```

Verifica procesele:

```bash
pm2 list
```

Trebuie sa vezi cel putin:

```text
cortextos-daemon
```

Pentru instalările noi cu Slack nativ, nu trebuie să vezi un proces separat de bridge. Slack rulează în `cortextos-daemon`.

Doar dacă ai setat explicit `NOVA_SLACK_MODE=bridge`, trebuie să vezi și:

```text
nova-slack-bridge
```

## 3. Alege canalul: Telegram sau Slack

### Telegram

Telegram este drumul clasic cortextOS.

Ai nevoie de:

- bot pentru Orchestrator, creat in `@BotFather`
- token Telegram pentru Orchestrator
- dupa onboarding, inca un bot/token pentru Analyst

Format token:

```text
123456789:AA...
```

Flow:

1. Rulezi `nova-init.sh`
2. Alegi Telegram
3. Pui token-ul botului Orchestrator
4. Trimiti `/start` sau `salut` botului in Telegram
5. Wizard-ul citeste `CHAT_ID` si `ALLOWED_USER`
6. Porneste Orchestratorul
7. In Telegram trimiti:

```text
/onboarding
```

### Slack

Slack este drumul recomandat pentru echipe si cursuri unde vrei canal dedicat.

Ai nevoie de:

- Slack App cu Socket Mode activ
- Bot token `xoxb-...`
- App-level token `xapp-...` cu `connections:write`
- Channel ID pentru canal dedicat, de forma `C...`
- optional User ID, de forma `U...`

Bot Token Scopes:

```text
app_mentions:read
channels:history
chat:write
files:read
im:history
im:read
```

Bot Events:

```text
app_mention
message.channels
message.im
```

Dupa orice schimbare la scopes sau events, apasa:

```text
Reinstall to Workspace
```

Fara reinstall, Slack App poate arata corect in UI, dar nu trimite events catre cortextOS.

Flow:

1. Creezi Slack App
2. Activezi Socket Mode
3. Pui scopes/events
4. Reinstalezi app-ul in workspace
5. Creezi canal dedicat, de exemplu `#novaboss`
6. Inviti app-ul in canal:

```text
/invite @orchestrator1
```

7. Rulezi `nova-init.sh`
8. Alegi Slack
9. Pui token-urile si Channel ID
10. Scrii in canal, fara mention:

```text
salut
```

11. Pornesti onboarding:

```text
/onboarding
```

Ghidul complet pentru Slack este in:

```text
docs/slack-onboarding.md
```

## Combinatii recomandate pentru curs

### Recomandat

```text
Codex/OpenAI + server + Slack
```

Motiv: acesta este flow-ul cel mai apropiat de agenti always-on pentru echipe si companii.

### Simplu pentru inceput

```text
Codex/OpenAI + server + Telegram
```

Motiv: Telegram are mai putine setari decat Slack.

### Dezvoltare locala

```text
Codex/OpenAI + local + Telegram sau Slack
```

Motiv: bun pentru testarea codului, dar nu pentru agenti care trebuie sa ramana online.

### Compatibilitate

```text
Claude Code + server + Telegram
```

Motiv: pastreaza drumul vechi functional pentru cei care au deja Claude Code.

## Checklist pentru instalare reusita

Inainte de `nova-init.sh`, verifica:

- ai ales runtime-ul: Codex/OpenAI sau Claude Code
- esti pe masina corecta: local sau serverul cursantului
- esti logat ca userul care va rula agentii
- runtime-ul este autentificat pentru acel user
- ai token-urile canalului ales
- pentru Slack ai facut Reinstall to Workspace
- pentru Slack app-ul este invitat in canalul dedicat

Dupa `nova-init.sh`, verifica:

```bash
pm2 list
```

Pentru Telegram:

```text
cortextos-daemon online
```

Pentru Slack:

```text
cortextos-daemon online
```

`nova-slack-bridge online` apare doar în modul legacy/fallback (`NOVA_SLACK_MODE=bridge`).

Test final:

- Telegram: trimite `salut` botului
- Slack: scrie `salut` in canalul dedicat, fara `@`

Daca agentul raspunde, porneste:

```text
/onboarding
```
