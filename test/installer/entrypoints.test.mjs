import test, { describe } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { entrypointFixture } from './entrypoint-fixtures.mjs';

const slack = ['1', '2', 'tester', 'xoxb-fixture', 'xapp-fixture', 'C123', 'U123'];
describe('Bash entrypoints', { skip: process.platform === 'win32' ? 'Bash route is POSIX-only; run native Windows harness below.' : false }, () => {
for (const script of ['nova-prereq.sh', 'nova-init.sh']) {
  test(`${script}: existing cortextos cannot bypass failed prepare`, t => {
    const f = entrypointFixture(t);
    const r = f.runBash(script, ['1', '1']);
    assert.notEqual(r.status, 0, r.stdout + r.stderr);
    assert.equal(f.events().filter(x => x === 'engine:prepare').length, 1);
    assert.equal(f.events().some(x => x.startsWith('pm2:')), false);
    assert.equal(existsSync(join(f.engineRoot, 'orgs')), false);
  });
}
test('Claude configuration waits for engine prepare', t => {
  const f = entrypointFixture(t, { runtime: 'claude' });
  assert.notEqual(f.runBash('nova-prereq.sh').status, 0);
  assert.equal(existsSync(join(f.home, '.claude/settings.json')), false);
  assert.equal(existsSync(join(f.home, '.claude.json')), false);
});
test('check refusal prevents template and credential writes', t => {
  const f = entrypointFixture(t, { failPhase: 'check' });
  const r = f.runBash('nova-init.sh', slack);
  assert.notEqual(r.status, 0);
  assert.ok(f.events().includes('engine:check'));
  assert.equal(existsSync(join(f.engineRoot, 'templates/nova-cortex-orchestrator')), false);
  assert.equal(existsSync(join(f.engineRoot, 'orgs')), false);
});
test('start failure remains visible and prevents Slack mutation and success', t => {
  const f = entrypointFixture(t, { failPhase: 'start' });
  const r = f.runBash('nova-init.sh', slack);
  assert.notEqual(r.status, 0);
  assert.ok(f.events().includes('engine:start --org nova-tester --channel slack'));
  assert.match(r.stdout, /VISIBLE-CONSENT-start/);
  assert.equal(f.events().some(x => x.startsWith('pm2:')), false);
  assert.equal(existsSync(join(f.repo, 'slack-bridge/.env')), false);
  assert.doesNotMatch(r.stdout, /Nova Cortex e gata/);
});
test('Slack health gates guarded save and save refusal stops success', t => {
  const f = entrypointFixture(t, { failPhase: 'save' });
  const r = f.runBash('nova-init.sh', slack);
  assert.notEqual(r.status, 0);
  assert.ok(f.events().includes('pm2:jlist'));
  assert.ok(f.events().includes('engine:save'));
  assert.equal(f.events().includes('pm2:save'), false);
  assert.match(r.stdout, /VISIBLE-CONSENT-save/);
  assert.doesNotMatch(r.stdout, /Nova Cortex e gata/);
});
test('unhealthy bridge prevents save', t => {
  const f = entrypointFixture(t, { failPhase: '', bridgeOnline: false });
  assert.notEqual(f.runBash('nova-init.sh', slack).status, 0);
  assert.equal(f.events().includes('engine:save'), false);
});
test('successful child preflight continues through configuration and guarded save', t => {
  const f = entrypointFixture(t, { failPhase: '' });
  const r = f.runBash('nova-init.sh', slack);
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.deepEqual(f.events().filter(x => x.startsWith('engine:')), ['engine:prepare', 'engine:check', 'engine:start --org nova-tester --channel slack', 'engine:save']);
  assert.match(readFileSync(join(f.engineRoot, 'orgs/nova-tester/agents/boss/.env'), 'utf8'), /SLACK_ALLOWED_USER=U123/);
});
test('existing template is preserved even if helper preflight allowed an ignored path', t => {
  const f = entrypointFixture(t, { failPhase: '' });
  const target = join(f.engineRoot, 'templates/nova-cortex-orchestrator');
  mkdirSync(target);
  writeFileSync(join(target, 'SOUL.md'), 'user-owned sentinel');
  const r = f.runBash('nova-init.sh', slack);
  assert.notEqual(r.status, 0);
  assert.equal(readFileSync(join(target, 'SOUL.md'), 'utf8'), 'user-owned sentinel');
  assert.equal(existsSync(join(f.engineRoot, 'orgs')), false);
});
});
test('Windows native entrypoint acceptance', { skip: process.platform !== 'win32' ? 'Requires native Windows PowerShell 5.1/7; macOS pwsh is parser-only evidence.' : false }, async () => {
  const { spawnSync } = await import('node:child_process');
  const { fileURLToPath } = await import('node:url');
  const r = spawnSync('powershell.exe', ['-NoProfile', '-File', fileURLToPath(new URL('./windows-entrypoints.test.ps1', import.meta.url))], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stdout + r.stderr);
});
