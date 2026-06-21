# Nova Cortex — Manifeste Slack pentru Boss + Analyst

Două manifeste gata de copiat pentru cele două app-uri Slack ale echipei tale de bază:
**Boss** (Orchestrator, chief of staff) și **Analyst** (partener analitic).

Diferențe față de instalarea cu o singură app:

- Fiecare agent are propria app Slack, propriul bot user, proprii token-uri
- Mai ușor de gestionat permisiuni separate pe canale
- Replicare 1:1 a flow-ului Telegram unde fiecare agent are propriul bot BotFather

---

## 1. Crearea primei app — Boss (Orchestrator)

1. Mergi la <https://api.slack.com/apps>
2. **Create New App** → **From a manifest**
3. Alege workspace-ul
4. Copiază tot blocul JSON de mai jos și paste-uiește-l în câmpul de manifest
5. **Next** → **Create**

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

### După Create

1. **Basic Information** → **App-Level Tokens** → **Generate Token and Scopes**
   - Name: `nova-boss-socket`
   - Scope: `connections:write`
   - **Generate** → copiază token-ul `xapp-...` (asta e `SLACK_APP_TOKEN` pentru Boss)
2. **OAuth & Permissions** → **Install to Workspace** → Allow
   - Copiază **Bot User OAuth Token** `xoxb-...` (asta e `SLACK_BOT_TOKEN` pentru Boss)
3. În Slack, creează un canal dedicat (ex: `#nova-boss`)
   - Invită app-ul: `/invite @Nova Cortex Boss`
   - Click pe numele canalului → **About** → copiază **Channel ID** `C...`

**Credențiale Boss de salvat:**

```text
SLACK_BOT_TOKEN_BOSS    = xoxb-...
SLACK_APP_TOKEN_BOSS    = xapp-...
SLACK_CHANNEL_ID_BOSS   = C...
```

---

## 2. Crearea celei de-a doua app — Analyst

Repeți pașii 1-5 de mai sus, dar cu manifestul de mai jos:

```json
{
  "display_information": {
    "name": "Nova Cortex Analyst",
    "description": "Partenerul analitic al Boss-ului — monitorizează KPI, detectează anomalii",
    "background_color": "#2d1b4e"
  },
  "features": {
    "app_home": {
      "home_tab_enabled": false,
      "messages_tab_enabled": true,
      "messages_tab_read_only_enabled": false
    },
    "bot_user": {
      "display_name": "Nova Cortex Analyst",
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

### După Create

1. **App-Level Tokens** → `nova-analyst-socket` cu `connections:write` → copiază `xapp-...`
2. **Install to Workspace** → copiază `xoxb-...`
3. Canal dedicat Analyst (ex: `#nova-analyst`)
   - Invită: `/invite @Nova Cortex Analyst`
   - Copiază Channel ID

**Credențiale Analyst de salvat:**

```text
SLACK_BOT_TOKEN_ANALYST    = xoxb-...
SLACK_APP_TOKEN_ANALYST    = xapp-...
SLACK_CHANNEL_ID_ANALYST   = C...
```

---

## 3. Folosirea credențialelor în wizard

### La `nova-init.ps1` (Filmarea 1 — Boss)

Wizard-ul te întreabă credențialele pentru Boss. Paste-uiești pe rând:

| Prompt | Valoare |
|---|---|
| Bot Token | `SLACK_BOT_TOKEN_BOSS` |
| App Token Socket Mode | `SLACK_APP_TOKEN_BOSS` |
| Channel ID | `SLACK_CHANNEL_ID_BOSS` |
| User ID | ID-ul tău Slack `U...` |

### În onboarding (Filmarea 2 — Analyst)

În chat-ul Slack cu Boss, scrii `/onboarding`. La pasul unde Boss spawn-uiește Analyst-ul, ai nevoie de credențialele Analyst pe care le-ai salvat mai sus.

Pe Slack, instalările noi folosesc integrarea nativă cortextOS. Boss va scrie credențialele Slack ale Analyst-ului în `.env`-ul lui și îl va porni fără să duplice `slack-bridge`.

---

## 4. Tips pentru filmare

- Cele două app-uri pot rula în același workspace Slack, dar e mai curat dacă au **canale separate** (`#nova-boss` și `#nova-analyst`)
- `background_color` diferit între cele două manifeste — `#1a1a2e` (Boss, mai întunecat) vs `#2d1b4e` (Analyst, mov) — ca să le distingi vizual în Slack
- Salvează ambele seturi de credențiale într-un singur notepad înainte de filmare ca să nu cauți printre tab-uri când wizard-ul cere

---

## 5. Checklist înainte de filmare

- [ ] App **Nova Cortex Boss** creată din manifest
- [ ] `SLACK_BOT_TOKEN_BOSS` (xoxb-) copiat
- [ ] `SLACK_APP_TOKEN_BOSS` (xapp-) copiat
- [ ] `SLACK_CHANNEL_ID_BOSS` (C...) copiat
- [ ] Boss invitat în canalul lui
- [ ] App **Nova Cortex Analyst** creată din manifest
- [ ] `SLACK_BOT_TOKEN_ANALYST` (xoxb-) copiat
- [ ] `SLACK_APP_TOKEN_ANALYST` (xapp-) copiat
- [ ] `SLACK_CHANNEL_ID_ANALYST` (C...) copiat
- [ ] Analyst invitat în canalul lui
- [ ] Toate cele 6 valori salvate într-un notepad accesibil
