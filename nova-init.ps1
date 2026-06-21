# nova-init.ps1 — Configurează primii tăi agenți Nova Cortex (Windows nativ).
#
# Rulează verificarea de prereq (nova-prereq.ps1) dacă cortextOS lipsește, apoi
# ghidează utilizatorul prin setup-ul Nova Cortex:
#   - Alege runtime: Claude Code sau OpenAI Codex
#   - Alege canal de control: Telegram sau Slack
#   - Alege un nume de workspace (org)
#   - Conectează canalul ales pentru Nova Cortex Orchestrator
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

# ─── Pasul 1: Runtime AI ─────────────────────────────────────────────
Write-Host "Pasul 1 din 4: Ce abonament AI folosești?" -ForegroundColor White
Write-Host ""
Write-Host "  1) OpenAI Codex   — ChatGPT Plus sau Pro" -ForegroundColor Gray
Write-Host "  2) Claude Code    — Anthropic Pro sau Max" -ForegroundColor Gray
Write-Host ""
$RUNTIME_CHOICE = Read-Host "  → Alege 1 sau 2 [1]"
if ([string]::IsNullOrEmpty($RUNTIME_CHOICE)) { $RUNTIME_CHOICE = '1' }
switch ($RUNTIME_CHOICE) {
  '1' { $NOVA_AGENT_RUNTIME = 'codex';  $CORTEXT_RUNTIME = 'codex-app-server'; $ORCH_TEMPLATE = 'nova-cortex-orchestrator-codex'; $ANALYST_TEMPLATE = 'nova-cortex-analyst-codex' }
  '2' { $NOVA_AGENT_RUNTIME = 'claude'; $CORTEXT_RUNTIME = 'claude-code';      $ORCH_TEMPLATE = 'nova-cortex-orchestrator';       $ANALYST_TEMPLATE = 'nova-cortex-analyst' }
  default { Nova-Fail "Alegere invalidă. Reia nova-init.ps1 și alege 1 sau 2." }
}
$env:NOVA_AGENT_RUNTIME = $NOVA_AGENT_RUNTIME
Nova-Ok "Runtime ales: $NOVA_AGENT_RUNTIME"

# ─── Pasul 2: Canal de control ────────────────────────────────────────
Write-Host ""
Write-Host "Pasul 2 din 4: Unde vrei să vorbești cu BOSS?" -ForegroundColor White
Write-Host ""
Write-Host "  1) Telegram   — bot privat, recomandat pentru uz personal" -ForegroundColor Gray
Write-Host "  2) Slack      — Socket Mode bridge, pentru echipe" -ForegroundColor Gray
Write-Host ""
$CHANNEL_CHOICE = Read-Host "  → Alege 1 sau 2 [1]"
if ([string]::IsNullOrEmpty($CHANNEL_CHOICE)) { $CHANNEL_CHOICE = '1' }
switch ($CHANNEL_CHOICE) {
  '1' { $NOVA_CONTROL_CHANNEL = 'telegram' }
  '2' { $NOVA_CONTROL_CHANNEL = 'slack' }
  default { Nova-Fail "Alegere invalidă. Reia nova-init.ps1 și alege 1 sau 2." }
}
Nova-Ok "Canal ales: $NOVA_CONTROL_CHANNEL"

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

# Pasul 3: nume workspace
Write-Host ""
Write-Host "Pasul 3 din 4: Care e numele tău?" -ForegroundColor White
Nova-Dim "Folosit ca etichetă pentru workspace-ul tău privat (ex: `"nova-dan`"). Litere mici, fără spații."
# Bash echivalent (`tr -cd 'a-z0-9-'`) sterge caracterele invalide, nu le inlocuieste.
# Match exact ca varianta sh: 'Dan Mitruț' -> 'danmitru' pe ambele OS-uri.
$NOVA_USER = (Read-Host "  →").ToLower() -replace '[^a-z0-9-]', ''
if ([string]::IsNullOrEmpty($NOVA_USER)) {
  Nova-Fail "Numele e obligatoriu. Reia nova-init.ps1."
}
$ORG = "nova-$NOVA_USER"
Nova-Ok "Nume workspace: $ORG"

# Pasul 4: credențiale canal
Write-Host ""
if ($NOVA_CONTROL_CHANNEL -eq 'telegram') {

  Write-Host "Pasul 4 din 4: Tokenul de bot Telegram pentru Nova Cortex Orchestrator" -ForegroundColor White
  Nova-Dim "Dacă nu ai unul: deschide Telegram, scrie la @BotFather, trimite /newbot, urmează pașii."
  Nova-Dim "BotFather îți va da un token care arată ca 123456:AAxxxxxxxxxxxx — paste-uiește-l mai jos."
  Nova-Dim "Vei avea nevoie de un AL DOILEA token mai târziu pentru Analyst — Orchestratorul ți-l va cere în /onboarding."
  $BOT_TOKEN = Read-Host "  →"
  if ($BOT_TOKEN -notmatch '^\d+:[A-Za-z0-9_-]+$') {
    Nova-Fail "Acela nu pare un token valid de bot Telegram. Format așteptat: 123456:AAxx... Reia nova-init.ps1."
  }
  Nova-Ok "Token capturat (se salvează local, nu se share-uiește niciodată)."

  Write-Host ""
  Write-Host "Deschide bot-ul în Telegram" -ForegroundColor White
  Nova-Dim "Pe Telegram caută numele botului (cel pe care l-ai dat la BotFather)."
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

} else {

  Write-Host "Pasul 4 din 4: Tokenele Slack pentru Nova Cortex" -ForegroundColor White
  Nova-Dim "Ai nevoie de un Slack App cu Socket Mode activat și scopurile: chat:write, channels:read, connections:write."
  Write-Host ""

  Write-Host "  Bot Token (xoxb-...)" -ForegroundColor Gray
  $SLACK_BOT_TOKEN = Read-Host "  →"
  if ($SLACK_BOT_TOKEN -notmatch '^xoxb-') {
    Nova-Fail "Bot token invalid. Trebuie să înceapă cu xoxb-. Reia nova-init.ps1."
  }

  Write-Host ""
  Write-Host "  App Token pentru Socket Mode (xapp-...)" -ForegroundColor Gray
  $SLACK_APP_TOKEN = Read-Host "  →"
  if ($SLACK_APP_TOKEN -notmatch '^xapp-') {
    Nova-Fail "App token invalid. Trebuie să înceapă cu xapp-. Reia nova-init.ps1."
  }

  Write-Host ""
  Write-Host "  Channel ID (C... — ID-ul canalului unde BOSS răspunde)" -ForegroundColor Gray
  $SLACK_CHANNEL_ID = Read-Host "  →"
  if ($SLACK_CHANNEL_ID -notmatch '^C[A-Z0-9]+$') {
    Nova-Fail "Channel ID invalid. Trebuie să înceapă cu C urmat de majuscule/cifre. Reia nova-init.ps1."
  }

  Write-Host ""
  Write-Host "  User ID al tău (U... — obligatoriu pentru securitate)" -ForegroundColor Gray
  $SLACK_ALLOWED_USER = Read-Host "  →"
  if ($SLACK_ALLOWED_USER -notmatch '^U[A-Z0-9]+$') {
    Nova-Fail "User ID invalid. Trebuie să înceapă cu U urmat de majuscule/cifre. Reia nova-init.ps1."
  }
  Nova-Ok "Credențiale Slack capturate (se salvează local)."

}

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
  cortextos add-agent boss --template $ORCH_TEMPLATE --org $ORG *> $null
  if ($LASTEXITCODE -ne 0) { Nova-Fail "Template-ul Orchestrator nu există la $CORTEXTOS_TEMPLATES\$ORCH_TEMPLATE\. Pasul de copiere template-uri probabil a eșuat — re-rulează scriptul." }
  Nova-Ok "Nova Cortex Orchestrator creat"
} finally {
  Pop-Location
}

# ─── Scrie .env-ul agentului ───────────────────────────────────────────
Nova-Say "Configurez canalul de control pentru Orchestratorul tău..."
$AGENT_ENV = Join-Path $CORTEXTOS_HOME "orgs\$ORG\agents\boss\.env"
if (Test-Path $AGENT_ENV) {
  $envContent = Get-Content $AGENT_ENV -Raw
  $upsert = {
    param($content, $key, $value)
    if ($content -match "(?m)^${key}=.*$") {
      $content -replace "(?m)^${key}=.*$", "${key}=$value"
    } else {
      $content.TrimEnd() + "`n${key}=$value`n"
    }
  }

  # Variabile Nova Cortex comune
  $envContent = & $upsert $envContent 'NOVA_CONTROL_CHANNEL'  $NOVA_CONTROL_CHANNEL
  $envContent = & $upsert $envContent 'NOVA_AGENT_RUNTIME'    $NOVA_AGENT_RUNTIME
  $envContent = & $upsert $envContent 'NOVA_ANALYST_TEMPLATE' $ANALYST_TEMPLATE

  # Credențiale specifice canalului
  if ($NOVA_CONTROL_CHANNEL -eq 'telegram') {
    $envContent = & $upsert $envContent 'BOT_TOKEN'    $BOT_TOKEN
    $envContent = & $upsert $envContent 'CHAT_ID'      $CHAT_ID
    $envContent = & $upsert $envContent 'ALLOWED_USER' $USER_ID
  } else {
    $envContent = & $upsert $envContent 'SLACK_BOT_TOKEN'    $SLACK_BOT_TOKEN
    $envContent = & $upsert $envContent 'SLACK_APP_TOKEN'    $SLACK_APP_TOKEN
    $envContent = & $upsert $envContent 'SLACK_CHANNEL_ID'   $SLACK_CHANNEL_ID
    $envContent = & $upsert $envContent 'SLACK_ALLOWED_USER' $SLACK_ALLOWED_USER
  }

  Set-Content -Path $AGENT_ENV -Value $envContent -Encoding UTF8 -NoNewline

  # Restrictioneaza accesul la .env (analogul chmod 600 pe Windows).
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

  Nova-Ok "Credențiale salvate local în .env"
} else {
  Nova-Warn "Fișierul .env al agentului nu există la calea așteptată — configurează canalul manual."
}

# ─── Pornește Orchestratorul ──────────────────────────────────────────
Nova-Step "Pornesc Orchestratorul tău"
Push-Location $CORTEXTOS_HOME
try {
  Nova-Say "Pornesc daemon-ul + boss..."
  cortextos start boss *> $null
  if ($LASTEXITCODE -eq 0) {
    if ($NOVA_CONTROL_CHANNEL -eq 'telegram') {
      Nova-Ok "Boss e online — gata să vorbească pe Telegram"
    } else {
      Nova-Ok "Boss e online"
    }
  } else {
    Nova-Warn "Auto-start a eșuat. Pornește manual: cd $CORTEXTOS_HOME; cortextos start boss"
  }
} finally {
  Pop-Location
}

# ─── Slack bridge legacy/fallback ─────────────────────────────────────
if ($NOVA_CONTROL_CHANNEL -eq 'slack' -and $env:NOVA_SLACK_MODE -eq 'bridge') {
  Nova-Step "Pornesc Slack bridge legacy"
  $SLACK_BRIDGE_DIR = Join-Path $SCRIPT_DIR 'slack-bridge'
  if (-not (Test-Path $SLACK_BRIDGE_DIR)) {
    Nova-Warn "Directorul slack-bridge lipsește de la $SLACK_BRIDGE_DIR — bridge-ul nu va porni."
  } else {
    # Scrie .env pentru bridge
    $bridgeEnv = @"
NOVA_TARGET_AGENT=boss
NOVA_BRIDGE_AGENT=slack
CTX_ORG=$ORG
SLACK_BOT_TOKEN=$SLACK_BOT_TOKEN
SLACK_APP_TOKEN=$SLACK_APP_TOKEN
SLACK_DEFAULT_CHANNEL=$SLACK_CHANNEL_ID
SLACK_LISTEN_CHANNELS=$SLACK_CHANNEL_ID
SLACK_BRIDGE_STATE=$CORTEXTOS_HOME\slack-bridge-state.json
SLACK_MEDIA_DIR=$CORTEXTOS_HOME\orgs\$ORG\agents\boss\slack-media
SLACK_MAX_FILE_BYTES=104857600
"@
    $bridgeEnv += "`nSLACK_ALLOWED_USER=$SLACK_ALLOWED_USER"
    Set-Content -Path (Join-Path $SLACK_BRIDGE_DIR '.env') -Value $bridgeEnv -Encoding UTF8

    Push-Location $SLACK_BRIDGE_DIR
    try {
      Nova-Say "Instalez dependențele bridge-ului..."
      npm install *> $null
      pm2 delete nova-slack-bridge 2>$null | Out-Null
      pm2 start npm --name nova-slack-bridge -- start *> $null
      if ($LASTEXITCODE -eq 0) {
        Nova-Ok "Slack bridge pornit (PM2: nova-slack-bridge)"
      } else {
        Nova-Warn "PM2 start a eșuat pentru Slack bridge. Pornește manual: cd $SLACK_BRIDGE_DIR; pm2 start npm --name nova-slack-bridge -- start"
      }
    } finally {
      Pop-Location
    }
  }
} elseif ($NOVA_CONTROL_CHANNEL -eq 'slack') {
  Nova-Ok "Slack nativ cortextOS activat — bridge-ul legacy nu este pornit"
}

# ─── Ecran final ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╭────────────────────────────────────────────────╮" -ForegroundColor Magenta
Write-Host "│  Nova Cortex e gata.                           │" -ForegroundColor Magenta
Write-Host "╰────────────────────────────────────────────────╯" -ForegroundColor Magenta
Write-Host ""
Write-Host "Următorii pași:" -ForegroundColor White
Write-Host ""
if ($NOVA_CONTROL_CHANNEL -eq 'telegram') {
  Write-Host "  1. Deschide Telegram și găsește botul pe care tocmai l-ai conectat."
  Write-Host "     Trimite-i orice mesaj (ex: `"salut`") ca să-ți rețină chat-ul."
  Write-Host ""
  Write-Host "  2. Trimite Orchestratorului această comandă ca să termine setup-ul:"
  Write-Host "       /onboarding" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "     Te va ghida prin identitate, program de lucru, reguli de autonomie,"
  Write-Host "     apoi îți va cere un AL DOILEA token BotFather ca să aducă Analystul online."
} else {
  Write-Host "  1. Deschide Slack și găsește canalul configurat."
  Write-Host "     Invită app-ul în canal, apoi trimite orice mesaj (ex: `"salut`") ca să verifici că Boss răspunde."
  Write-Host ""
  Write-Host "  2. Trimite Orchestratorului această comandă ca să termine setup-ul:"
  Write-Host "       /onboarding" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "     Te va ghida prin identitate, program de lucru și reguli de autonomie."
}
Write-Host ""
Write-Host "  3. După ce Analystul e online, Orchestratorul tău te poate ajuta să adaugi"
Write-Host "     agenți specialiști (CFO, marketer, ops, research — tu alegi)."
Write-Host ""
Write-Host "  Pentru a reporni Orchestratorul oricând: cd $CORTEXTOS_HOME; cortextos start boss" -ForegroundColor DarkGray
if ($NOVA_CONTROL_CHANNEL -eq 'slack' -and $env:NOVA_SLACK_MODE -eq 'bridge') {
  Write-Host "  Pentru a reporni bridge-ul Slack legacy: pm2 restart nova-slack-bridge" -ForegroundColor DarkGray
} elseif ($NOVA_CONTROL_CHANNEL -eq 'slack') {
  Write-Host "  Slack rulează nativ prin cortextOS; pentru restart: cd $CORTEXTOS_HOME; cortextos restart boss" -ForegroundColor DarkGray
}
Write-Host ""
Write-Host "  Workspace: $ORG  •  runtime: $NOVA_AGENT_RUNTIME  •  canal: $NOVA_CONTROL_CHANNEL" -ForegroundColor DarkGray
Write-Host ""
