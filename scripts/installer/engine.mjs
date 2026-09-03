import { existsSync, readFileSync, writeFileSync, mkdirSync, readdirSync, lstatSync, chmodSync, renameSync, realpathSync } from 'node:fs';
import { join, resolve, dirname, relative } from 'node:path';
import { homedir } from 'node:os';
import { createHash, randomBytes } from 'node:crypto';
import * as system from './system.mjs';
import { phaseOutcome } from './outcome.mjs';
const fail = (code, paths = []) => new system.InstallError(code, `${code}${paths.length ? ': ' + paths.map(p => JSON.stringify(p)).join(', ') : ''}`);
function context(options, adapters) {
  const env = options.env ?? process.env;
  const root = resolve(options.root ?? env.CORTEXTOS_DIR ?? join(homedir(), 'cortextos'));
  const defaultState = join(homedir(), '.cortextos', 'default');
  if ((env.CTX_INSTANCE_ID && env.CTX_INSTANCE_ID !== 'default') || (env.CTX_ROOT && !system.samePath(env.CTX_ROOT, defaultState))) {
    throw fail('UNSUPPORTED_INSTANCE');
  }
  return { ...system, ...adapters, root, env, stateRoot: resolve(options.stateRoot ?? defaultState), release: system.validateRelease(options.release) };
}

function git(c, args) {
  return c.run('git', args, { cwd: c.root, env: c.env, timeoutMs: 120000 }).stdout;
}

function attempt(code, fn) {
  try {
    return fn();
  } catch {
    throw fail(code);
  }
}

function dirtyPaths(output) {
  const fields = output.split('\0');
  const paths = [];
  for (let i = 0; i < fields.length; i++) {
    if (!fields[i]) {
      continue;
    }
    const status = fields[i].slice(0, 2);
    paths.push(fields[i].slice(3));
    if (/[RC]/.test(status)) {
      paths.push(fields[++i]);
    }
  }
  return paths;
}

function clean(c, untracked) {
  const paths = dirtyPaths(git(c, ['status', '--porcelain=v1', '-z', untracked ? '--untracked-files=all' : '--untracked-files=no']));
  if (paths.length) {
    throw fail('DIRTY_WORKTREE', paths);
  }
}

function remote(c) {
  const names = git(c, ['remote']).trim().split('\n').filter(Boolean);
  for (const name of names) {
    const urls = git(c, ['remote', 'get-url', '--all', name]).trim().split('\n');
    // Read raw config: get-url applies insteadOf and can obscure repository identity.
    const raw = git(c, ['config', '--get-all', `remote.${name}.url`]).trim().split('\n');
    if (urls.length !== 1 || raw.length !== 1) {
      continue;
    }
    try {
      system.validateRelease({ ...c.release, repo: raw[0] });
      return name;
    } catch { }
  }
  throw fail('REMOTE_MISMATCH');
}

function windowsShimTarget(tool) {
  // npm/cmd-shim's node-without-arguments wrapper. Compare the whole program,
  // not a target substring: extra batch commands or altered branches must fail.
  // Unknown npm wrapper versions require review, never execution to discover intent.
  const expected = [
    '@ECHO off', 'GOTO start', ':find_dp0', 'SET dp0=%~dp0', 'EXIT /b',
    ':start', 'SETLOCAL', 'CALL :find_dp0', '',
    'IF EXIST "%dp0%\\node.exe" (', '  SET "_prog=%dp0%\\node.exe"',
    ') ELSE (', '  SET "_prog=node"', '  SET PATHEXT=%PATHEXT:;.JS;=;%', ')', '',
    'endLocal & goto #_undefined_# 2>NUL || title %COMSPEC% & "%_prog%"  "%dp0%\\node_modules\\cortextos\\dist\\cli.js" %*', '',
  ].join('\n');
  let content;
  try {
    regular(tool);
    content = readFileSync(tool, 'utf8').replace(/\r\n/g, '\n');
  } catch {
    throw fail('GLOBAL_LINK_MISMATCH', [tool]);
  }
  if (content !== expected) {
    throw fail('GLOBAL_LINK_MISMATCH', [tool]);
  }
  return join(dirname(tool), 'node_modules', 'cortextos', 'dist', 'cli.js');
}

function link(c, required) {
  const platform = c.platform ?? process.platform;
  const tool = c.findTool('cortextos', { env: c.env, platform });
  if (!tool) {
    if (required) {
      throw fail('GLOBAL_LINK_MISSING');
    }
    return;
  }
  let target = tool;
  if (platform === 'win32') {
    if (!tool.toLowerCase().endsWith('.cmd')) {
      throw fail('GLOBAL_LINK_MISMATCH', [tool]);
    }
    target = windowsShimTarget(tool);
  }
  if (!system.samePath(target, join(c.root, 'dist', 'cli.js'))) {
    throw fail('GLOBAL_LINK_MISMATCH', [tool]);
  }
}

async function preflight(c, strict) {
  for (const path of [c.stateRoot, join(c.stateRoot, 'config'), join(c.stateRoot, 'state')]) {
    let stat;
    try {
      stat = lstatSync(path);
    } catch (error) {
      if (error.code === 'ENOENT') {
        continue;
      }
      throw fail('UNSAFE_STATE', [path]);
    }
    if (stat.isSymbolicLink() || !stat.isDirectory()) {
      throw fail('UNSAFE_STATE', [path]);
    }
  }
  for (const path of ['.env', 'config/enabled-agents.json', 'config/bus-signing-key']) {
    const full = join(c.stateRoot, path);
    try {
      const stat = lstatSync(full);
      if (stat.isSymbolicLink() || !stat.isFile()) {
        throw fail('UNSAFE_STATE', [full]);
      }
    } catch (error) {
      if (error.code !== 'ENOENT') {
        throw error;
      }
    }
  }
  link(c, false);
  if (typeof c.inspectRuntime !== 'function') {
    throw fail('RUNTIME_INSPECTION_REQUIRED');
  }
  await c.inspectRuntime({ root: c.root, stateRoot: c.stateRoot, instance: 'default', env: c.env }, c);
  if (!existsSync(c.root)) {
    return false;
  }
  const top = attempt('NOT_ENGINE_REPOSITORY', () => git(c, ['rev-parse', '--show-toplevel']).trim());
  if (!system.samePath(top, c.root)) {
    throw fail('NOT_ENGINE_REPOSITORY', [c.root]);
  }
  clean(c, strict);
  remote(c);
  return true;
}

function regular(path) {
  const stat = lstatSync(path);
  if (!stat.isFile() || stat.isSymbolicLink()) {
    throw fail('UNSAFE_FILE', [path]);
  }
}

function artifacts(c) {
  const result = {};
  const walk = path => {
    for (const entry of readdirSync(path, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const full = join(path, entry.name);
      if (entry.isSymbolicLink()) {
        throw fail('UNSAFE_ARTIFACT', [full]);
      }
      if (entry.isDirectory()) {
        walk(full);
      } else if (/\.(js|map)$/.test(entry.name)) {
        result[relative(c.root, full).split('\\').join('/')] = createHash('sha256').update(readFileSync(full)).digest('hex');
      }
    }
  };
  if (!existsSync(join(c.root, 'dist'))) {
    throw fail('ARTIFACT_MISSING');
  }
  walk(join(c.root, 'dist'));
  if (!result['dist/daemon.js'] || !result['dist/cli.js']) {
    throw fail('ARTIFACT_MISSING');
  }
  return result;
}

function receiptPath(c) {
  return resolve(c.root, git(c, ['rev-parse', '--git-path', 'nova-installer/build.json']).trim());
}

function lastReceipt(c) {
  try {
    return JSON.parse(readFileSync(receiptPath(c), 'utf8'));
  } catch {
    return null;
  }
}

function repairHelpers(c) {
  if (process.platform === 'win32') {
    return;
  }
  const base = join(c.root, 'node_modules', 'node-pty');
  if (!existsSync(base) || lstatSync(base).isSymbolicLink()) {
    return;
  }
  const walk = path => {
    for (const entry of readdirSync(path, { withFileTypes: true })) {
      const full = join(path, entry.name);
      if (entry.isDirectory()) {
        walk(full);
      } else if (entry.isFile() && entry.name === 'spawn-helper') {
        chmodSync(full, lstatSync(full).mode | 0o111);
      }
    }
  };
  walk(base);
}

function initializeState(c) {
  if (existsSync(c.stateRoot)) {
    if (lstatSync(c.stateRoot).isSymbolicLink() || !lstatSync(c.stateRoot).isDirectory()) {
      throw fail('UNSAFE_STATE', [c.stateRoot]);
    }
    return;
  }
  // mkdir without recursive at the final root prevents racing into an existing state tree.
  mkdirSync(dirname(c.stateRoot), { recursive: true, mode: 0o700 });
  mkdirSync(c.stateRoot, { mode: 0o700 });
  for (const path of ['config', 'state', 'state/oauth', 'state/usage', 'inbox', 'inflight', 'processed', 'outbox', 'logs', 'orgs']) {
    mkdirSync(join(c.stateRoot, path), { mode: 0o700 });
  }
  for (const [path, value] of Object.entries({ 'config/enabled-agents.json': '{}\n', '.env': `CTX_INSTANCE_ID=default\nCTX_ROOT=${c.stateRoot}\n`, 'config/bus-signing-key': randomBytes(32).toString('hex') + '\n' })) {
    writeFileSync(join(c.stateRoot, path), value, { mode: 0o600, flag: 'wx' });
  }
}

/** Strict update/build. inspectRuntime is required until the CLI wires the PM2 boundary. */
export async function prepareEngine(options, adapters = {}) {
  const c = context(options, adapters);
  const existed = await preflight(c, true);
  if (!existed) {
    mkdirSync(dirname(c.root), { recursive: true });
    attempt('CLONE_FAILED', () => c.run('git', ['clone', '--no-checkout', c.release.repo, c.root], { cwd: dirname(c.root), env: c.env, timeoutMs: 120000 }));
  }
  const selected = remote(c);
  attempt('FETCH_FAILED', () => git(c, ['fetch', '--no-tags', selected, c.release.ref]));
  attempt('RELEASE_NOT_REACHABLE', () => {
    git(c, ['cat-file', '-e', `${c.release.sha}^{commit}`]);
    git(c, ['merge-base', '--is-ancestor', c.release.sha, 'FETCH_HEAD']);
  });
  if (existed) {
    attempt('NON_FAST_FORWARD', () => git(c, ['merge-base', '--is-ancestor', 'HEAD', c.release.sha]));
    git(c, ['merge', '--ff-only', c.release.sha]);
  } else {
    git(c, ['checkout', '--detach', c.release.sha]);
  }
  const sourceSha = git(c, ['rev-parse', 'HEAD']).trim();
  if (sourceSha !== c.release.sha) {
    throw fail('SOURCE_SHA_MISMATCH');
  }
  const last = lastReceipt(c);
  try {
    regular(join(c.root, 'package.json'));
    regular(join(c.root, 'package-lock.json'));
    if (JSON.parse(readFileSync(join(c.root, 'package.json'), 'utf8')).name !== 'cortextos') {
      throw fail('PACKAGE_MISMATCH');
    }
    const npm = c.resolveNodeTool('npm', { env: c.env });
    const command = args => c.run(npm.node, [npm.script, ...args], { cwd: c.root, env: c.env, timeoutMs: 600000 });
    attempt('BUILD_FAILED', () => {
      command(['ci']);
      repairHelpers(c);
      command(['run', 'build']);
    });
    const hashes = artifacts(c);
    attempt('LINK_FAILED', () => command(['link', '--ignore-scripts', '--package-lock=false']));
    link(c, true);
    initializeState(c);
    clean(c, true);
    const receipt = { schema: 1, root: realpathSync(c.root), sha: sourceSha, nodeVersion: process.version, builtAt: new Date().toISOString(), artifacts: hashes };
    const path = receiptPath(c);
    mkdirSync(dirname(path), { recursive: true });
    const temporary = path + '.' + randomBytes(8).toString('hex') + '.tmp';
    writeFileSync(temporary, JSON.stringify(receipt, null, 2) + '\n', { flag: 'wx', mode: 0o600 });
    renameSync(temporary, path);
    return { ...receipt, outcome: phaseOutcome(c, receipt) };
  } catch (error) {
    const safe = error instanceof system.InstallError ? error : fail('PREPARE_FAILED');
    safe.sourceSha = sourceSha;
    safe.lastSuccessfulSha = last?.sha ?? null;
    safe.outcome = phaseOutcome(c, { sha: sourceSha }, { build: 'failed' });
    throw safe;
  }
}

/** Read-only provenance check; harmless untracked wizard templates are allowed. */
export async function verifyEngine(options, adapters = {}) {
  const c = context(options, adapters);
  if (!await preflight(c, false)) {
    throw fail('NOT_ENGINE_REPOSITORY');
  }
  const receipt = lastReceipt(c);
  if (!receipt || receipt.schema !== 1) {
    throw fail('BUILD_RECEIPT_MISSING');
  }
  if (!system.samePath(receipt.root, c.root) || receipt.sha !== c.release.sha || git(c, ['rev-parse', 'HEAD']).trim() !== receipt.sha) {
    throw fail('BUILD_RECEIPT_MISMATCH');
  }
  if (JSON.stringify(artifacts(c)) !== JSON.stringify(receipt.artifacts)) {
    throw fail('ARTIFACT_MISMATCH');
  }
  link(c, true);
  return { ...receipt, outcome: phaseOutcome(c, receipt) };
}
