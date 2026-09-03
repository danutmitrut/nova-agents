import { existsSync, mkdtempSync, mkdirSync, cpSync, writeFileSync, readFileSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

export function entrypointFixture(t, { failPhase = 'prepare', runtime = 'codex', bridgeOnline = true } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'nova entrypoints '));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const repo = join(root, 'repo with spaces'), home = join(root, 'home'), bin = join(root, 'bin');
  const engineRoot = join(home, 'cortextos');
  for (const path of [repo, home, bin, join(repo, 'scripts'), join(engineRoot, 'templates'), join(home, '.codex'), join(home, '.claude')]) mkdirSync(path, { recursive: true });
  for (const script of ['nova-init.sh', 'nova-prereq.sh']) cpSync(new URL('../../' + script, import.meta.url), join(repo, script));
  for (const dir of ['templates', 'slack-bridge']) cpSync(new URL('../../' + dir, import.meta.url), join(repo, dir), { recursive: true });
  writeFileSync(join(home, '.codex/auth.json'), '{}');
  writeFileSync(join(home, '.claude/.credentials.json'), '{}');
  const eventsPath = join(root, 'events');
  writeFileSync(eventsPath, '');
  const executable = (name, content) => writeFileSync(join(bin, name), '#!/bin/bash\n' + content, { mode: 0o755 });
  for (const name of ['bash', 'dirname', 'head', 'grep', 'tr', 'basename', 'cp', 'chmod', 'sed', 'mv', 'mkdir', 'cat']) symlinkSync((existsSync('/bin/' + name) ? '/bin/' : '/usr/bin/') + name, join(bin, name));
  executable('uname', 'echo Darwin');
  executable('clear', 'exit 0');
  for (const name of ['brew', 'codex', 'claude', 'jq', 'npm', 'pm2', 'cortextos', 'curl', 'sudo']) {
    executable(name, `echo '${name}:'"$*" >> "$EVENTS"\n` + (name === 'cortextos' ? `if [[ "$1" == init ]]; then mkdir -p "$CORTEXTOS_DIR/orgs/$2/agents/boss"; echo '# fixture' > "$CORTEXTOS_DIR/orgs/$2/agents/boss/.env"; fi\n` : '') + (name === 'pm2' ? `if [[ "$1" == jlist ]]; then echo '[{"name":"nova-slack-bridge","pm2_env":{"status":"${bridgeOnline ? 'online' : 'errored'}"}}]'; fi\n` : 'echo fixture\n') + 'exit 0');
  }
  symlinkSync(process.execPath, join(bin, 'node'));
  writeFileSync(join(repo, 'scripts/nova-engine.mjs'), `import { appendFileSync } from 'node:fs';\nappendFileSync(process.env.EVENTS, 'engine:' + process.argv.slice(2).join(' ') + '\\n');\nconsole.log('VISIBLE-CONSENT-' + process.argv[2]);\nprocess.exit(process.argv[2] === process.env.FAIL_PHASE ? 9 : 0);\n`);
  const env = { PATH: bin, HOME: home, CORTEXTOS_DIR: engineRoot, EVENTS: eventsPath, FAIL_PHASE: failPhase, NOVA_AGENT_RUNTIME: runtime, TERM: 'dumb' };
  return { root, repo, home, engineRoot, events: () => readFileSync(eventsPath, 'utf8').trim().split('\n'), runBash: (script, input = []) => spawnSync('/bin/bash', [join(repo, script)], { cwd: root, env: { ...env, ...(script === 'nova-init.sh' ? { NOVA_AGENT_RUNTIME: '' } : {}) }, input: input.join('\n') + '\n', encoding: 'utf8', timeout: 15000 }) };
}
