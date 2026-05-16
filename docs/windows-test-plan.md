# Nova Cortex Windows Test Plan

Acest ghid este protocolul complet pentru testarea Nova Cortex pe o masina Windows reala.

Scopul testului nu este doar sa vedem daca porneste, ci sa validam daca Windows poate deveni ruta oficiala pentru curs sau ramane doar masina de lucru care se conecteaza la un server Ubuntu.

## Obiectiv

Trebuie sa validam trei decizii pe Windows:

1. Runtime agenti: Codex/OpenAI sau Claude Code
2. Loc instalare: Windows local sau server Ubuntu accesat din Windows
3. Canal control: Telegram sau Slack

Rezultatul dorit:

- Orchestrator `boss` online
- Analyst creat si online
- mesajele ajung din Telegram sau Slack la agent
- agentul raspunde inapoi in acelasi canal
- PM2 tine procesele online
- fisierele Slack, daca alegem Slack, ajung la agent ca `local_file`

## Rutele Pe Care Le Testam

### Ruta A: Windows ca masina de lucru, agentii pe server Ubuntu

Aceasta este ruta recomandata pentru curs, chiar daca studentul are laptop Windows.

Windows este folosit pentru:

- browser
- Slack/Telegram
- terminal SSH
- Codex Desktop / editor / GitHub

Agentii ruleaza pe:

- Hetzner / Ubuntu
- user Linux `nova`
- PM2 pe server

Aceasta ruta trebuie sa fie prima validata, pentru ca standardizeaza mediul tuturor cursantilor.

### Ruta B: Windows local

Aceasta este ruta care trebuie testata separat.

Agentii ruleaza direct pe Windows, cu PowerShell nativ.

Trebuie validat:

- Node.js
- npm
- jq
- Python / build tools, daca sunt cerute
- Codex CLI
- Claude Code CLI
- cortextOS
- PM2
- Telegram
- Slack bridge
- path-uri Windows
- procese persistente dupa restart

Pana cand testul este complet, ruta B ramane experimentala.

## Cerinte Pentru Masina Windows

Ideal:

- Windows 11
- PowerShell 5.1 sau PowerShell 7
- acces Administrator
- browser instalat
- Git instalat sau instalabil
- cont GitHub
- cont OpenAI/ChatGPT pentru Codex
- optional cont Claude pentru Claude Code
- Telegram Desktop sau telefon cu Telegram
- Slack desktop/browser

Nu folosim WSL pentru ruta Windows local.

Motiv: vrem sa stim daca flow-ul merge nativ in PowerShell. WSL este practic ruta Linux, dar cu alte probleme de path/PTY.

## Pregatire Inainte De Test

Pe Windows, deschide:

```text
PowerShell as Administrator
```

Verifica versiuni:

```powershell
$PSVersionTable
where.exe git
where.exe node
where.exe npm
where.exe codex
where.exe claude
where.exe pm2
where.exe jq
```

Noteaza ce exista deja si ce lipseste.

## Test 1: Windows → Server Ubuntu

Acesta este testul prioritar pentru curs.

### 1. SSH din Windows catre server

In PowerShell:

```powershell
ssh root@IP_SERVER_CURSANT
```

Daca cere confirmare:

```text
Are you sure you want to continue connecting?
```

raspunde:

```text
yes
```

Daca autentificarea prin parola este dezactivata si cere cheie publica, avem doua variante:

1. adaugam cheia publica Windows in server
2. folosim consola Hetzner pentru setup initial

Comanda pentru generat cheie pe Windows:

```powershell
ssh-keygen -t ed25519 -C "student-windows"
type $env:USERPROFILE\.ssh\id_ed25519.pub
```

Cheia publica se adauga pe server in:

```bash
/root/.ssh/authorized_keys
```

sau in:

```bash
/home/nova/.ssh/authorized_keys
```

in functie de userul folosit.

### 2. Creeaza userul nova pe server

Pe server:

```bash
adduser nova
usermod -aG sudo nova
mkdir -p /opt/nova-agents
chown -R nova:nova /opt/nova-agents
```

Intra ca `nova`:

```bash
su - nova
```

### 3. Cloneaza repo-ul pe server

```bash
cd /opt
git clone https://github.com/danutmitrut/nova-agents.git
cd /opt/nova-agents
```

Daca repo-ul exista deja:

```bash
cd /opt/nova-agents
git pull
```

### 4. Alege runtime

Pentru ruta recomandata:

```bash
NOVA_AGENT_RUNTIME=codex bash nova-prereq.sh
```

Daca scriptul cere autentificare:

```bash
codex
```

Login in browser, apoi:

```text
/exit
```

Reia:

```bash
NOVA_AGENT_RUNTIME=codex bash nova-prereq.sh
```

### 5. Alege canal

Pentru Telegram:

```bash
NOVA_AGENT_RUNTIME=codex bash nova-init.sh
```

Alege:

```text
Telegram
```

Pentru Slack:

```bash
NOVA_AGENT_RUNTIME=codex bash nova-init.sh
```

Alege:

```text
Slack
```

Completeaza token-urile si Channel ID.

### 6. Verificare server

```bash
pm2 list
```

Pentru Telegram trebuie:

```text
cortextos-daemon online
```

Pentru Slack trebuie:

```text
cortextos-daemon online
nova-slack-bridge online
```

Test:

- Telegram: trimite `salut`
- Slack: scrie `salut` in canalul dedicat, fara `@`

Porneste:

```text
/onboarding
```

## Test 2: Windows Local Cu Codex

Acesta valideaza daca putem sustine instalare locala Windows.

### 1. PowerShell Administrator

Deschide:

```text
PowerShell as Administrator
```

Cloneaza repo:

```powershell
cd $env:USERPROFILE
git clone https://github.com/danutmitrut/nova-agents.git
cd nova-agents
```

### 2. Ruleaza prereq Windows

```powershell
.\nova-prereq.ps1
```

Noteaza:

- ce instaleaza
- ce cere manual
- daca cere restart
- daca apar erori de PATH
- daca PM2 se instaleaza global

### 3. Verifica toolchain

Inchide si redeschide PowerShell dupa instalare.

```powershell
node -v
npm -v
pm2 -v
codex --version
cortextos --version
jq --version
```

### 4. Autentifica Codex

```powershell
codex
```

Fa login in browser.

Iesi:

```text
/exit
```

### 5. Ruleaza init

Ideal, ruta noua ar trebui sa fie:

```powershell
$env:NOVA_AGENT_RUNTIME="codex"
.\nova-init.ps1
```

Daca `nova-init.ps1` nu are inca runtime Codex/Slack, acesta este bug de paritate cu Linux si trebuie reparat.

Noteaza exact:

- intreaba runtime sau nu?
- are optiune Slack sau doar Telegram?
- creeaza template Codex sau Claude?
- porneste `cortextos-daemon`?
- unde scrie workspace-ul?

### 6. Verificare PM2

```powershell
pm2 list
pm2 logs cortextos-daemon --lines 80
```

Test Telegram/Slack dupa caz.

## Test 3: Windows Local Cu Claude Code

Aceasta ruta este pentru compatibilitate.

### 1. Autentifica Claude

```powershell
claude
```

Login cu metoda disponibila.

### 2. Ruleaza init

```powershell
$env:NOVA_AGENT_RUNTIME="claude"
.\nova-init.ps1
```

Noteaza daca:

- porneste fara wizard-uri blocate
- cere trust folder
- cere permisiuni
- poate rula sub PM2
- raspunde in Telegram/Slack

## Test 4: Slack Pe Windows Local

Acesta este test separat pentru bridge.

### 1. Verifica Slack App

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

Socket Mode:

```text
ON
```

App-level token:

```text
xapp-...
```

Dupa orice modificare:

```text
Reinstall to Workspace
```

### 2. Verifica `.env`

Pe Windows, path-urile trebuie validate. Daca bridge-ul foloseste `HOME`, `join`, `os.homedir()`, ar trebui sa functioneze, dar trebuie testat cu fisiere reale.

Fisier asteptat:

```text
slack-bridge\.env
```

Chei:

```text
SLACK_BOT_TOKEN=xoxb-...
SLACK_APP_TOKEN=xapp-...
CTX_ORG=nova-danut
NOVA_TARGET_AGENT=boss
NOVA_BRIDGE_AGENT=slack
SLACK_ALLOWED_USER=U...
SLACK_DEFAULT_CHANNEL=C...
SLACK_LISTEN_CHANNELS=C...
SLACK_MAX_FILE_BYTES=104857600
```

Atentie la:

- backslash vs slash
- spatii in path
- permisiuni de scriere
- fisiere media descarcate

### 3. Pornire manuala bridge

```powershell
cd .\slack-bridge
npm install
npm start
```

Daca merge manual, porneste prin PM2:

```powershell
pm2 delete nova-slack-bridge
pm2 start npm --name nova-slack-bridge -- start
pm2 save
pm2 list
```

### 4. Test Slack

In canalul dedicat:

```text
salut
```

Comportament corect:

- raspuns direct in canal
- fara `@`
- fara ACK intermediar
- fara mesaj ca `slack` lipseste din roster

Trimite apoi:

- imagine
- PDF
- audio/video scurt

Verifica daca agentul primeste `local_file:`.

## Probleme De Urmarit

### PATH

Windows poate instala global npm packages, dar PowerShell-ul curent sa nu le vada pana la restart.

Comenzi:

```powershell
where.exe cortextos
where.exe pm2
where.exe codex
where.exe claude
```

### Permisiuni Administrator

`nova-prereq.ps1` poate avea nevoie de Administrator pentru:

- winget
- Visual Studio Build Tools
- jq
- Python
- Node.js

Dupa prereq, init ar trebui sa poata rula fara Administrator. Trebuie testat.

### Execution Policy

Daca PowerShell blocheaza scriptul:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

### PM2 Persistenta

PM2 pe Windows nu are acelasi model de startup ca Linux.

Trebuie testat:

```powershell
pm2 save
pm2 resurrect
```

si ce se intampla dupa restart Windows.

### Path-uri Cu Spatii

Testam instalarea in:

```text
C:\Users\<user>\nova-agents
```

si evitam initial:

```text
Desktop
Documents\Foldere Cu Spatii
OneDrive
```

OneDrive poate introduce lock/sync issues.

### Browser Login

Codex si Claude pot deschide browser-ul diferit pe Windows.

Trebuie notat:

- se deschide automat browser-ul?
- codul de device login apare corect?
- revine CLI-ul dupa login?

## Matrice De Test

| Ruta | Runtime | Locatie | Canal | Status |
|---|---|---|---|---|
| A1 | Codex | Server Ubuntu din Windows SSH | Telegram | De testat |
| A2 | Codex | Server Ubuntu din Windows SSH | Slack | De testat |
| A3 | Claude | Server Ubuntu din Windows SSH | Telegram | Optional |
| A4 | Claude | Server Ubuntu din Windows SSH | Slack | Optional |
| B1 | Codex | Windows local | Telegram | De testat |
| B2 | Codex | Windows local | Slack | De testat |
| B3 | Claude | Windows local | Telegram | Compatibilitate |
| B4 | Claude | Windows local | Slack | Compatibilitate |

Pentru curs, minimul acceptabil este:

```text
A1 si A2 functionale
```

Pentru suport Windows local oficial:

```text
B1 si B2 functionale
```

## Ce Inseamna Succes

O ruta este considerata functionala doar daca:

1. instalarea porneste din instructiuni curate
2. runtime-ul se autentifica pentru userul corect
3. `nova-init` creeaza Orchestratorul
4. PM2 arata procese online
5. canalul ales trimite mesaj la agent
6. agentul raspunde in canal
7. `/onboarding` porneste
8. Analystul poate fi creat
9. restartul procesului nu rupe configuratia

## Ce Trebuie Reparat Daca Pica

Daca Windows local pica, clasificam problema:

- script PowerShell incomplet fata de Linux
- runtime Codex/Claude neautentificat
- path Windows incompatibil
- PM2 Windows persistence
- Slack bridge path/media issue
- Telegram handshake issue
- cortextOS upstream issue pe Windows

Abia dupa clasificare decidem daca:

- reparam PowerShell
- recomandam doar server Ubuntu pentru curs
- marcam Windows local ca experimental

## Recomandare Provizorie Pentru Curs

Pana finalizam testul:

```text
Windows este suportat ca masina de lucru.
Agentii pentru curs ruleaza pe server Ubuntu.
Instalarea locala pe Windows este in testare.
```

Dupa ce validam B1 si B2, putem promova Windows local la ruta suportata oficial.
