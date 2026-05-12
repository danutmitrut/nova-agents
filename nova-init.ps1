# nova-init.ps1 — Configurează primii tăi agenți Nova Cortex (Windows nativ).
#
# Rulează verificarea de prereq (nova-prereq.ps1) dacă cortextOS lipsește, apoi
# ghidează utilizatorul prin setup-ul Nova Cortex:
#   - Alege un nume de workspace (org)
#   - Conectează bot-ul Telegram pentru Nova Cortex Orchestrator
#   - Handshake Telegram pentru a obține chat_id + allowed_user
#   - Pornește Orchestratorul (Analystul vine online în /onboarding)
#
# Pe Mac/Linux nativ foloseste nova-init.sh în loc.

$ErrorActionPreference = 'Stop'

# ─── Helper-i de output branded ─────────────────────────────────────────
function Nova-Say($msg)  { Write-Host "▸ $msg" -ForegroundColor Magenta }
function Nova-Ok($msg)   { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Nova-Warn($msg) { Write-Host "  ! $msg" -ForegroundColor Yellow }
function Nova-Fail($msg) { Write-Host "  ✗ $msg" -ForegroundColor Red; exit 1 }
function Nova-Step($msg) { Write-Host ""; Write-Host "─── $msg ───" -ForegroundColor Cyan }
function Nova-Dim($msg)  { Write-Host "    $msg" -ForegroundColor DarkGray }

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

# ─── Refuză WSL2 ────────────────────────────────────────────────────────
if (Test-Path '/proc/version' -ErrorAction SilentlyContinue) {
  $procVersion = Get-Content '/proc/version' -ErrorAction SilentlyContinue
  if ($procVersion -match 'microsoft|WSL') {
    Nova-Fail "Detectez WSL2. Foloseste varianta bash: bash nova-init.sh"
  }
}

# ─── Ecran de bun venit ────────────────────────────────────────────────
Clear-Host
Write-Host @'
   ███╗   ██╗ ██████╗ ██╗   ██╗ █████╗      ██████╗ ██████╗ ██████╗ ████████╗███████╗██╗  ██╗
   ████╗  ██║██╔═══██╗██║   ██║██╔══██╗    ██╔════╝██╔═══██╗██╔══██╗╚══██╔══╝██╔════╝╚██╗██╔╝
   ██╔██╗ ██║██║   ██║██║   ██║███████║    ██║     ██║   ██║██████╔╝   ██║   █████╗   ╚███╔╝
   ██║╚██╗██║██║   ██║╚██╗ ██╔╝██╔══██║    ██║     ██║   ██║██╔══██╗   ██║   ██╔══╝   ██╔██╗
   ██║ ╚████║╚██████╔╝ ╚████╔╝ ██║  ██║    ╚██████╗╚██████╔╝██║  ██║   ██║   ███████╗██╔╝ ██╗
   ╚═╝  ╚═══╝ ╚═════╝   ╚═══╝  ╚═╝  ╚═╝     ╚═════╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝
'@ -ForegroundColor Magenta
Write-Host ""
Write-Host "  Bun venit în Nova Cortex" -ForegroundColor White
Write-Host "  Forța de muncă AI multi-agent pentru business-ul tău" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Powered by cortextOS engine" -ForegroundColor DarkGray
Write-Host ""

# ─── Rulează prereq dacă cortextOS lipsește ────────────────────────────
if (-not (Get-Command cortextos -ErrorAction SilentlyContinue)) {
  Nova-Say "Întâi ne asigurăm că toolbox-ul tău e gata..."
  $prereqScript = Join-Path $SCRIPT_DIR 'nova-prereq.ps1'
  if (Test-Path $prereqScript) {
    & $prereqScript
  } else {
    Nova-Fail "cortextOS nu e instalat și nova-prereq.ps1 nu e lângă acest script. Rulează nova-prereq.ps1 manual întâi."
  }
}

# ─── Wizard ──────────────────────────────────────────────────────────────
Nova-Step "Configurăm workspace-ul tău Nova Cortex"

# Pasul 1: nume workspace
Write-Host ""
Write-Host "Pasul 1 din 3: Care e numele tău?" -ForegroundColor White
Nova-Dim "Folosit ca etichetă pentru workspace-ul tău privat (ex: `"nova-dan`"). Litere mici, fără spații."
# Bash echivalent (`tr -cd 'a-z0-9-'`) sterge caracterele invalide, nu le inlocuieste.
# Match exact ca varianta sh: 'Dan Mitruț' -> 'danmitru' pe ambele OS-uri.
$NOVA_USER = (Read-Host "  →").ToLower() -replace '[^a-z0-9-]', ''
if ([string]::IsNullOrEmpty($NOVA_USER)) {
  Nova-Fail "Numele e obligatoriu. Reia nova-init.ps1."
}
$ORG = "nova-$NOVA_USER"
Nova-Ok "Nume workspace: $ORG"

# Pasul 2: bot token
Write-Host ""
Write-Host "Pasul 2 din 3: Tokenul de bot Telegram pentru Nova Cortex Orchestrator" -ForegroundColor White
Nova-Dim "Dacă nu ai unul: deschide Telegram, scrie la @BotFather, trimite /newbot, urmează pașii."
Nova-Dim "BotFather îți va da un token care arată ca 123456:AAxxxxxxxxxxxx — paste-uiește-l mai jos."
Nova-Dim "Vei avea nevoie de un AL DOILEA token mai târziu pentru Analyst — Orchestratorul ți-l va cere în /onboarding."
$BOT_TOKEN = Read-Host "  →"
if ($BOT_TOKEN -notmatch '^\d+:[A-Za-z0-9_-]+$') {
  Nova-Fail "Acela nu pare un token valid de bot Telegram. Format așteptat: 123456:AAxx... Reia nova-init.ps1."
}
Nova-Ok "Token capturat (se salvează local, nu se share-uiește niciodată)."

# Pasul 3: Telegram handshake (CHAT_ID + ALLOWED_USER)
Write-Host ""
Write-Host "Pasul 3 din 3: Deschide bot-ul în Telegram" -ForegroundColor White
Nova-Dim "Bot-ul tău are deja tokenul. Pe Telegram caută numele lui (cel pe care l-ai dat la BotFather)."
Nova-Dim "Trimite-i /start, apoi orice mesaj (ex: `"salut`"). Apoi întoarce-te aici și apasă Enter."
Read-Host "  → Apasă Enter când ai trimis mesajul..."

Nova-Say "Caut mesajul tău în coada bot-ului..."
$telegramUrl = "https://api.telegram.org/bot$BOT_TOKEN/getUpdates"
$CHAT_ID = $null
$USER_ID = $null

# Filtreaza la ultimul update care contine un .message (nu callback query, edited
# message, channel post, etc) — pe acestea nu putem citi chat/from in mod uniform.
function Get-LastMessageFromUpdates {
  param($result)
  $msgUpdates = @($result | Where-Object { $_.message -and $_.message.chat -and $_.message.from })
  if ($msgUpdates.Count -gt 0) { $msgUpdates[-1].message } else { $null }
}

try {
  $response = Invoke-RestMethod -Uri $telegramUrl -TimeoutSec 10
  if ($response.ok) {
    $lastMsg = Get-LastMessageFromUpdates $response.result
    if ($lastMsg) { $CHAT_ID = $lastMsg.chat.id; $USER_ID = $lastMsg.from.id }
  }
} catch {
  Nova-Warn "getUpdates a esuat: $($_.Exception.Message)"
}

# Retry o data daca prima incercare a esuat
if (-not $CHAT_ID) {
  Nova-Warn "Nu am gasit mesaj. Verifica ca ai trimis /start si apoi un mesaj PLAIN (nu apasari de butoane) la bot."
  Read-Host "  → Reincearca acum (Enter)..."
  try {
    $response = Invoke-RestMethod -Uri $telegramUrl -TimeoutSec 10
    if ($response.ok) {
      $lastMsg = Get-LastMessageFromUpdates $response.result
      if ($lastMsg) { $CHAT_ID = $lastMsg.chat.id; $USER_ID = $lastMsg.from.id }
    }
  } catch {
    Nova-Warn "getUpdates a esuat a doua oara: $($_.Exception.Message)"
  }
}

if (-not $CHAT_ID -or -not $USER_ID) {
  Nova-Fail "Tot nu am putut citi mesajul din coada bot-ului. Verifica tokenul si retrimite mesajul. Reia nova-init.ps1."
}
Nova-Ok "Bot conectat (chat $CHAT_ID)"

# ─── Instalează template-urile Nova Cortex în directorul cortextOS ─────
Nova-Step "Instalez template-urile de agenți Nova Cortex"

$CORTEXTOS_HOME = if ($env:CORTEXTOS_DIR) { $env:CORTEXTOS_DIR } else { Join-Path $env:USERPROFILE 'cortextos' }
$CORTEXTOS_TEMPLATES = Join-Path $CORTEXTOS_HOME 'templates'
if (-not (Test-Path $CORTEXTOS_TEMPLATES)) {
  Nova-Fail "Directorul template-urilor cortextOS nu există la $CORTEXTOS_TEMPLATES — instalarea poate fi incompletă. Rulează 'cortextos doctor'."
}

$NOVA_TEMPLATES_SRC = Join-Path $SCRIPT_DIR 'templates'
if (-not (Test-Path $NOVA_TEMPLATES_SRC)) {
  Nova-Fail "Template-urile Nova Cortex lipsesc de la $NOVA_TEMPLATES_SRC — re-cloneaza repo-ul nova-agents."
}

Get-ChildItem -Path $NOVA_TEMPLATES_SRC -Directory -Filter 'nova-cortex-*' | ForEach-Object {
  $tmplName = $_.Name
  $destPath = Join-Path $CORTEXTOS_TEMPLATES $tmplName
  if (Test-Path $destPath) {
    Remove-Item -Recurse -Force $destPath
  }
  Copy-Item -Recurse $_.FullName $CORTEXTOS_TEMPLATES
  Nova-Ok "Template instalat: $tmplName"
}

# ─── Rulează comenzile cortextOS cu narațiune branded ──────────────────
Nova-Step "Construiesc echipa ta Nova Cortex"

# cortextos init/add-agent foloseste process.cwd() ca projectRoot. cd-uim
# explicit si exportam CTX_FRAMEWORK_ROOT ca sa fortam locul corect.
$env:CTX_FRAMEWORK_ROOT = $CORTEXTOS_HOME
Push-Location $CORTEXTOS_HOME

try {
  Nova-Say "Creez workspace-ul..."
  cortextos init $ORG *> $null
  if ($LASTEXITCODE -ne 0) { Nova-Fail "Nu am putut crea workspace-ul. Rulează 'cortextos doctor' pentru diagnostic." }
  Nova-Ok "Workspace `"$ORG`" gata"

  Nova-Say "Pornesc Nova Cortex Orchestrator (chief of staff-ul tău)..."
  cortextos add-agent boss --template nova-cortex-orchestrator --org $ORG *> $null
  if ($LASTEXITCODE -ne 0) { Nova-Fail "Template-ul Orchestrator nu există la $CORTEXTOS_TEMPLATES\nova-cortex-orchestrator\. Pasul de copiere template-uri probabil a eșuat — re-rulează scriptul." }
  Nova-Ok "Nova Cortex Orchestrator creat"
} finally {
  Pop-Location
}

# ─── Scrie .env-ul agentului ───────────────────────────────────────────
Nova-Say "Conectez Telegram pentru Orchestratorul tău..."
$AGENT_ENV = Join-Path $CORTEXTOS_HOME "orgs\$ORG\agents\boss\.env"
if (Test-Path $AGENT_ENV) {
  # Upsert BOT_TOKEN, CHAT_ID, ALLOWED_USER
  $envContent = Get-Content $AGENT_ENV -Raw
  $upsert = {
    param($content, $key, $value)
    if ($content -match "(?m)^${key}=.*$") {
      $content -replace "(?m)^${key}=.*$", "${key}=$value"
    } else {
      $content.TrimEnd() + "`n${key}=$value`n"
    }
  }
  $envContent = & $upsert $envContent 'BOT_TOKEN' $BOT_TOKEN
  $envContent = & $upsert $envContent 'CHAT_ID' $CHAT_ID
  $envContent = & $upsert $envContent 'ALLOWED_USER' $USER_ID
  Set-Content -Path $AGENT_ENV -Value $envContent -Encoding UTF8 -NoNewline

  # Restrict access: scoatem ACE-urile pentru BUILTIN\Users si Everyone, dar pastram
  # inheritance + SYSTEM/Administrators (necesare pentru cortextos doctor / admin tools).
  # Bash echivalent face `chmod 600` care lasa doar owner — analogul Windows e sa scoatem
  # accesul pentru orice "user generic" dar sa pastram suportul de sistem.
  try {
    $acl = Get-Acl $AGENT_ENV
    $rulesToRemove = $acl.Access | Where-Object {
      $_.IdentityReference.Value -match '(BUILTIN\\Users|Everyone|NT AUTHORITY\\Authenticated Users)'
    }
    foreach ($r in $rulesToRemove) { [void]$acl.RemoveAccessRule($r) }
    if ($rulesToRemove) { Set-Acl -Path $AGENT_ENV -AclObject $acl }
  } catch {
    Nova-Warn "Nu am putut restringe permisiunile pe .env: $($_.Exception.Message). Continua, dar verifica manual."
  }

  Nova-Ok "Token + chat ID + allowed user salvate (local)"
} else {
  Nova-Warn "Fișierul .env al agentului nu există la calea așteptată — deschide dashboard-ul ca să configurezi Telegram manual."
}

# ─── Pornește Orchestratorul ──────────────────────────────────────────
Nova-Step "Pornesc Orchestratorul tău"
Push-Location $CORTEXTOS_HOME
try {
  Nova-Say "Pornesc daemon-ul + boss..."
  cortextos start boss *> $null
  if ($LASTEXITCODE -eq 0) {
    Nova-Ok "Boss e online — gata să vorbească pe Telegram"
  } else {
    Nova-Warn "Auto-start a eșuat. Pornește manual: cd $CORTEXTOS_HOME; cortextos start boss"
  }
} finally {
  Pop-Location
}

# ─── Ecran final ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╭────────────────────────────────────────────────╮" -ForegroundColor Magenta
Write-Host "│  Nova Cortex e gata.                           │" -ForegroundColor Magenta
Write-Host "╰────────────────────────────────────────────────╯" -ForegroundColor Magenta
Write-Host ""
Write-Host "Următorii pași:" -ForegroundColor White
Write-Host ""
Write-Host "  1. Deschide Telegram și găsește botul pe care tocmai l-ai conectat."
Write-Host "     Trimite-i orice mesaj (ex: `"salut`") ca să-ți rețină chat-ul."
Write-Host ""
Write-Host "  2. Trimite Orchestratorului această comandă ca să termine setup-ul:"
Write-Host "       /onboarding" -ForegroundColor Cyan
Write-Host ""
Write-Host "     Te va ghida prin identitate, program de lucru, reguli de autonomie,"
Write-Host "     apoi îți va cere un AL DOILEA token BotFather ca să aducă Analystul online."
Write-Host ""
Write-Host "  3. După ce Analystul e online, Orchestratorul tău te poate ajuta să adaugi"
Write-Host "     agenți specialiști (CFO, marketer, ops, research — tu alegi)."
Write-Host ""
Write-Host "  Pentru a reporni Orchestratorul oricând: cd $CORTEXTOS_HOME; cortextos start boss" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Workspace: $ORG  •  motorul cortextOS rulează local pe această mașină." -ForegroundColor DarkGray
Write-Host ""
