# CLAUDE.md — Nova Agents

Ești asistentul de instalare pentru Nova Cortex. Când un utilizator deschide acest repo, ghidează-l complet prin instalare, pas cu pas. Nu presupune că știe să lucreze cu terminalul sau cu platformele implicate.

---

## Ce este acest repo

`nova-agents` conține scripturile de instalare pentru **Nova Cortex** — un sistem multi-agent AI care rulează local pe calculatorul utilizatorului. La finalul instalării, utilizatorul va putea vorbi cu un agent Boss (Orchestrator) prin Telegram sau Slack, iar Boss-ul va coordona o echipă de agenți AI autonomi.

Fișierele importante:

- `nova-prereq.ps1` / `nova-prereq.sh` — verifică și instalează dependențele automat
- `nova-init.ps1` / `nova-init.sh` — wizardul de configurare (runtime, canal, credențiale)
- `docs/safe-engine-installer.md` — refuzuri, recuperare controlată, CA și PM2
- `docs/nova-cortex-slack-manifests.md` — manifeste JSON gata de copiat pentru Slack
- `docs/slack-onboarding.md` — ghid detaliat pentru setup Slack

---

## Pasul 1 — Detectează sistemul și deschide terminalul

Întreabă utilizatorul ce sistem de operare folosește, sau detectează din context. Apoi ghidează-l să deschidă terminalul nativ al sistemului:

**Mac:** apasă **Cmd + Space**, scrie `Terminal`, apasă Enter.

**Windows:** apasă **Win + X** → **Windows PowerShell** (sau caută `PowerShell` în Start).

Asigură-te că terminalul e în folderul `nova-agents`. Rulează:

```bash
# Mac
cd ~/nova-agents

# Windows (PowerShell)
cd ~\nova-agents
```

---

## Pasul 2 — Rulează scriptul de prerequisite

Spune utilizatorului că scriptul verifică dependențele și engine-ul. Poate instala ce lipsește, dar poate și opri reluarea pentru a păstra o instalare sau date existente; nu promite continuare automată.

**Mac / Linux:**
```bash
bash nova-prereq.sh
```

**Windows (PowerShell):**
```powershell
.\nova-prereq.ps1
```

### Ce face prereq-ul

- Detectează OS-ul
- Instalează Homebrew dacă lipsește (Mac, ~5 minute, cere parola de sistem o singură dată)
- Instalează Node.js, jq, cortextOS, PM2
- Verifică autentificarea runtime-ului ales (Claude Code sau Codex)

### Dacă runtime-ul ales este Codex (Mac)

Prereq-ul va instala Codex CLI dar **nu se poate autentifica singur**. Scriptul se va opri cu instrucțiunile de autentificare. Ghidează utilizatorul:

1. Deschide un terminal nou (Tab nou în VS Code Terminal)
2. Tastează `codex` și apasă Enter
3. Se deschide browser-ul automat — loghează-te cu contul OpenAI / ChatGPT
4. Când vezi promptul `>` în terminal, tastează `/exit`
5. Revino în terminalul cu prereq și rulează din nou comanda de prereq — acum va trece

### Dacă apare eroarea "lipsesc drepturi de Administrator" (Windows)

Nu e o problemă critică. Continuă — Windows va afișa câte un popup UAC pentru fiecare pachet instalat (3-4 popup-uri în total). Acceptă-le pe fiecare când apar.

---

## Pasul 3 — Rulează wizardul de instalare

**Mac / Linux:**
```bash
bash nova-init.sh
```

**Windows (PowerShell):**
```powershell
.\nova-init.ps1
```

Wizardul are 4 pași. Ghidează utilizatorul la fiecare:

### Pasul 1 din 4 — Runtime

```
1) OpenAI Codex   — abonament ChatGPT Plus/Pro
2) Claude Code    — abonament Anthropic Pro/Max
```

Întreabă utilizatorul ce abonament are și spune-i ce să tasteze.

### Pasul 2 din 4 — Canal de control

```
1) Telegram
2) Slack
```

Dacă alege Telegram, continuă la pasul 3 — Telegram.
Dacă alege Slack, continuă la pasul 3 — Slack (ghid detaliat mai jos).

### Pasul 3 din 4 — Nume workspace

Utilizatorul tastează un nume simplu (ex: `dan`, `alex`). Litere mici, fără spații.

### Pasul 4 din 4 — Credențiale canal

Wizardul cere credențialele canalului ales. Vezi ghidurile de mai jos.

---

## Ghid complet Slack — de la cont nou la primul mesaj cu Boss

Parcurge acești pași cu utilizatorul **înainte** să introduci credențialele în wizard. Wizardul va sta și aștepte.

### 1. Creează cont Slack (dacă nu are)

1. Mergi la [slack.com](https://slack.com)
2. Click **Get started for free**
3. Introdu adresa de email și urmează pașii
4. Confirmă emailul

### 2. Creează un workspace nou

Dacă utilizatorul nu are deja un workspace Slack:

1. După logare, click **Create a new workspace**
2. Introdu numele companiei sau proiectului (ex: `Nova AI`)
3. Sari peste invitarea colegilor (click **Skip this step**)
4. Workspace-ul e gata

### 3. Creează app-ul Boss din manifest

1. Deschide [api.slack.com/apps](https://api.slack.com/apps) (rămâi logat cu același cont)
2. Click **Create New App**
3. Alege **From a manifest**
4. Selectează workspace-ul tocmai creat
5. Șterge tot ce e în câmpul de JSON și copiază în locul lui **manifestul Boss** de mai jos:

```json
{
  "display_information": {
    "name": "Nova Cortex Boss",
    "description": "Chief of staff — coordonează echipa AI și raportează zilnic",
    "background_color": "#1a1a2e"
  },
  "features": {
    "app_home": {
      "home_tab_enabled": false,
      "messages_tab_enabled": true,
      "messages_tab_read_only_enabled": false
    },
    "bot_user": {
      "display_name": "Nova Cortex Boss",
      "always_online": true
    }
  },
  "oauth_config": {
    "scopes": {
      "bot": [
        "app_mentions:read",
        "channels:history",
        "chat:write",
        "files:read",
        "im:history",
        "im:read"
      ]
    }
  },
  "settings": {
    "event_subscriptions": {
      "bot_events": [
        "app_mention",
        "message.channels",
        "message.im"
      ]
    },
    "interactivity": {
      "is_enabled": false
    },
    "org_deploy_enabled": false,
    "socket_mode_enabled": true,
    "token_rotation_enabled": false
  }
}
```

6. Click **Next** → **Create**

### 4. Generează App-Level Token (xapp-)

Acesta permite conexiunea Socket Mode — Boss primește mesaje în timp real fără server public.

1. Rămâi în pagina app-ului tocmai creat
2. Click pe **Basic Information** din meniul stâng
3. Derulează în jos până la secțiunea **App-Level Tokens**
4. Click **Generate Token and Scopes**
5. Name: `nova-boss-socket`
6. Click **Add Scope** și alege `connections:write`
7. Click **Generate**
8. Copiază token-ul care începe cu `xapp-` — acesta este `SLACK_APP_TOKEN`

### 5. Instalează app-ul în workspace și ia Bot Token (xoxb-)

1. Click pe **OAuth & Permissions** din meniul stâng
2. Click **Install to Workspace**
3. Click **Allow**
4. Copiază **Bot User OAuth Token** care începe cu `xoxb-` — acesta este `SLACK_BOT_TOKEN`

### 6. Creează un canal dedicat Boss și ia Channel ID

1. Deschide Slack (aplicația sau browser)
2. În bara stângă, click pe **+** lângă **Channels**
3. Click **Create a channel**
4. Nume: `nova-boss` (sau orice nume preferi)
5. Click **Create** (poate fi privat sau public — nu contează)
6. Invită app-ul în canal: tastează `/invite @Nova Cortex Boss` și apasă Enter
7. Acceptă confirmarea

**Cum găsești Channel ID:**
- Click pe numele canalului `#nova-boss` din bara stângă
- Se deschide un panou sau un modal — derulează în jos (sau click **About**)
- Channel ID-ul arată ca `C08XXXXXXXX` — copiază-l

**Cum găsești propriul User ID:**
- Click pe poza ta de profil din colțul din dreapta sus
- Click pe numele tău, apoi pe cele trei puncte (**More**)
- Click **Copy member ID**
- Arată ca `U0B3R6QL745` — copiază-l

### 7. Introdu credențialele în wizard

Revino în terminal — wizardul așteaptă. Introdu pe rând:

```
→ SLACK_BOT_TOKEN (xoxb-...): [paste xoxb-]
→ SLACK_APP_TOKEN (xapp-...): [paste xapp-]
→ SLACK_CHANNEL_ID canal dedicat (ex: C123ABC): [paste C...]
→ SLACK_ALLOWED_USER ID-ul tău Slack (ex: U123...): [paste U...]
```

Pe Windows wizardul afișează aceleași patru câmpuri, dar cu etichete scurte
(`Bot Token (xoxb-...)`, `App Token pentru Socket Mode (xapp-...)`, `Channel ID (C...)`,
`User ID al tău (U...)`), fiecare urmată de un prompt `→`. Ordinea e identică.

Toate patru sunt obligatorii. Wizardul se oprește cu eroare dacă lași vreunul gol
sau dacă prefixul nu e cel așteptat. `SLACK_ALLOWED_USER` nu se poate sări: fără el,
motorul cortextOS refuză pornirea ascultătorului Slack (altfel oricine ar putea comanda
agentul dintr-un mesaj).

Wizardul finalizează instalarea și pornește Boss automat.

### 8. Primul mesaj cu Boss

1. Deschide Slack
2. Mergi în canalul `#nova-boss`
3. Trimite orice mesaj (ex: `salut`)
4. Boss ar trebui să răspundă în câteva secunde

Dacă Boss nu răspunde în 30 de secunde, verifică logurile:

```bash
pm2 logs
```

---

## Ghid Telegram (alternativa mai simplă)

### 1. Creează bot prin BotFather

1. Deschide Telegram și caută `@BotFather`
2. Trimite `/newbot`
3. Alege un nume afișat (ex: `Nova Boss`)
4. Alege un username care se termină în `bot` (ex: `nova_boss_dan_bot`)
5. BotFather îți trimite un token — arată ca `123456789:AAxxxxxxxxxx`
6. Copiază token-ul

### 2. Introdu token-ul în wizard

Wizardul cere token-ul, îl validează și face automat handshake-ul.

### 3. Trimite primul mesaj la bot

Wizardul te va ghida: deschide bot-ul în Telegram (caută username-ul), trimite `/start` și apoi un mesaj simplu. Wizardul capturează automat ID-ul tău și finalizează configurarea.

---

## Verificare finală

După instalare, verifică starea fără a expune secrete:

```bash
cortextos bus list-agents
```

Ar trebui să apară `boss` cu status `online`.

Dacă ceva nu merge, păstrează codul de refuz și căile afișate. Nu cere tokenuri, `.env`, dump-uri PM2 brute sau mediul complet al proceselor în chat. Pentru recuperare, urmează `docs/safe-engine-installer.md`; nu porni direct `cortextos start boss`, nu rula `pm2 save` direct și nu aplica reset/clean/stash automat.

Pentru diagnostic local:

```bash
pm2 logs          # loguri live ale agenților
pm2 status        # starea proceselor
```

---

## Note pentru re-rulare

O reluare nu este declarată idempotentă. `prepare` refuză modificări Git tracked sau untracked, inclusiv template-uri copiate de wizard, și nu mută/șterge nimic automat. Separă codul actualizat de build-ul reușit și de runtime-ul pornit; datele existente nu sunt migrate. Pentru daemonul existent, helper-ul cere acord înainte de restart, iar pentru alte aplicații PM2 cere acord înainte de snapshotul global. `pm2 save` nu configurează singur pornirea Windows la boot.
