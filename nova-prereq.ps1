# nova-prereq.ps1 — Verificare prerequisites Nova Cortex pe Windows nativ + auto-install.
#
# Rulează înainte de nova-init.ps1. Detectează versiunea de Windows + PowerShell,
# instalează tool-urile lipsă. Idempotent: safe de rerulat.
#
# Suportă: Windows 10/11 nativ cu PowerShell 5.1+ sau 7+. NU rulează în WSL2 —
# pentru WSL2/Linux foloseste nova-prereq.sh.

$ErrorActionPreference = 'Stop'

# ─── Helper-i de output branded ─────────────────────────────────────────
function Nova-Say($msg)  { Write-Host "▸ $msg" -ForegroundColor Magenta }
function Nova-Ok($msg)   { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Nova-Warn($msg) { Write-Host "  ! $msg" -ForegroundColor Yellow }
function Nova-Fail($msg) { Write-Host "  ✗ $msg" -ForegroundColor Red; exit 1 }
function Nova-Step($msg) { Write-Host ""; Write-Host "─── $msg ───" -ForegroundColor Cyan }
function Nova-Dim($msg)  { Write-Host "    $msg" -ForegroundColor DarkGray }

# ─── Refuză să ruleze în WSL ────────────────────────────────────────────
# Daca scriptul e cumva invocat din WSL via PowerShell.exe, redirectam la bash.
if (Test-Path '/proc/version' -ErrorAction SilentlyContinue) {
  $procVersion = Get-Content '/proc/version' -ErrorAction SilentlyContinue
  if ($procVersion -match 'microsoft|WSL') {
    Nova-Fail "Detectez WSL2. Foloseste varianta bash: bash nova-prereq.sh (in WSL, dar Nova Cortex acum recomanda nativ — vezi README)"
  }
}

# ─── Detectează OS + PowerShell version ─────────────────────────────────
Nova-Step "Detectez sistemul tău"

# $IsWindows e introdus in PowerShell 6+ — pe PS 5.1 e $null si comparatia
# directa cu $false esueaza silent. Fallback la $env:OS care pe Windows e
# mereu 'Windows_NT'. Daca nici una nu sugereaza Windows, refuza sa rulam.
if (-not ($IsWindows -or $env:OS -match 'Windows')) {
  Nova-Fail "Acest script ruleaza doar pe Windows nativ. Pe Mac/Linux foloseste: bash nova-prereq.sh"
}

$winVersion = [System.Environment]::OSVersion.Version
Nova-Ok "Windows $($winVersion.Major).$($winVersion.Minor) (build $($winVersion.Build))"

$psVersion = $PSVersionTable.PSVersion
if ($psVersion.Major -lt 5) {
  Nova-Fail "PowerShell $psVersion prea vechi. Necesita 5.1+. Updateaza Windows sau instaleaza PowerShell 7."
}
Nova-Ok "PowerShell $psVersion"

# ─── Node.js 20+ ─────────────────────────────────────────────────────────
Nova-Step "Verific Node.js (runtime pentru agenții Nova Cortex)"
$nodeOk = $false
if (Get-Command node -ErrorAction SilentlyContinue) {
  $nodeMajor = (node -p "process.versions.node.split('.')[0]" 2>$null)
  if ([int]$nodeMajor -ge 20) {
    Nova-Ok "Node.js $(node --version) — îndeplinește cerința (>=20)"
    $nodeOk = $true
  } else {
    Nova-Warn "Node.js $(node --version) e mai vechi decat v20"
  }
}

if (-not $nodeOk) {
  Nova-Say "Node.js v20+ lipseste."
  # Incercam winget primul (Windows 10 1809+ / 11)
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    Nova-Say "Instalez Node.js LTS via winget..."
    winget install -e --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { Nova-Fail "winget install Node.js a esuat. Instaleaza manual: https://nodejs.org/" }
    # Refresh PATH in current session
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
    Nova-Ok "Node.js instalat ($(node --version))"
  } else {
    Nova-Fail "winget nu e disponibil pe sistemul tau. Instaleaza manual Node.js LTS (v20+) de la https://nodejs.org/ apoi reia nova-prereq.ps1"
  }
}

# ─── Claude Code CLI ─────────────────────────────────────────────────────
Nova-Step "Verific Claude Code CLI (agenții AI au nevoie ca să gândească)"
if (Get-Command claude -ErrorAction SilentlyContinue) {
  Nova-Ok "Claude Code deja instalat ($(claude --version 2>$null | Select-Object -First 1))"
} else {
  Nova-Say "Instalez Claude Code CLI..."
  npm install -g '@anthropic-ai/claude-code'
  if ($LASTEXITCODE -ne 0) { Nova-Fail "npm install Claude Code a esuat" }
  Nova-Ok "Claude Code instalat"
  Nova-Dim "Va trebui să te autentifici cu 'claude' (o singură dată) înainte ca agenții să vorbească cu Anthropic."
}

# ─── Verifica autentificarea Claude Code ────────────────────────────────
# Claude Code stocheaza credentialele in $env:USERPROFILE\.claude\.credentials.json
# (pe Windows uses keychain-like store, dar fisierul exista). Fara autentificare,
# primul boot al claude in PTY se blocheaza la "Select login method".
$claudeCredFile = Join-Path $env:USERPROFILE '.claude\.credentials.json'
if (-not (Test-Path $claudeCredFile)) {
  Nova-Warn "Claude Code NU autentificat (lipseste $claudeCredFile)."
  Write-Host ""
  Write-Host "  Trebuie sa rulezi MANUAL " -NoNewline
  Write-Host "claude" -ForegroundColor Cyan -NoNewline
  Write-Host " o data inainte de nova-init.ps1:"
  Write-Host ""
  Write-Host "    1. Tasteaza: " -NoNewline; Write-Host "claude" -ForegroundColor Cyan
  Write-Host "    2. Alege tema (1 = Auto)"
  Write-Host "    3. Alege login method (1 = Claude subscription Pro/Max)"
  Write-Host "    4. Browser-ul se deschide pentru autentificare cu contul Anthropic"
  Write-Host "    5. Cand vezi prompt-ul " -NoNewline; Write-Host ">" -ForegroundColor Cyan -NoNewline; Write-Host ", iesi cu " -NoNewline; Write-Host "/exit" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "  Apoi reia: " -NoNewline; Write-Host ".\nova-prereq.ps1" -ForegroundColor Cyan -NoNewline; Write-Host " (verifica) si " -NoNewline; Write-Host ".\nova-init.ps1" -ForegroundColor Cyan -NoNewline; Write-Host " (wizard)."
  Write-Host ""
  Nova-Fail "Autentifica claude inainte sa continui."
}
Nova-Ok "Claude Code autentificat"

# ─── Seteaza skipDangerousModePermissionPrompt ──────────────────────────
# Claude Code 2.1.133+ a adaugat o avertizare manuala pentru
# --dangerously-skip-permissions care blocheaza PTY-ul cortextOS.
$claudeSettingsFile = Join-Path $env:USERPROFILE '.claude\settings.json'
if (Test-Path $claudeSettingsFile) {
  $settings = Get-Content $claudeSettingsFile -Raw | ConvertFrom-Json
  if (-not $settings.skipDangerousModePermissionPrompt) {
    Nova-Say "Setez skipDangerousModePermissionPrompt in .claude\settings.json..."
    # Salveaza o copie a versiunii originale inainte sa mutam (o data, nu suprascriem).
    $settingsBackup = "$claudeSettingsFile.nova-bak"
    if (-not (Test-Path $settingsBackup)) {
      Copy-Item $claudeSettingsFile $settingsBackup -ErrorAction SilentlyContinue
    }
    $settings | Add-Member -NotePropertyName 'skipDangerousModePermissionPrompt' -NotePropertyValue $true -Force
    $settings | ConvertTo-Json -Depth 20 | Set-Content $claudeSettingsFile -Encoding UTF8
    Nova-Ok "skipDangerousModePermissionPrompt setat"
  } else {
    Nova-Ok "skipDangerousModePermissionPrompt deja setat"
  }
} else {
  New-Item -ItemType Directory -Path (Join-Path $env:USERPROFILE '.claude') -Force | Out-Null
  '{"skipDangerousModePermissionPrompt": true}' | Set-Content $claudeSettingsFile -Encoding UTF8
  Nova-Ok "Creat .claude\settings.json cu skipDangerousModePermissionPrompt"
}

# ─── Marcheaza onboarding-ul ca terminat in ~/.claude.json ──────────────
# Daca aceste flag-uri lipsesc, claude rulat in PTY relanseaza first-run wizard.
$claudeProfileFile = Join-Path $env:USERPROFILE '.claude.json'
if (Test-Path $claudeProfileFile) {
  $claudeProfile = Get-Content $claudeProfileFile -Raw | ConvertFrom-Json
  if (-not $claudeProfile.hasCompletedOnboarding) {
    Nova-Say "Marchez onboarding Claude Code ca terminat in .claude.json..."
    # Salveaza o copie a versiunii originale inainte sa mutam (o data, nu suprascriem).
    $profileBackup = "$claudeProfileFile.nova-bak"
    if (-not (Test-Path $profileBackup)) {
      Copy-Item $claudeProfileFile $profileBackup -ErrorAction SilentlyContinue
    }
    $claudeProfile | Add-Member -NotePropertyName 'hasCompletedOnboarding' -NotePropertyValue $true -Force
    $claudeProfile | Add-Member -NotePropertyName 'hasInitOnboardingBeenShown' -NotePropertyValue $true -Force
    $claudeProfile | Add-Member -NotePropertyName 'lastOnboardingVersion' -NotePropertyValue '2.0.26' -Force
    $claudeProfile | ConvertTo-Json -Depth 20 | Set-Content $claudeProfileFile -Encoding UTF8
    Nova-Ok "Flag hasCompletedOnboarding setat"
  } else {
    Nova-Ok "Onboarding Claude Code deja marcat ca terminat"
  }
}

# ─── cortextOS engine ────────────────────────────────────────────────────
Nova-Step "Verific cortextOS (motorul pe care rulează Nova Cortex)"
if (Get-Command cortextos -ErrorAction SilentlyContinue) {
  Nova-Ok "cortextOS deja instalat"
} else {
  Nova-Say "Instalez motorul cortextOS..."
  Nova-Dim "Powered by cortextOS — framework open-source multi-agent de la Cortext LLC (MIT)."
  # install.mjs e ESM (top-level await, import.meta) — `node -e` cu eval rupe pentru ESM.
  # Descarcam intai la disk, apoi rulam `node fisier.mjs` ca sa primim parsing ESM corect.
  $installerUrl = 'https://raw.githubusercontent.com/grandamenium/cortextos/main/install.mjs'
  $installerTmp = Join-Path $env:TEMP "cortextos-install-$([guid]::NewGuid()).mjs"
  try {
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerTmp -UseBasicParsing -ErrorAction Stop
    node $installerTmp
    if ($LASTEXITCODE -ne 0) { Nova-Fail "Instalarea cortextOS a esuat (exit $LASTEXITCODE)" }
  } finally {
    Remove-Item -Path $installerTmp -ErrorAction SilentlyContinue
  }

  # Refresh PATH si verifica
  $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
  if (-not (Get-Command cortextos -ErrorAction SilentlyContinue)) {
    Nova-Fail "cortextOS instalat dar nu pe PATH. Inchide PowerShell si redeschide, apoi reia."
  }
  Nova-Ok "cortextOS instalat si pe PATH"
}

# ─── PM2 (manager de proces pentru daemon) ──────────────────────────────
Nova-Step "Verific PM2 (manager de proces pentru daemon)"
if (Get-Command pm2 -ErrorAction SilentlyContinue) {
  Nova-Ok "PM2 deja instalat ($(pm2 --version 2>$null | Select-Object -First 1))"
} else {
  Nova-Say "PM2 lipseste — il instalez global..."
  npm install -g pm2
  if ($LASTEXITCODE -ne 0) { Nova-Fail "Instalarea PM2 a esuat" }
  Nova-Ok "PM2 instalat"
}

# ─── Sumar final ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╭──────────────────────────────────────────╮" -ForegroundColor Magenta
Write-Host "│  Toolbox Nova Cortex gata                │" -ForegroundColor Magenta
Write-Host "╰──────────────────────────────────────────╯" -ForegroundColor Magenta
Write-Host ""
Write-Host "Versiuni confirmate:"
Write-Host "  Node.js:        $(node --version)"
Write-Host "  Claude Code:    $((claude --version 2>$null | Select-Object -First 1))"
Write-Host "  cortextOS:      instalat"
Write-Host "  PM2:            $(pm2 --version 2>$null | Select-Object -First 1)"
Write-Host ""
Write-Host "Următor: rulează " -NoNewline; Write-Host ".\nova-init.ps1" -ForegroundColor Cyan -NoNewline; Write-Host " ca să configurezi primii agenți Nova Cortex."
Write-Host ""
