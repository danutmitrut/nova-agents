import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const pwsh = process.platform === 'win32' ? 'powershell.exe' : '/Users/danmitrut/.local/bin/pwsh';
const source = readFileSync(new URL('../../nova-init.ps1', import.meta.url), 'utf8');
// Execute the real selection block with only the PM2 process boundary replaced.
const block = source.slice(source.indexOf('      $bridgeJson = & $Pm2Cmd jlist'), source.indexOf("      & node (Join-Path $PSScriptRoot 'scripts\\nova-engine.mjs') save"));
const record = { name: 'nova-slack-bridge', pm2_env: { status: 'online', username: 'student', USERNAME: 'student', env: { USERNAME: 'student', SLACK_BOT_TOKEN: 'secret-sentinel' } } };
for (const [name, records, ok] of [
    ['Windows metadata', [record], true],
    ['duplicate bridge', [record, record], false],
    ['offline bridge', [{ ...record, pm2_env: { ...record.pm2_env, status: 'errored' } }], false],
    ['missing bridge', [], false],
    ['malformed JSON', null, false],
]) {
    test(`PowerShell Slack selector: ${name} (portable block, not native acceptance)`, { skip: process.platform !== 'win32' && !existsSync(pwsh) }, () => {
        const json = records === null ? '{bad' : JSON.stringify(records);
        const scriptRoot = fileURLToPath(new URL('../../', import.meta.url)).replaceAll("'", "''");
        const code = `$PSScriptRoot = '${scriptRoot}'\nfunction Nova-Fail($message) { throw $message }\nfunction Fixture-Pm2 { $global:LASTEXITCODE = 0; '${json}' }\n$Pm2Cmd = 'Fixture-Pm2'\ntry {\n${block}\nWrite-Output 'SELECTED'; exit 0\n} catch { Write-Output 'REFUSED'; exit 1 }`;
        const r = spawnSync(pwsh, ['-NoProfile', '-Command', code], { encoding: 'utf8', timeout: 10000 });
        assert.equal(r.status, ok ? 0 : 1, r.stdout + r.stderr);
        assert.doesNotMatch(r.stdout + r.stderr, /secret-sentinel|USERNAME/);
    });
}
