# Native behavioral harness. No installed PM2, engine, network or services are used.
param([string]$PowerShellExe = (Join-Path $PSHOME 'powershell.exe'))
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { Write-Host 'SKIP: requires native Windows; macOS pwsh parsing is not behavioral evidence.'; exit 0 }
if (-not (Test-Path $PowerShellExe)) { $PowerShellExe = Join-Path $PSHOME 'pwsh.exe' }
$repoSource = Split-Path (Split-Path $PSScriptRoot)
$nodeExe = (Get-Command node.exe -ErrorAction Stop).Source
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('nova entrypoints ' + [guid]::NewGuid())
New-Item -ItemType Directory $sandbox | Out-Null
function Assert-True($condition, $message) { if (-not $condition) { throw $message } }
try {
  # A real disposable .exe is needed because the production VS path ends in .exe.
  $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
  Assert-True (Test-Path $csc) 'Native harness requires the Windows .NET Framework C# compiler.'
  $source = Join-Path $sandbox 'VsStub.cs'
  'class VsStub { static void Main() { System.Console.WriteLine(System.Environment.GetEnvironmentVariable("FIXTURE_VS")); } }' | Set-Content $source
  $vsExe = Join-Path $sandbox 'vswhere.exe'
  & $csc /nologo /target:exe "/out:$vsExe" $source
  Assert-True ($LASTEXITCODE -eq 0) 'Could not compile isolated vswhere fixture.'
  $caWriter = Join-Path $sandbox 'ca-fixture.mjs'
  "import { writeFileSync } from 'node:fs'; import { rootCertificates } from 'node:tls'; writeFileSync(process.argv[2], rootCertificates[0]);" | Set-Content $caWriter -Encoding UTF8
  $fixtureCA = Join-Path $sandbox 'fixture-ca.pem'
  & $nodeExe $caWriter $fixtureCA
  Assert-True ($LASTEXITCODE -eq 0) 'Could not create isolated CA fixture.'
  foreach ($presence in @('present','absent')) {
  foreach ($case in @('prepare', 'check', 'start', 'save', 'unhealthy', 'success', 'prereq')) {
    $root = Join-Path $sandbox "$case-$presence"
    $repo = Join-Path $root 'repo with spaces'
    $user = Join-Path $root 'user'
    $bin = Join-Path $root 'bin with spaces'
    $engine = Join-Path $user 'cortextos'
    $vsDir = Join-Path $root 'program files\Microsoft Visual Studio\Installer'
    foreach ($dir in @($repo, $bin, $user, "$user\.codex", "$user\.claude", "$engine\templates", "$repo\scripts", $vsDir, "$root\vs")) { New-Item -ItemType Directory $dir -Force | Out-Null }
    Copy-Item $vsExe (Join-Path $vsDir 'vswhere.exe')
    foreach ($name in @('nova-init.ps1', 'nova-prereq.ps1', 'templates', 'slack-bridge')) { Copy-Item (Join-Path $repoSource $name) $repo -Recurse }
    New-Item -ItemType Directory "$repo\scripts\installer" | Out-Null
    Copy-Item (Join-Path $repoSource 'scripts\installer\slack-status.mjs') "$repo\scripts\installer\slack-status.mjs"
    '{}' | Set-Content "$user\.codex\auth.json"
    '{}' | Set-Content "$user\.claude\.credentials.json"
    $events = Join-Path $root 'events'
    '' | Set-Content $events
    # npm-style .cmd wrappers intentionally coexist with poison .ps1 shims.
    "@echo off`r`n`"$nodeExe`" %*`r`nexit /b %errorlevel%" | Set-Content "$bin\node.cmd" -Encoding ASCII
    foreach ($tool in @('npm', 'pm2', 'cortextos', 'codex', 'claude', 'jq', 'python', 'python3', 'winget')) {
      $body = "@echo off`r`necho $tool`:%*>>`"%EVENTS%`"`r`n"
      if ($tool -eq 'cortextos') { $body += "if `"%1`"==`"init`" mkdir `"%CORTEXTOS_DIR%\orgs\%2\agents\boss`"`r`nif `"%1`"==`"init`" echo # fixture>`"%CORTEXTOS_DIR%\orgs\%2\agents\boss\.env`"`r`n" }
      elseif ($tool -eq 'pm2') { $body += 'if "%1"=="jlist" echo [{"name":"nova-slack-bridge","pm2_env":{"status":"%BRIDGE_STATUS%","username":"student","USERNAME":"student","env":{"USERNAME":"student","SLACK_BOT_TOKEN":"secret-sentinel"}}}]' + "`r`n" }
      elseif ($tool -in @('python','python3')) { $body += "echo 3`r`n" }
      else { $body += "echo fixture`r`n" }
      $body += "exit /b 0`r`n"
      $body | Set-Content "$bin\$tool.cmd" -Encoding ASCII
      if ($tool -in @('npm','pm2','cortextos')) { 'throw "Unsafe PowerShell shim selected"' | Set-Content "$bin\$tool.ps1" }
    }
    @'
import { appendFileSync } from 'node:fs';
appendFileSync(process.env.EVENTS, 'engine:' + process.argv.slice(2).join(' ') + '\n');
console.log('VISIBLE-CONSENT-' + process.argv[2]);
process.exit(process.argv[2] === process.env.FAIL_PHASE ? 9 : 0);
'@ | Set-Content "$repo\scripts\nova-engine.mjs" -Encoding UTF8
    $p = New-Object Diagnostics.ProcessStartInfo
    $p.FileName = $PowerShellExe
    $script = if ($case -eq 'prereq') { 'nova-prereq.ps1' } else { 'nova-init.ps1' }
    $wrapper = Join-Path $root 'observe-environment.ps1'
    @'
$ErrorActionPreference = 'Stop'
$keys = @('NOVA_AGENT_RUNTIME','CTX_FRAMEWORK_ROOT','CTX_ROOT','CTX_PROJECT_ROOT','CTX_INSTANCE_ID','NODE_EXTRA_CA_CERTS','CORTEXTOS_REPO','Path')
$before = @{}
foreach ($key in $keys) { $before[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
& $env:FIXTURE_ENTRYPOINT
$result = $LASTEXITCODE
foreach ($key in $keys) {
  if ([Environment]::GetEnvironmentVariable($key, 'Process') -cne $before[$key]) { throw ('Environment not restored: ' + $key) }
}
Write-Output 'ENVIRONMENT-RESTORED'
exit $result
'@ | Set-Content $wrapper -Encoding UTF8
    $p.Arguments = "-NoProfile -File `"$wrapper`""
    $p.WorkingDirectory = $root
    $p.UseShellExecute = $false
    $p.RedirectStandardInput = $true
    $p.RedirectStandardOutput = $true
    $p.RedirectStandardError = $true
    $p.EnvironmentVariables['PATH'] = "$bin;$env:SystemRoot\System32;$PSHOME"
    foreach ($key in @('HOME','USERPROFILE','APPDATA','LOCALAPPDATA','TEMP','TMP')) { $p.EnvironmentVariables[$key] = $user }
    foreach ($key in @('CORTEXTOS_REPO','CTX_ROOT','CTX_FRAMEWORK_ROOT','CTX_PROJECT_ROOT','CTX_INSTANCE_ID','NODE_EXTRA_CA_CERTS','NODE_OPTIONS')) { $p.EnvironmentVariables.Remove($key) }
    if ($presence -eq 'present') {
      foreach ($key in @('CORTEXTOS_REPO','CTX_ROOT','CTX_FRAMEWORK_ROOT','CTX_PROJECT_ROOT','CTX_INSTANCE_ID')) { $p.EnvironmentVariables[$key] = "sentinel-$key" }
      $p.EnvironmentVariables['NODE_EXTRA_CA_CERTS'] = $fixtureCA
    }
    $p.EnvironmentVariables['FIXTURE_ENTRYPOINT'] = "$repo\$script"
    $p.EnvironmentVariables['PM2_HOME'] = "$user\.pm2"
    $p.EnvironmentVariables['CORTEXTOS_DIR'] = $engine
    $p.EnvironmentVariables['EVENTS'] = $events
    $p.EnvironmentVariables['FAIL_PHASE'] = $(if ($case -eq 'prereq') { 'prepare' } else { $case })
    $p.EnvironmentVariables['BRIDGE_STATUS'] = $(if ($case -eq 'unhealthy') { 'errored' } else { 'online' })
    if ($presence -eq 'present') { $p.EnvironmentVariables['NOVA_AGENT_RUNTIME'] = 'codex' }
    else { $p.EnvironmentVariables.Remove('NOVA_AGENT_RUNTIME') }
    $p.EnvironmentVariables['ProgramFiles(x86)'] = "$root\program files"
    $p.EnvironmentVariables['FIXTURE_VS'] = "$root\vs"
    $child = [Diagnostics.Process]::Start($p)
    $stdoutTask = $child.StandardOutput.ReadToEndAsync()
    $stderrTask = $child.StandardError.ReadToEndAsync()
    foreach ($answer in @('1','2','tester','xoxb-fixture','xapp-fixture','C123','U123')) { $child.StandardInput.WriteLine($answer) }
    $child.StandardInput.Close()
    if (-not $child.WaitForExit(30000)) { $child.Kill(); throw "Harness timeout: $case" }
    $output = $stdoutTask.Result + $stderrTask.Result
    Assert-True ($output -match 'ENVIRONMENT-RESTORED') "Environment restoration failed: $case/$presence`n$output"
    Assert-True ($output -notmatch 'secret-sentinel') 'Raw PM2 environment leaked.'
    $log = @(Get-Content $events)
    Assert-True (@($log | Where-Object { $_ -eq 'engine:prepare' }).Count -eq 1) "prepare bypassed: $case`n$output"
    Assert-True ($log -notcontains 'pm2:--version') 'PM2 version invoked before runtime preflight.'
    if ($case -eq 'success') { Assert-True ($child.ExitCode -eq 0) "Child success did not continue wizard: $output" }
    else { Assert-True ($child.ExitCode -ne 0) "Failure reported as success: $case"; Assert-True ($output -notmatch 'Nova Cortex e gata') 'False final success.' }
    if ($case -in @('prepare','prereq','check')) {
      Assert-True (-not (Test-Path "$engine\orgs")) 'Preflight failure wrote org credentials.'
      Assert-True (-not (Test-Path "$engine\templates\nova-cortex-orchestrator")) 'Preflight failure copied templates.'
    }
    if ($case -eq 'start') {
      Assert-True ($log -contains 'engine:start --org nova-tester --channel slack') 'Incorrect start arguments.'
      Assert-True ($output -match 'VISIBLE-CONSENT-start') 'Hidden runtime consent output.'
      Assert-True (-not (Test-Path "$repo\slack-bridge\.env")) 'Slack wrote after start refusal.'
    }
    if ($case -eq 'save') { Assert-True ($log -contains 'engine:save') 'Missing guarded save.'; Assert-True ($output -match 'VISIBLE-CONSENT-save') 'Hidden save consent.' }
    if ($case -eq 'unhealthy') { Assert-True ($log -notcontains 'engine:save') 'Unhealthy bridge reached save.' }
    Assert-True ($log -notcontains 'pm2:save') 'Unguarded global PM2 save.'
    Write-Host "PASS native Windows case: $case/$presence"
  }
  }
} finally {
  Remove-Item -LiteralPath $sandbox -Recurse -Force
}
