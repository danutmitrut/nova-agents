import {accessSync, constants, existsSync, realpathSync, readFileSync, statSync} from 'node:fs';
import {delimiter, dirname, join, resolve} from 'node:path';
import {spawnSync} from 'node:child_process';

const CANONICAL_REPOSITORY = 'danutmitrut/cortextos';
const NODE_TOOL_ENTRIES = {npm: 'bin/npm-cli.js', pm2: 'bin/pm2'};

export class InstallError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'InstallError';
    this.code = code;
  }
}

function fail(code, message) {
  return new InstallError(code, message);
}

function safePath(path) {
  try {
    return realpathSync.native(path);
  } catch {
    return resolve(path);
  }
}

/** Run a command without delegating argument parsing to a shell. */
export function run(command, args, {cwd, env, timeoutMs, inheritOutput = false} = {}) {
  if (!Number.isInteger(timeoutMs) || timeoutMs <= 0) {
    throw fail('INVALID_TIMEOUT', 'Command timeout must be a positive integer');
  }
  const result = spawnSync(command, args, {
    cwd, env, encoding: 'utf8', maxBuffer: 1024 * 1024, shell: false,
    stdio: inheritOutput ? 'inherit' : 'pipe', timeout: timeoutMs,
  });
  if (result.error?.code === 'ETIMEDOUT') {
    throw fail('COMMAND_TIMEOUT', `Command timed out: ${command}`);
  }
  if (result.error || result.status !== 0 || result.signal) {
    throw fail('COMMAND_FAILED', `Command failed: ${command}`);
  }
  return {stdout: result.stdout ?? '', stderr: result.stderr ?? ''};
}

function pathParts(env, platform) {
  const pathValue = env?.PATH ?? env?.Path ?? '';
  return pathValue.split(platform === 'win32' ? ';' : delimiter).filter(Boolean);
}

function isPosixExecutable(path) {
  try {
    if (!statSync(path).isFile()) return false;
    accessSync(path, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

/** Find a tool only from the supplied PATH, resolving POSIX symlinks. */
export function findTool(name, {env = process.env, platform = process.platform} = {}) {
  const candidates = platform === 'win32' ? [`${name}.exe`, `${name}.cmd`, name] : [name];
  for (const directory of pathParts(env, platform)) {
    for (const candidate of candidates) {
      const discovered = join(directory, candidate);
      if (!existsSync(discovered)) continue;
      if (platform === 'win32') return resolve(discovered);
      if (isPosixExecutable(discovered)) return safePath(discovered);
    }
  }
  return null;
}

function packageName(packageJson) {
  try {
    return JSON.parse(readFileSync(packageJson, 'utf8')).name;
  } catch {
    return null;
  }
}

/** Resolve npm or PM2 to the audited JavaScript entry point on Windows. */
export function resolveNodeTool(name, {env = process.env, platform = process.platform} = {}) {
  if (!(name in NODE_TOOL_ENTRIES)) throw fail('UNSUPPORTED_NODE_TOOL', `Unsupported Node tool: ${name}`);
  const shim = findTool(name, {env, platform});
  if (!shim) throw fail('TOOL_NOT_FOUND', `Tool not found on PATH: ${name}`);
  if (platform !== 'win32') return {node: findTool('node', {env, platform}) ?? process.execPath, script: shim};
  if (!shim.toLowerCase().endsWith('.cmd')) {
    throw fail('TOOL_PROVENANCE_UNCLEAR', `Ambiguous ${name} shim: ${shim}`);
  }

  const packageRoot = join(dirname(shim), 'node_modules', name);
  const script = join(packageRoot, NODE_TOOL_ENTRIES[name]);
  if (packageName(join(packageRoot, 'package.json')) !== name || !existsSync(script)) {
    throw fail('TOOL_PROVENANCE_UNCLEAR', `Ambiguous ${name} shim: ${shim}`);
  }
  const node = findTool('node', {env, platform});
  if (!node) throw fail('TOOL_NOT_FOUND', `Node executable not found for ${shim}`);
  return {node, script: resolve(script)};
}

/** Compare paths after realpath resolution when available. */
export function samePath(a, b) {
  const left = safePath(a);
  const right = safePath(b);
  return process.platform === 'win32' ? left.toLowerCase() === right.toLowerCase() : left === right;
}

function canonicalRepository(remote) {
  if (remote === `git@github.com:${CANONICAL_REPOSITORY}` || remote === `git@github.com:${CANONICAL_REPOSITORY}.git`) return true;
  try {
    const url = new URL(remote);
    if (url.protocol !== 'https:' || url.username || url.password || url.hostname !== 'github.com' || url.port || url.search || url.hash) return false;
    return url.pathname.replace(/^\//, '').replace(/\.git$/, '') === CANONICAL_REPOSITORY;
  } catch {
    return false;
  }
}

/** Validate a release identity before it is used to update an engine checkout. */
export function validateRelease(release) {
  if (!release || release.schema !== 1) throw fail('INVALID_RELEASE_SCHEMA', 'Release schema must be 1');
  if (!canonicalRepository(release.repo)) throw fail('INVALID_RELEASE_REPOSITORY', 'Release repository is not canonical');
  if (typeof release.ref !== 'string' || !/^refs\/(heads|tags)\/[^\s]+$/.test(release.ref)) throw fail('INVALID_RELEASE_REF', 'Release ref must be a full heads or tags ref');
  if (typeof release.sha !== 'string' || !/^[0-9a-f]{40}$/.test(release.sha)) throw fail('INVALID_RELEASE_SHA', 'Release SHA must be 40 lowercase hexadecimal characters');
  return Object.freeze({...release});
}
