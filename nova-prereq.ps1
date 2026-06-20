# nova-prereq.ps1 — Verificare prerequisites Nova Cortex pe Windows nativ + auto-install.
#
# Rulează înainte de nova-init.ps1. Detectează versiunea de Windows + PowerShell,
# instalează tool-urile lipsă. Idempotent: safe de rerulat.
#
# NECESITA DREPTURI DE ADMINISTRATOR — instalam VS Build Tools, jq si Python via
# winget (toate cer admin) + cortextOS face npm link global. Daca rulezi din shell
# normal, scriptul se opreste cu instructiuni clare.
#
# Suportă: Windows 10/11 nativ cu PowerShell 5.1+ sau 7+. NU rulează în WSL2 —
# pentru WSL2/Linux foloseste nova-prereq.sh.
#
# Acceptă variabila de mediu $env:NOVA_AGENT_RUNTIME (codex|claude). Implicit claude.

$ErrorActionPreference = 'Stop'

# ─── Helper-i de output branded ─────────────────────────────────────────
function Nova-Say($msg)  { Write-Host "▸ $msg" -ForegroundColor Magenta }
function Nova-Ok($msg)   { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Nova-Warn($msg) { Write-Host "  ! $msg" -ForegroundColor Yellow }
function Nova-Fail($msg) { Write-Host "  ✗ $msg" -ForegroundColor Red; exit 1 }
function Nova-Step($msg) { Write-Host ""; Write-Host "─── $msg ───" -ForegroundColor Cyan }
function Nova-Dim($msg)  { Write-Host "    $msg" -ForegroundColor DarkGray }

$NOVA_AGENT_RUNTIME = if ($env:NOVA_AGENT_RUNTIME) { $env:NOVA_AGENT_RUNTIME } else { 'claude' }
if ($NOVA_AGENT_RUNTIME -notin @('claude', 'codex')) {
  Nova-Fail "NOVA_AGENT_RUNTIME trebuie să fie 'claude' sau 'codex' (acum: $NOVA_AGENT_RUNTIME)."
}

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

# ─── Verifica drepturi Administrator ────────────────────────────────────
# nova-prereq necesita admin pentru:
#   - winget install Microsoft.VisualStudio.2022.BuildTools (VS BuildTools)
#   - winget install jqlang.jq, Python.Python.3.x
#   - cortextos install (npm link global cere drepturi de scriere in %APPDATA%\npm)
# Fara admin, multe operatiuni esueaza silent sau cu UAC prompts care intrerup
# fluxul. Fail-uim devreme cu un mesaj clar in loc sa lasam user-ul sa descopere
# la jumatatea instalarii.
function Test-IsAdmin {
  $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object System.Security.Principal.WindowsPrincipal($currentUser)
  return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-IsAdmin)) {
  Write-Host ""
  Write-Host "  Acest script trebuie rulat ca Administrator." -ForegroundColor Red
  Write-Host ""
  Write-Host "  De ce: instalam Visual Studio Build Tools, jq si Python via winget — toate cer drepturi de admin."
  Write-Host ""
  Write-Host "  Cum: " -NoNewline
  Write-Host "Start → 'powershell' → click dreapta → 'Run as administrator'" -ForegroundColor Cyan
  Write-Host "  Apoi: " -NoNewline
  Write-Host "cd `$env:USERPROFILE/nova-agents" -ForegroundColor Cyan
  Write-Host "  Apoi: " -NoNewline
  Write-Host "./nova-prereq.ps1" -ForegroundColor Cyan
  Write-Host ""
  Nova-Fail "Re-ruleaza ca Admin."
}
Nova-Ok "Drepturi Administrator confirmate"

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

# ─── Runtime AI: Claude Code sau OpenAI Codex ────────────────────────────
if ($NOVA_AGENT_RUNTIME -eq 'codex') {

  Nova-Step "Verific OpenAI Codex CLI (runtime-ul agenților Nova Cortex)"
  if (Get-Command codex -ErrorAction SilentlyContinue) {
    Nova-Ok "Codex CLI deja instalat ($(codex --version 2>$null | Select-Object -First 1))"
  } else {
    Nova-Say "Instalez OpenAI Codex CLI..."
    npm install -g '@openai/codex'
    if ($LASTEXITCODE -ne 0) { Nova-Fail "npm install Codex a esuat" }
    Nova-Ok "Codex CLI instalat"
  }

  $codexAuthOk = ($env:OPENAI_API_KEY -or (Test-Path (Join-Path $env:USERPROFILE '.codex\auth.json')))
  if (-not $codexAuthOk) {
    Nova-Warn "Codex CLI pare instalat, dar nu văd autentificare OpenAI."
    Write-Host ""
    Write-Host "  Trebuie să rulezi MANUAL " -NoNewline
    Write-Host "codex" -ForegroundColor Cyan -NoNewline
    Write-Host " o dată înainte de nova-init.ps1:"
    Write-Host ""
    Write-Host "    1. Tastează: " -NoNewline; Write-Host "codex" -ForegroundColor Cyan
    Write-Host "    2. Autentifică-te cu ChatGPT/OpenAI când ți se cere"
    Write-Host "    3. Când ajungi în Codex, ieși cu " -NoNewline; Write-Host "/exit" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Alternativ, setează " -NoNewline; Write-Host "OPENAI_API_KEY" -ForegroundColor Cyan -NoNewline; Write-Host " pentru userul care rulează agenții."
    Write-Host "  Apoi reia: " -NoNewline
    Write-Host "`$env:NOVA_AGENT_RUNTIME='codex'; .\nova-prereq.ps1" -ForegroundColor Cyan
    Write-Host ""
    Nova-Fail "Autentifică Codex/OpenAI înainte să continui."
  }
  Nova-Ok "Codex/OpenAI autentificat"

} else {

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

  # Claude Code stocheaza credentialele in $env:USERPROFILE\.claude\.credentials.json.
  # Fara autentificare, primul boot al claude in PTY se blocheaza la "Select login method".
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

  # Seteaza skipDangerousModePermissionPrompt — evita prompt-ul de --dangerously-skip-permissions
  # care blocheaza PTY-ul cortextOS (Claude Code 2.1.133+).
  $claudeSettingsFile = Join-Path $env:USERPROFILE '.claude\settings.json'
  if (Test-Path $claudeSettingsFile) {
    $settings = Get-Content $claudeSettingsFile -Raw | ConvertFrom-Json
    if (-not $settings.skipDangerousModePermissionPrompt) {
      Nova-Say "Setez skipDangerousModePermissionPrompt in .claude\settings.json..."
      $settingsBackup = "$claudeSettingsFile.nova-bak"
      if (-not (Test-Path $settingsBackup)) { Copy-Item $claudeSettingsFile $settingsBackup -ErrorAction SilentlyContinue }
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

  # Marcheaza onboarding-ul ca terminat — evita first-run wizard la fiecare lansare PTY.
  $claudeProfileFile = Join-Path $env:USERPROFILE '.claude.json'
  if (Test-Path $claudeProfileFile) {
    $claudeProfile = Get-Content $claudeProfileFile -Raw | ConvertFrom-Json
    if (-not $claudeProfile.hasCompletedOnboarding) {
      Nova-Say "Marchez onboarding Claude Code ca terminat in .claude.json..."
      $profileBackup = "$claudeProfileFile.nova-bak"
      if (-not (Test-Path $profileBackup)) { Copy-Item $claudeProfileFile $profileBackup -ErrorAction SilentlyContinue }
      $claudeProfile | Add-Member -NotePropertyName 'hasCompletedOnboarding' -NotePropertyValue $true -Force
      $claudeProfile | Add-Member -NotePropertyName 'hasInitOnboardingBeenShown' -NotePropertyValue $true -Force
      $claudeProfile | Add-Member -NotePropertyName 'lastOnboardingVersion' -NotePropertyValue '2.0.26' -Force
      $claudeProfile | ConvertTo-Json -Depth 20 | Set-Content $claudeProfileFile -Encoding UTF8
      Nova-Ok "Flag hasCompletedOnboarding setat"
    } else {
      Nova-Ok "Onboarding Claude Code deja marcat ca terminat"
    }
  }

}

# ─── Visual Studio Build Tools (C++ compiler pentru node-pty) ──────────
# cortextOS depinde de node-pty care e un native addon C++. Build-ul cere MSVC.
# Pe Windows nu vine standard cu Node 20+ — trebuie instalat separat. Detectam
# via vswhere.exe (instalat de Visual Studio Installer), nu via 'where cl.exe'
# care nu vede instalarile winget (cl.exe e pe PATH doar in 'Developer PowerShell').
Nova-Step "Verific Visual Studio Build Tools (compiler C++ pentru native addons)"
$vsInstaller = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = $null
if (Test-Path $vsInstaller) {
  $vsPath = & $vsInstaller -latest -products '*' -requires 'Microsoft.VisualStudio.Workload.VCTools' -property installationPath 2>$null | Select-Object -First 1
}

if (-not $vsPath) {
  Nova-Say "VS Build Tools (workload C++) lipsesc. Instalez via winget — ~10-15 min, ~3-7 GB download..."
  Nova-Dim "Sterge un ceai si vino mai tarziu. Daca apare prompt UAC, accepta."
  winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override '--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended' --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) {
    Nova-Fail "winget install VS BuildTools a esuat. Instaleaza manual de la https://visualstudio.microsoft.com/visual-cpp-build-tools/"
  }
  # Re-detecteaza dupa install
  if (Test-Path $vsInstaller) {
    $vsPath = & $vsInstaller -latest -products '*' -requires 'Microsoft.VisualStudio.Workload.VCTools' -property installationPath 2>$null | Select-Object -First 1
  }
  if (-not $vsPath) { Nova-Fail "VS BuildTools instalate dar vswhere nu le gaseste — bug winget?" }
  Nova-Ok "VS Build Tools instalate la $vsPath"
} else {
  Nova-Ok "VS Build Tools deja prezent la $vsPath"
}

# ─── Source Developer Shell (cl.exe pe PATH pentru subprocess-uri) ─────
# Fara DevShell, cl.exe e in $vsPath\VC\Tools\MSVC\<ver>\bin\... dar NU pe PATH global.
# Cortextos install foloseste 'where cl.exe' pentru detectie → esueaza fara DevShell.
# Enter-VsDevShell sourceste vcvars + adauga cl.exe + INCLUDE/LIB la $env-ul curent,
# care e mostenit de toate subprocess-urile spawn-ate de acest script.
$devShellDll = Join-Path $vsPath 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll'
if (Test-Path $devShellDll) {
  Nova-Say "Sourcing Visual Studio Developer Shell vars (cl.exe + INCLUDE + LIB)..."
  Import-Module $devShellDll
  Enter-VsDevShell -VsInstallPath $vsPath -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64' | Out-Null
  if (Get-Command cl.exe -ErrorAction SilentlyContinue) {
    Nova-Ok "DevShell sourced — cl.exe vizibil pentru subprocess-uri"
  } else {
    Nova-Warn "DevShell sourced dar cl.exe tot lipseste pe PATH — cortextos install poate cracteaza"
  }
} else {
  Nova-Warn "Microsoft.VisualStudio.DevShell.dll lipseste la $devShellDll — cortextos install poate cracteaza fara cl.exe pe PATH"
}

# ─── jq (folosit de cortextos shell scripts si bus operations) ──────────
# Cortextos install.mjs incearca jq install via winget DAR nu refresh-uieste PATH
# inainte sa cheme subprocess 'cortextos install', care la randul lui incearca
# Chocolatey ca fallback (cu prompt interactiv). Instalam noi inainte cu refresh
# de PATH dupa, asa cortextos il gaseste deja pe PATH si nu face nimic.
Nova-Step "Verific jq (JSON parser folosit de cortextos)"
if (Get-Command jq -ErrorAction SilentlyContinue) {
  Nova-Ok "jq deja instalat ($(jq --version 2>$null))"
} else {
  Nova-Say "Instalez jq via winget..."
  winget install --id jqlang.jq -e --accept-package-agreements --accept-source-agreements --silent
  if ($LASTEXITCODE -ne 0) { Nova-Fail "winget install jq a esuat (exit $LASTEXITCODE)" }
  # Refresh PATH in sesiunea curenta. Daca scriem doar la User PATH (winget),
  # trebuie sa rebuild-uim $env:Path din Machine + User pentru a-l vedea acum.
  $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
  if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
    Nova-Fail "jq instalat dar nu apare pe PATH dupa refresh. Inchide PowerShell, redeschide ca Admin, reia."
  }
  Nova-Ok "jq instalat si pe PATH"
}

# ─── Python 3 (fallback pentru node-gyp + cortextos KB venv) ────────────
Nova-Step "Verific Python 3 (folosit de node-gyp + cortextos Knowledge Base venv)"
$hasPython = (Get-Command python -ErrorAction SilentlyContinue) -or (Get-Command python3 -ErrorAction SilentlyContinue)
if ($hasPython) {
  $pyVer = $null
  try { $pyVer = (python --version 2>&1) } catch {}
  Nova-Ok "Python 3 deja prezent ($pyVer)"
} else {
  Nova-Say "Instalez Python 3 via winget..."
  winget install --id Python.Python.3.12 -e --accept-package-agreements --accept-source-agreements --silent
  if ($LASTEXITCODE -ne 0) { Nova-Fail "winget install Python a esuat (exit $LASTEXITCODE)" }
  $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
  if (-not ((Get-Command python -ErrorAction SilentlyContinue) -or (Get-Command python3 -ErrorAction SilentlyContinue))) {
    Nova-Warn "Python instalat dar nu apare pe PATH. KB venv poate sa cracteze, dar continuam — nu e critic pentru agentii de baza."
  } else {
    Nova-Ok "Python 3 instalat si pe PATH"
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
  $installerUrl = 'https://raw.githubusercontent.com/danutmitrut/cortextos/main/install.mjs'
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
if ($NOVA_AGENT_RUNTIME -eq 'codex') {
  Write-Host "  Codex CLI:      $((codex --version 2>$null | Select-Object -First 1))"
} else {
  Write-Host "  Claude Code:    $((claude --version 2>$null | Select-Object -First 1))"
}
Write-Host "  cortextOS:      instalat"
Write-Host "  PM2:            $(pm2 --version 2>$null | Select-Object -First 1)"
Write-Host ""
Write-Host "Următor: rulează " -NoNewline; Write-Host ".\nova-init.ps1" -ForegroundColor Cyan -NoNewline; Write-Host " ca să configurezi primii agenți Nova Cortex."
Write-Host ""
