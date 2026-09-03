import {mkdtempSync, rmSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';

import {run} from '../../scripts/installer/system.mjs';

function writeVersion(root, version) {
  writeFileSync(join(root, 'package.json'), JSON.stringify({
    version,
    scripts: {build: 'node build.mjs'},
  }));
  writeFileSync(join(root, 'build.mjs'), "process.stdout.write('fixture build');\n");
}

/** Create an isolated Git source and a separate target clone for installer tests. */
export function fixtureRepo(t) {
  const directory = mkdtempSync(join(tmpdir(), 'nova-install-test-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  const source = join(directory, 'source');
  const root = join(directory, 'target');
  const commandOptions = {cwd: directory, env: process.env, timeoutMs: 5000};
  const sourceGit = (args) => run('git', ['-C', source, ...args], commandOptions);

  run('git', ['init', '-b', 'main', source], commandOptions);
  sourceGit(['config', 'user.name', 'Nova installer test']);
  sourceGit(['config', 'user.email', 'nova-installer-test@example.invalid']);
  writeVersion(source, '1.0.0');
  sourceGit(['add', 'package.json', 'build.mjs']);
  sourceGit(['commit', '-m', 'fixture old version']);
  const oldSha = sourceGit(['rev-parse', 'HEAD']).stdout.trim();

  writeVersion(source, '2.0.0');
  sourceGit(['add', 'package.json']);
  sourceGit(['commit', '-m', 'fixture new version']);
  const newSha = sourceGit(['rev-parse', 'HEAD']).stdout.trim();
  run('git', ['clone', source, root], commandOptions);

  const git = (args) => run('git', ['-C', root, ...args], commandOptions);
  return {
    source,
    root,
    oldSha,
    newSha,
    release: {schema: 1, repo: source, ref: 'refs/heads/main', sha: newSha},
    git,
  };
}
