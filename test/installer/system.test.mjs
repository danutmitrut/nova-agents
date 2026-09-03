import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, realpathSync, symlinkSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import test from 'node:test';

import {findTool, InstallError, resolveNodeTool, run, samePath, validateRelease} from '../../scripts/installer/system.mjs';
import {fixtureRepo} from './fixtures.mjs';

function tempDir(t) {
  const root = mkdtempSync(join(tmpdir(), 'nova-system-test-'));
  t.after(() => import('node:fs').then(({rmSync}) => rmSync(root, {recursive: true, force: true})));
  return root;
}

function writeExecutable(path, contents = '') {
  writeFileSync(path, contents, {mode: 0o755});
}

test('process arguments are not interpreted by a shell', () => {
  const value = 'literal $HOME; & (not a command)';
  const result = run(process.execPath, ['-e', 'process.stdout.write(process.argv[1])', value], {
    cwd: tmpdir(), env: process.env, timeoutMs: 1000,
  });
  assert.equal(result.stdout, value);
});

test('a failing child cannot appear successful', () => {
  assert.throws(() => run(process.execPath, ['-e', 'process.exit(7)'], {
    cwd: tmpdir(), env: process.env, timeoutMs: 1000,
  }), {code: 'COMMAND_FAILED'});
});

test('a timed out child reports a timeout', () => {
  assert.throws(() => run(process.execPath, ['-e', 'setTimeout(() => {}, 5000)'], {
    cwd: tmpdir(), env: process.env, timeoutMs: 20,
  }), {code: 'COMMAND_TIMEOUT'});
});

test('a command without a positive explicit timeout is rejected', () => {
  assert.throws(() => run(process.execPath, ['-e', 'process.exit(0)'], {
    cwd: tmpdir(), env: process.env, timeoutMs: 0,
  }), {code: 'INVALID_TIMEOUT'});
});

test('a child that exits by SIGTERM is a failure, not a timeout', () => {
  assert.throws(() => run(process.execPath, ['-e', 'process.kill(process.pid, "SIGTERM")'], {
    cwd: tmpdir(), env: process.env, timeoutMs: 1000,
  }), {code: 'COMMAND_FAILED'});
});

test('findTool resolves a POSIX symlink in a PATH directory with spaces', (t) => {
  const root = tempDir(t);
  const bin = join(root, 'bin with spaces');
  const real = join(root, 'real-tool');
  mkdirSync(bin);
  writeExecutable(real);
  symlinkSync(real, join(bin, 'nova-tool'));

  assert.equal(findTool('nova-tool', {env: {PATH: bin}, platform: 'linux'}), realpathSync.native(real));
});

test('samePath compares resolved POSIX paths', (t) => {
  const root = tempDir(t);
  const real = join(root, 'real-tool');
  const alias = join(root, 'alias-tool');
  writeExecutable(real);
  symlinkSync(real, alias);
  assert.equal(samePath(real, alias), true);
});

test('resolveNodeTool returns the verified npm JavaScript entry point on Windows', (t) => {
  const root = tempDir(t);
  const bin = join(root, 'bin');
  const script = join(bin, 'node_modules', 'npm', 'bin', 'npm-cli.js');
  mkdirSync(join(bin, 'node_modules', 'npm', 'bin'), {recursive: true});
  writeExecutable(join(bin, 'node.exe'));
  writeFileSync(join(bin, 'npm.cmd'), '@echo off\r\n');
  writeFileSync(join(bin, 'node_modules', 'npm', 'package.json'), '{"name":"npm"}');
  writeFileSync(script, 'process.exit(0);');

  assert.deepEqual(resolveNodeTool('npm', {env: {PATH: bin}, platform: 'win32'}), {
    node: join(bin, 'node.exe'), script,
  });
});

test('a Windows npm shim associated with another package is rejected', (t) => {
  const root = tempDir(t);
  const bin = join(root, 'bin');
  mkdirSync(join(bin, 'node_modules', 'npm', 'bin'), {recursive: true});
  writeExecutable(join(bin, 'node.exe'));
  writeFileSync(join(bin, 'npm.cmd'), '@echo off\r\n');
  writeFileSync(join(bin, 'node_modules', 'npm', 'package.json'), '{"name":"not-npm"}');
  writeFileSync(join(bin, 'node_modules', 'npm', 'bin', 'npm-cli.js'), 'process.exit(0);');

  assert.throws(() => resolveNodeTool('npm', {env: {PATH: bin}, platform: 'win32'}), (error) =>
    error instanceof InstallError && error.code === 'TOOL_PROVENANCE_UNCLEAR' && error.message.includes(join(bin, 'npm.cmd')),
  );
});

test('a Windows npm executable cannot substitute for the audited cmd shim', (t) => {
  const root = tempDir(t);
  const bin = join(root, 'bin');
  mkdirSync(join(bin, 'node_modules', 'npm', 'bin'), {recursive: true});
  writeExecutable(join(bin, 'node.exe'));
  writeExecutable(join(bin, 'npm.exe'));
  writeFileSync(join(bin, 'node_modules', 'npm', 'package.json'), '{"name":"npm"}');
  writeFileSync(join(bin, 'node_modules', 'npm', 'bin', 'npm-cli.js'), 'process.exit(0);');

  assert.throws(() => resolveNodeTool('npm', {env: {PATH: bin}, platform: 'win32'}), {
    code: 'TOOL_PROVENANCE_UNCLEAR',
  });
});

test('release validation rejects malformed SHA', () => {
  assert.throws(() => validateRelease({
    schema: 1,
    repo: 'https://github.com/danutmitrut/cortextos.git',
    ref: 'refs/heads/fix/windows-telegram-submit-main-integration',
    sha: 'EE7f06f2ad687237db670118f6cdf7c6792c1572',
  }), {code: 'INVALID_RELEASE_SHA'});
});

test('release validation rejects a noncanonical remote', () => {
  assert.throws(() => validateRelease({
    schema: 1,
    repo: 'https://github.com/danutmitrut/cortextos.evil.example/cortextos.git',
    ref: 'refs/heads/fix/windows-telegram-submit-main-integration',
    sha: 'ee7f06f2ad687237db670118f6cdf7c6792c1572',
  }), {code: 'INVALID_RELEASE_REPOSITORY'});
});

test('release validation rejects a ref that only begins with a valid namespace', () => {
  assert.throws(() => validateRelease({
    schema: 1,
    repo: 'https://github.com/danutmitrut/cortextos',
    ref: 'refs/heads/feature\nuntrusted',
    sha: 'ee7f06f2ad687237db670118f6cdf7c6792c1572',
  }), {code: 'INVALID_RELEASE_REF'});
});

test('fixtureRepo creates a disposable cloned checkout with old and new commits', (t) => {
  const fixture = fixtureRepo(t);
  assert.notEqual(fixture.source, fixture.root);
  assert.notEqual(fixture.oldSha, fixture.newSha);
  assert.equal(fixture.git(['rev-parse', 'HEAD']).stdout.trim(), fixture.newSha);
  assert.equal(fixture.git(['show', `${fixture.oldSha}:package.json`]).stdout.includes('"version":"1.0.0"'), true);
  assert.equal(fixture.git(['show', `${fixture.newSha}:package.json`]).stdout.includes('"version":"2.0.0"'), true);
  assert.equal(fixture.release.sha, fixture.newSha);
});
