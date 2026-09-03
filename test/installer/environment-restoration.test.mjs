import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

const pwsh = process.platform === 'win32' ? 'powershell.exe' : '/Users/danmitrut/.local/bin/pwsh';
for (const script of ['nova-init.ps1', 'nova-prereq.ps1']) {
    const source = readFileSync(new URL('../../' + script, import.meta.url), 'utf8');
    const start = source.indexOf(script === 'nova-init.ps1' ? '$novaOriginalRuntime =' : '$novaOriginalEnvironment =');
    const capture = source.slice(start, source.indexOf('try {', start));
    const cleanup = source.slice(source.lastIndexOf('} finally {') + 1);
    for (const present of [true, false]) for (const failure of [true, false]) {
        test(`${script} restores ${present ? 'original sentinels' : 'absence'} after ${failure ? 'failure' : 'success'} (portable cleanup block)`, { skip: process.platform !== 'win32' && !existsSync(pwsh) }, () => {
            // The real capture/finally blocks surround deterministic work; no native installer or services.
            const code = `
# macOS environment keys are case-sensitive; emulate Windows' single Path key.
if ($env:OS -ne 'Windows_NT') { $env:Path = $env:PATH; Remove-Item Env:PATH }
$keys = @('NOVA_AGENT_RUNTIME','CTX_FRAMEWORK_ROOT','CTX_ROOT','CTX_PROJECT_ROOT','CTX_INSTANCE_ID','NODE_EXTRA_CA_CERTS','CORTEXTOS_REPO','Path')
foreach ($key in $keys) { if ($key -ne 'Path') { [Environment]::SetEnvironmentVariable($key, ${present ? "('sentinel-' + $key)" : '$null'}, 'Process') } }
$before = @{}
foreach ($key in $keys) { $before[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
${capture}
try {
    try {
        $env:Path = 'temporary-path'
        ${script === 'nova-prereq.ps1' ? "foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key, 'temporary', 'Process') }" : "$env:NOVA_AGENT_RUNTIME = 'temporary'; $env:CTX_FRAMEWORK_ROOT = 'temporary'"}
        ${failure ? "throw 'controlled-work-failure'" : ''}
    } ${cleanup}
} catch { if ($_.Exception.Message -ne 'controlled-work-failure') { throw } }
foreach ($key in $keys) {
    if ([Environment]::GetEnvironmentVariable($key, 'Process') -cne $before[$key]) { throw ('Not restored: ' + $key) }
}
Write-Output 'RESTORED'
`;
            const r = spawnSync(pwsh, ['-NoProfile', '-Command', code], { encoding: 'utf8', timeout: 10000 });
            assert.equal(r.status, 0, r.stdout + r.stderr);
            assert.match(r.stdout, /RESTORED/);
        });
    }
}
