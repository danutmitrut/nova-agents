# Nova Cortex Slack Onboarding

Ghid testat pentru conectarea Nova Cortex la Slack prin `slack-bridge`.

Arhitectura este simpla:

- Slack trimite mesaje catre `slack-bridge` prin Socket Mode.
- Bridge-ul injecteaza mesajele in `boss` prin `cortextos bus send-message`.
- Agentul raspunde catre numele `slack`.
- Bridge-ul citeste inbox-ul `slack` si posteaza raspunsul inapoi in Slack.

`slack` este bridge/outbox, nu agent worker. Este normal sa nu apara in `cortextos bus list-agents`.

## 0. Regula per cursant

Fiecare cursant trebuie sa lucreze pe serverul lui, cu autentificarile lui. Nu se foloseste serverul trainerului si nu se refolosesc token-uri intre cursanti.

Fiecare cursant are nevoie de:

- server Hetzner propriu sau server alocat lui
- acces SSH la acel server
- user Linux pentru agenti, recomandat `nova`
- autentificare Codex/OpenAI facuta pe server, pentru userul Linux care ruleaza agentii
- Slack App/token-uri proprii pentru workspace-ul folosit
- Channel ID propriu pentru canalul dedicat
- optional User ID propriu pentru `SLACK_ALLOWED_USER`

Important: autentificarea Codex/OpenAI este per user Linux. Daca agentii ruleaza ca `nova`, ruleaza `codex` cand esti logat ca `nova`, nu ca `root`.

```bash
ssh root@IP_SERVER_CURSANT
su - nova
codex
```

Dupa login, iesi din Codex cu:

```text
/exit
```

Abia apoi ruleaza:

```bash
cd /opt/nova-agents
NOVA_AGENT_RUNTIME=codex bash nova-prereq.sh
NOVA_AGENT_RUNTIME=codex bash nova-init.sh
```

## 1. Creeaza Slack App

Intra in <https://api.slack.com/apps>.

1. Create New App
2. From scratch
3. App name: `orchestrator1` sau `Nova Cortex`
4. Alege workspace-ul corect
5. Create App

## 2. Activeaza Socket Mode

In Slack App:

1. **Socket Mode**
2. Enable Socket Mode: ON
3. Creeaza App-Level Token:
   - Name: `nova-socket`
   - Scope: `connections:write`
4. Copiaza token-ul `xapp-...`

Acesta este:

```bash
SLACK_APP_TOKEN=xapp-...
```

## 3. Bot Token Scopes

In **OAuth & Permissions**, adauga exact aceste Bot Token Scopes:

```text
app_mentions:read
channels:history
chat:write
files:read
im:history
im:read
```

Nu adauga pentru testul de baza:

```text
groups:history
mpim:history
```

Acestea sunt doar pentru private channels si multi-person DMs.

## 4. Event Subscriptions

In **Event Subscriptions**, activeaza Events si adauga Bot Events:

```text
app_mention
message.channels
message.im
```

Fara `message.channels`, botul nu primeste mesaje simple din canal. Vei putea vorbi cu el doar prin `@orchestrator1`.

## 5. Reinstall to Workspace

Dupa ce modifici scopes sau events, mergi la **OAuth & Permissions** si apasa:

```text
Reinstall to Workspace
```

Acesta este pasul care se uita cel mai usor. Fara reinstall, Slack App UI poate arata corect, dar events/scopes nu sunt active in workspace.

Dupa reinstall, copiaza:

```bash
SLACK_BOT_TOKEN=xoxb-...
```

## 6. Ia ID-urile corecte

ID-urile sunt specifice workspace-ului. Acelasi om poate avea alt `U...` in alt workspace.

### Channel ID

In canalul dedicat, de exemplu `#novaboss`:

1. Click pe numele canalului
2. About / Settings
3. Copy Channel ID sau Copy link
4. ID-ul arata ca `C0B4AJ1RF41`

Acesta se pune in:

```bash
SLACK_DEFAULT_CHANNEL=C...
SLACK_LISTEN_CHANNELS=C...
```

`SLACK_LISTEN_CHANNELS` este canalul unde poti scrie fara `@`.

### User ID

Profilul tau Slack:

1. Click pe profil
2. More / trei puncte
3. Copy member ID

Arata ca `U0B3R6QL745`.

Acesta este optional:

```bash
SLACK_ALLOWED_USER=U...
```

Daca il setezi, doar acel user poate vorbi cu agentul.

## 7. `.env` pe server

Pe server:

```bash
cd /opt/nova-agents/slack-bridge
nano .env
```

Continut:

```bash
SLACK_BOT_TOKEN=xoxb-...
SLACK_APP_TOKEN=xapp-...
CTX_ORG=nova-danut
NOVA_TARGET_AGENT=boss
NOVA_BRIDGE_AGENT=slack
CTX_FRAMEWORK_ROOT=/home/nova/cortextos
CTX_PROJECT_ROOT=/home/nova/cortextos
CTX_INSTANCE_ID=default
SLACK_ALLOWED_USER=U...
SLACK_DEFAULT_CHANNEL=C...
SLACK_LISTEN_CHANNELS=C...
SLACK_BRIDGE_STATE=/home/nova/cortextos/slack-bridge-state.json
SLACK_MEDIA_DIR=/home/nova/cortextos/orgs/nova-danut/agents/boss/slack-media
SLACK_MAX_FILE_BYTES=104857600
```

Salvare in nano:

```text
Ctrl+O
Enter
Ctrl+X
```

## 8. Porneste bridge-ul

```bash
cd /opt/nova-agents/slack-bridge
npm install
pm2 delete nova-slack-bridge 2>/dev/null || true
pm2 start npm --name nova-slack-bridge -- start
pm2 save
pm2 list
```

Trebuie sa vezi:

```text
cortextos-daemon    online
nova-slack-bridge   online
```

Log:

```bash
pm2 logs nova-slack-bridge --lines 80
```

Linia buna:

```text
[nova-slack-bridge] running. Slack -> boss, replies via slack
```

## 9. Teste

### Canal dedicat

In canalul din `SLACK_LISTEN_CHANNELS`, scrie fara mention:

```text
salut
```

Bridge-ul nu mai trimite ACK de tip `Primit. Trimit...`; trebuie sa apara doar raspunsul agentului.

### Alt canal

In orice alt canal unde app-ul este invitat, foloseste mention:

```text
@orchestrator1 salut
```

### DM

Trimite direct mesaj app-ului.

### Fisiere

Trimite in canalul dedicat sau DM:

- imagine
- PDF/document
- audio
- video scurt

Agentul primeste:

```text
[IMAGE]
file_name: screenshot.png
mime_type: image/png
size: 12345
local_file: slack-media/...
```

Regula: agentul citeste `local_file:` direct. Nu cere userului sa retrimita fisierul.

## 10. Debug rapid

Bridge pornit?

```bash
pm2 list
pm2 logs nova-slack-bridge --lines 80
```

Slack livreaza events?

In log trebuie sa apara:

```text
[nova-slack-bridge] message subtype=none user=... channel=... channel_type=channel
```

Nu apare nimic?

- verifica `message.channels`
- verifica `Reinstall to Workspace`
- verifica daca app-ul este invitat in canal
- verifica daca ai luat ID-ul canalului din workspace-ul corect

Raspunsurile agentului nu ajung in Slack?

- verifica `NOVA_BRIDGE_AGENT=slack`
- verifica `SLACK_DEFAULT_CHANNEL`
- verifica `SLACK_BRIDGE_STATE`
- tine minte: warning-ul cortextOS `agent 'slack' not found` poate aparea, dar `slack` este bridge/outbox, nu worker agent

Fisierele nu ajung?

- verifica scope-ul `files:read`
- reinstaleaza app-ul in workspace
- verifica `SLACK_MEDIA_DIR`
