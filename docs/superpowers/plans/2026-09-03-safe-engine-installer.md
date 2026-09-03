# Safe Engine Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Nova install/update a verified CortextOS revision and start the correct daemon with its approved TLS trust configuration, without overwriting student changes or saving unhealthy PM2 state.

**Architecture:** A dependency-free Node installer owns engine provenance and guarded PM2 operations. Existing PowerShell/Bash entry points retain their prerequisite and onboarding UI, but call this helper instead of skipping an existing engine or executing a moving bootstrap. Small modules isolate filesystem/Git, build receipts, CA validation, and PM2/IPC lifecycle; no change to the engine hotfix is required.

**Tech Stack:** Node >=20 built-ins, Git, existing npm/PM2 installations, PowerShell 5.1/7, Bash; `node:test` for portable tests. No new npm dependencies.

## Global Constraints

- Specification: `docs/superpowers/specs/2026-09-03-safe-engine-installer-design.md`, approved 2026-09-03.
- Canonical engine repository: `https://github.com/danutmitrut/cortextos.git`.
- Initial accepted revision: `ee7f06f2ad687237db670118f6cdf7c6792c1572`; fetch ref: `refs/heads/fix/windows-telegram-submit-main-integration`.
- Do not claim the hotfix is merged to main. Do not push, merge, release, restart Dan's agents, or operate on Dorina's machine while implementing/testing locally.
- Existing tracked or untracked changes stop the installer. No automatic stash, reset, clean, remote replacement, downgrade, certificate import, or data migration.
- Preserve `.env`, orgs, instance data, crons, memory, backups and stashes. Only the wizard's existing explicit configuration flow may write its configured target files.
- Use only explicitly configured `NODE_EXTRA_CA_CERTS`; never weaken TLS or Execution Policy. Do not emit raw PM2 JSON/environment or secrets in reports/errors.
- Restart only the identified daemon with explicit interruption consent. Never save an empty/unhealthy PM2 list or silently resurrect a dump.
- Local tests must use disposable repositories and simulated processes, never the host's PM2 instance. Windows acceptance and reboot persistence remain separate evidence gates.

## Repository baseline and execution boundary

The planning checkout is `work/nova-agents`, on `main`, with the design committed as `e3070f1`. Before code, use the worktree skill: request consent for isolation if not already provided and select a non-main implementation branch. Do not create a second task in the app. The recommended branch is `fix/safe-engine-installer`.

Baseline observed 2026-09-03: `node --test slack-bridge/test/allowlist.test.js` passes 3 tests; `bash -n nova-prereq.sh nova-init.sh` passes. Host Node is 25.9.0, not the minimum supported version. There is no root package.json; do not install Slack dependencies merely to run installer tests.

## File ownership and public interfaces

New files:

- `scripts/installer/engine-release.json`: immutable release identity.
- `scripts/installer/system.mjs`: process adapter, path/tool resolution, errors; no global process mutations.
- `scripts/installer/engine.mjs`: clean-repo checks, pin/FF update, build and receipt validation.
- `scripts/installer/tls.mjs`: approved CA validation and bounded token-free TLS probe.
- `scripts/installer/pm2.mjs`: selected PM2 metadata, lifecycle policy, guarded save.
- `scripts/installer/ipc.mjs`: bounded existing engine IPC protocol, without CLI auto-start fallback.
- `scripts/nova-engine.mjs`: CLI for `prepare`, `check`, `start`, `save`; Romanian diagnostics.
- `test/installer/*.test.mjs`, `test/installer/fixtures.mjs`: behavior tests and disposable test fixtures.
- `test/installer/windows-entrypoints.test.ps1`: Windows-only entry-point behavior tests using isolated stubs.
- `docs/safe-engine-installer.md`: student-facing operation, refusal, and recovery guide.

Modified files: `nova-prereq.ps1`, `nova-prereq.sh`, `nova-init.ps1`, `nova-init.sh`, `README.md`, `CLAUDE.md`, `docs/windows-test-plan.md`. Keep Slack message processing and agent templates unchanged.

Contracts (plain JS objects, documented with JSDoc):

```js
// system.mjs
// Throws InstallError {code, message}; never includes raw child output by default.
run(command, args, {cwd, env, timeoutMs, inheritOutput}); // -> {stdout, stderr}
findTool(name, {env, platform}); // -> absolute executable/shim path or null
resolveNodeTool(name, {env, platform}); // npm|pm2 -> {node, script}
samePath(a, b); // realpath comparison where possible; Windows case folding only there

// engine.mjs
prepareEngine({root, release, env}, adapters); // -> BuildReceipt
verifyEngine({root, release, env}, adapters); // -> BuildReceipt; read-only
// receipt: {schema:1, root, sha, nodeVersion, builtAt, artifacts:{relativePath:sha256}}

// tls.mjs
validateCA(env); // -> {path: absolutePath|null}; no trust-store changes
probeTLS({hostname, node, env}, adapters); // -> Promise<void>, throws sanitized code

// pm2.mjs
readProcesses(adapters); // -> selected ProcessInfo[], never raw environment
inspectRuntime({root, instance, stateRoot, env}, adapters); // -> RuntimeSnapshot
ensureRuntime({root, instance, stateRoot, org, env, allowRestart, allowGlobalSave}, adapters);
guardedSave({root, instance, stateRoot, env, allowGlobalSave}, adapters);
// ProcessInfo: {id,name,pid,status,cwd,script,node,instance,stateRoot,frameworkRoot,
//   extraCA,pm2Home,username,restarts,startedAt,stdoutPath,stderrPath}

// ipc.mjs
sendIPC({instance, request, timeoutMs}); // -> Promise<{success,data?,error?,code?}>
```

`adapters` inject external operations only (process runner, IPC, time, output sink). Production defaults use real processes. Git/file/build tests use actual temporary files and repositories; only network/PM2/native-runtime side effects are replaced. Test helpers never become production exports.

## Task 1: Safe process/path boundaries and verified release selection

**Files:** create `scripts/installer/system.mjs`, `scripts/installer/engine-release.json`, `test/installer/system.test.mjs`, `test/installer/fixtures.mjs`.

**Consumes:** environment and filesystem. **Produces:** the `system.mjs` contract and `fixtureRepo(t)` test helper described below.

- [x] Write behavior tests first: paths with spaces, command failure/timeout, Node-tool shim resolution, conflicting executable locations, malformed SHA, noncanonical remote. A shim that resolves to another package must fail rather than execute.

```js
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
```

- [x] Run `node --test test/installer/system.test.mjs`; confirm the missing behavior fails before implementation. Do not hide import/typo errors as behavioral failures: initially export a throwing boundary if needed to exercise the assertion.
- [x] Implement `run` with `spawnSync(command,args,{shell:false,...})`, explicit timeout/maxBuffer/status checks and sanitized errors. For npm/PM2 on Windows, resolve their known JS entry points from the selected installation and execute with Node; do not send `.cmd` to `spawnSync` as though it were an executable. PowerShell callers may invoke `.cmd` directly via `&`.
- [x] Implement tool discovery from PATH using `path.delimiter`. Resolve POSIX symlinks; for Windows npm/PM2 shims, accept the installed layout only after checking the sibling package name and expected JS entry point. Fail with the discovered path when provenance is ambiguous; never evaluate shim contents.
- [x] Add the manifest:

```json
{
  "schema": 1,
  "repo": "https://github.com/danutmitrut/cortextos.git",
  "ref": "refs/heads/fix/windows-telegram-submit-main-integration",
  "sha": "ee7f06f2ad687237db670118f6cdf7c6792c1572"
}
```

Validate the full lowercase 40-hex SHA and a full `refs/heads/` or `refs/tags/` ref. URL normalization accepts HTTPS with/without `.git` and GitHub SSH for the same exact owner/repo; reject URL credentials, lookalike hosts and substring matches.
- [x] Build `fixtureRepo(t)` entirely under `mkdtempSync(join(tmpdir(),'nova-install-test-'))`: initialize Git with local test identity, create two committed versions of package.json and a tiny dependency-free build script, create a separate clone for the target, and return `{source,root,oldSha,newSha,release,git}`. `git` runs array arguments with `-C root`. Test cleanup removes only this captured temp directory via `t.after`.
- [x] Run tests green, check `git diff --check`, commit task files as `feat(installer): add safe process and release boundaries`.

## Task 2: Engine update, build provenance, and failure-safe preparation

**Files:** create `scripts/installer/engine.mjs`, `test/installer/engine.test.mjs`, initial `scripts/nova-engine.mjs`.

**Consumes:** Task 1 boundaries, fixture repo and manifest. **Produces:** `prepareEngine`, `verifyEngine` and CLI `prepare`/`check`.

- [x] Write tests reproducing the actual stale-engine failure and refusing destructive paths:

```js
test('an existing engine is fast-forwarded and built at the accepted commit', async t => {
  const f = fixtureRepo(t);
  const receipt = await prepareEngine({root:f.root, release:f.release, env:process.env}, f.adapters);
  assert.equal(f.git('rev-parse','HEAD'), f.newSha);
  assert.equal(receipt.sha, f.newSha);
  assert.equal(readFileSync(join(f.root,'dist','daemon.js'),'utf8'), 'new daemon\n');
});
test('untracked student data prevents update and is preserved', async t => {
  const f = fixtureRepo(t);
  writeFileSync(join(f.root,'student-note.txt'),'keep me');
  await assert.rejects(prepareEngine({root:f.root,release:f.release,env:process.env},f.adapters),
    {code:'DIRTY_WORKTREE'});
  assert.equal(f.git('rev-parse','HEAD'),f.oldSha);
  assert.equal(readFileSync(join(f.root,'student-note.txt'),'utf8'),'keep me');
});
```

The fixture's `adapters` keep real Git and filesystem work, replacing npm with a controlled child build script that writes the literal old/new daemon artifacts. Add fresh clone, exact version, tracked change, rename/untracked Unicode path, upstream remote, divergence/ahead, non-Git dir, global CLI/PM2 path mismatch, fetch failure, changed fetch ref, failed build and failed link cases.
- [x] Run `node --test test/installer/engine.test.mjs` and record red results for the new contracts.
- [x] Implement preflight before any mutation: resolve root (`CORTEXTOS_DIR` or homedir/cortextos), validate global command target and runtime snapshot, run `git status --porcelain=v1 -z --untracked-files=all`, verify remote identity. Reject any dirty entry with a path-only report. Preserve remote names, HEAD branch, environment and student files.
- [x] For fresh install use a no-checkout clone, fetch manifest ref, and verify the full requested SHA is a commit reachable from that fetched ref. Check out only the accepted commit. For existing install, fetch the matching remote/ref, verify reachability, and use `git merge-base --is-ancestor HEAD <sha>` before `git merge --ff-only <sha>`. Equal SHA does not advance history; all other relationships stop. Do not run `git pull`, which could select another target.
- [x] Verify `package.json.name === 'cortextos'`, lockfile exists, then run pinned checkout `npm ci`, `npm run build`, and global link without lifecycle scripts or lockfile rewriting (`npm link --ignore-scripts --package-lock=false`). Treat failed commands as fatal, with no privileged automatic fallback. Preserve executable-bit repair for node-pty's actual `spawn-helper` files on POSIX. Test that repair only targets dependency helper files.
- [x] Preserve fresh-install state setup required by the pinned engine: call `node dist/cli.js install` only for a genuinely new engine/state installation, with its nonzero exit propagated and no moving bootstrap. Keep existing state untouched on update. Review its runtime dependency behavior; do not turn Codex selection into silent forced Claude setup. If this command cannot respect runtime selection, implement only its required state-directory initialization locally and leave optional prerequisites explicitly reported.
- [x] After successful build, hash all generated `.js` and `.map` files below `dist` and store the receipt under the repo's Git administrative path (`git rev-parse --git-path nova-installer/build.json`), not as an untracked source file. Include node version and timestamp. `check` recomputes artifact hashes, compares root/SHA and validates the global link; it never repairs or rebuilds implicitly.
- [x] Failed build/link produces no new successful receipt. If source advanced, error output distinguishes source SHA from last successful build. Do not restart or save PM2. Do not claim old running processes loaded the new code.
- [x] CLI commands and exit behavior:

```sh
node scripts/nova-engine.mjs prepare
node scripts/nova-engine.mjs check
```

Exit 0 only on the requested verified stage; exit 1 with a code/path-only Romanian error otherwise. Unknown arguments fail. CLI uses the checked-in manifest only; tests may inject their fixture manifest into functions, not through a public production override.
- [x] Run all Task 1–2 tests, commit as `fix(installer): verify and fast-forward existing engine installs`.

## Task 3: Approved CA handling, PM2 identity, and guarded lifecycle

**Files:** create `scripts/installer/tls.mjs`, `scripts/installer/pm2.mjs`, `scripts/installer/ipc.mjs`, `test/installer/tls.test.mjs`, `test/installer/pm2.test.mjs`, `test/installer/ipc.test.mjs`; extend CLI.

**Consumes:** verified build receipt, selected Node/PM2 installation, root/instance/org. **Produces:** `inspectRuntime`, `ensureRuntime`, `guardedSave`, IPC adapter, CLI `start`/`save`.

- [x] Write failing tests for CA missing/valid/missing-file/relative/malformed, TLS validation disabled in environment, duplicate-case environment keys, wrong daemon root, ambiguous processes, stopped/errored status, empty list with dump, rejected restart consent, failed restart, CA missing after restart and unhealthy save:

```js
test('empty PM2 list with a previous dump requires manual recovery', async () => {
  const fixture = fakeRuntime({processes:[],dumpExists:true});
  await assert.rejects(ensureRuntime(fixture.options,fixture.adapters),
    {code:'PM2_RECOVERY_REQUIRED'});
  assert.deepEqual(fixture.mutations,[]);
});
test('a healthy daemon receives the approved CA before save', async () => {
  const fixture = fakeRuntime({healthy:true,extraCA:fixtureCertificatePath});
  await ensureRuntime({...fixture.options,allowRestart:true},fixture.adapters);
  assert.deepEqual(fixture.mutations.map(x=>x.operation),['restart','save']);
  assert.equal(fixture.mutations[0].env.NODE_EXTRA_CA_CERTS,fixtureCertificatePath);
  assert.equal(fixture.mutations[0].target,0);
});
```

`fakeRuntime` is a test-local stateful adapter: returns literal PM2 process records, updates status/env on a requested operation, records external commands, supplies controlled IPC and log deltas. It must reject unknown operations and model failed restarts without changing state. Use generated test CA files with no private keys in the repo; `fixtureCertificatePath` points to a temporary public PEM test fixture. Assertions exercise the real lifecycle coordinator, not the fake alone.
- [x] Run the three test files red. Add IPC tests using a temporary Unix socket or Windows named pipe: fragmented JSON response, rejection, connection failure, timeout, oversized response. No real daemon contact.
- [x] Implement CA validation using `X509Certificate` for every PEM certificate block and reject leftover invalid blocks/content, unreadable/relative paths and TLS bypass settings. If shell CA is absent but the existing daemon carries one, require the user to restore/confirm that config instead of silently clearing it. Do not write process/user/machine environment globally.
- [x] Implement bounded HTTPS test in a fresh child of the selected Node executable because `NODE_EXTRA_CA_CERTS` is read at startup. Probe `api.telegram.org` for Telegram, `slack.com` for Slack, without bot credentials; accept an authenticated TLS connection even for a non-2xx HTTP status. Expose only structured TLS/network error codes, no request URLs containing secrets. Timeout 10 seconds, no retry-policy changes.
- [x] Parse PM2's JSON in Node, immediately select `ProcessInfo` fields. Check username and PM2 home against current user/home and reject case-conflicting values. For the existing Nova wizard support the `default` instance; nondefault `CTX_INSTANCE_ID`/`CTX_ROOT` or mismatched framework/project paths require explicit supported selection, not silent normalization. Treat PM2 access errors as failure, not an empty list.
- [x] Implement a pre-mutation snapshot, including existing dump/dump backup presence and process identities. If a saved daemon exists but the live list lacks it, stop for controlled recovery even when unrelated live apps exist. If a live daemon is outside PM2, detect its state pid/IPC and stop instead of starting a competing process.
- [x] `ensureRuntime` revalidates receipt and snapshot, probes TLS, then starts or restarts only the selected daemon. New daemon configuration contains explicit absolute script/cwd/interpreter, `--instance default`, CTX roots/org and the approved CA; do not execute a possibly customized ecosystem file that could start unrelated apps. Restart existing daemon by numeric ID with `--update-env` only after consent. Do not change unrelated process settings.
- [x] Use the pinned engine protocol directly so a lost daemon cannot trigger `cortextos start`'s implicit start/save fallback:

```js
const request = {type:'status',source:'nova-installer'};
// Endpoint: Windows \\.\pipe\cortextos-default;
// POSIX: join(homedir(),'.cortextos','default','daemon.sock').
// Write JSON once on connect; parse response on end; 5s timeout, 1 MiB cap.
```

Cross-check `stateRoot/daemon.pid` against PM2 pid and require successful IPC plus fresh bootstrap evidence. For existing online Boss, status is enough; otherwise send `{type:'start-agent',agent:'boss',source:'nova-installer'}` and wait for actual `running` status/pid. `start-agent` acknowledgement alone is not proof of a running agent. Never mutate the enabled registry here; add-agent in the wizard must have created it.
- [x] Record stdout/stderr byte offsets before restart; read only bounded new data afterward, reject fresh TLS errors and rotated/truncated-log ambiguity. Require a fresh `[daemon] Running (pid: N)` matching the pid, unchanged PID/restart count across the verification window, correct CA in PM2 and successful IPC. Bound readiness to 30 seconds. Missing evidence is a clear incomplete/failed result, not success.
- [x] `guardedSave` re-reads process identities/health before saving, requires explicit `allowGlobalSave` when other apps exist, invokes save once, checks command success and validates saved selected daemon fields from the resulting dump. Never prints/writes a copy of the raw dump. Any changed process set between confirmation and save cancels saving.
- [x] Extend CLI with `start --org <org> --channel telegram|slack` and `save`. Prompt interactively for a running-daemon restart and any global snapshot; EOF/noninteractive input refuses the mutation. Report “saved for restore; Windows auto-start unverified”, not reboot persistence.
- [x] Run Tasks 1–3 tests green, commit as `fix(installer): preserve approved TLS trust in guarded PM2 startup`.

## Task 4: Wire entry points without bypassing checks or false success

**Files:** modify four root scripts; create `test/installer/entrypoints.test.mjs`, `test/installer/windows-entrypoints.test.ps1`; update CLI integration as needed.

**Consumes:** CLI `prepare`, `check`, `start`, `save`. **Produces:** both installer routes use the same engine policy and guarded startup.

- [x] Write behavior harnesses before script changes. Execute Bash with temporary PATH/HOME and stub external commands; run PowerShell equivalents on Windows. Simulate prerequisites installed, existing global CortextOS, and helper failure. Assert helper is still called, exit is nonzero, and template/credential/configuration writes and daemon start did not occur. Do not grep source lines as a substitute for running entry points.

```js
test('existing cortextos does not bypass failing engine preflight', async t => {
  const fixture = entrypointFixture(t,{engineExit:1,toolsInstalled:true});
  const result = fixture.runBash('nova-init.sh',['1','1']);
  assert.notEqual(result.status,0);
  assert.equal(fixture.events().filter(x=>x==='engine:prepare').length,1);
  assert.equal(fixture.events().includes('engine:start'),false);
  assert.equal(existsSync(join(fixture.engineRoot,'orgs')),false);
});
```

Define `entrypointFixture` in test utilities: copy scripts and installer files into a temp directory, create scripted executable stubs for external prerequisites, isolate HOME and PATH, provide input on stdin, collect tool events in that temp directory. The helper stub replaces only the heavy engine boundary in entry-point tests; Task 2 separately tests its real behavior. No production testing bypass flags.
- [x] Run harness red. Windows tests unavailable on macOS must be explicitly skipped with reason; do not turn parser-only checks into behavioral PASS.
- [x] Move PM2 prerequisite availability before engine runtime inspection. Replace the entire legacy engine skip/bootstrap block in both prereq scripts with the shared `prepare` call, propagating nonzero status. Use `$PSScriptRoot`/`SCRIPT_DIR`, not current working directory, for locating the helper.

```powershell
& node (Join-Path $PSScriptRoot 'scripts\nova-engine.mjs') prepare
if ($LASTEXITCODE -ne 0) { Nova-Fail 'Verificarea engine-ului a eșuat; instalarea se oprește.' }
```

```bash
node "$SCRIPT_DIR/scripts/nova-engine.mjs" prepare || nova_fail 'Verificarea engine-ului a eșuat; instalarea se oprește.'
```

- [x] Remove the Windows init condition based on `Get-Command cortextos`. Always run prerequisites as an explicit child PowerShell process with the same environment and compatible executable, propagate exit code, and avoid `exit` inside prereq terminating the successful parent wizard. Preserve the Bash behavior of running prerequisites before workspace/token prompts.
- [x] Replace bare Windows npm/PM2/CortextOS invocations with explicit resolved `.cmd` wrappers where applicable, invoked by `&`; preserve native `claude.exe` support. Scope changes to the affected installer scripts. Verify paths with spaces and exit codes.
- [x] Before template/config writes, `check` verifies receipt, root and runtime identity. A repeat wizard with existing untracked templates must refuse preflight rather than delete them; document this deliberate safety behavior. Do not add automatic ignores to make reruns appear clean.
- [x] Replace both wizard `cortextos start boss` blocks with shared `start --org <org> --channel <channel>`. Display verified daemon/Boss readiness separately from untested Telegram round-trip. A helper failure stops before Slack startup and before final success text.
- [x] Preserve Slack bridge creation behavior but replace its unguarded `pm2 save` with the same `save` helper after bridge status is checked. A global snapshot containing other apps requires confirmation; refusal leaves the snapshot unsaved and says so. This does not authorize edits to unrelated apps.
- [x] Restore installer-owned temporary env overrides in `finally`/subshell scope. Do not erase preexisting `CORTEXTOS_REPO`, CTX roots or CA configuration on exit. Replace old generic success/fallback instructions with exact phase results and the safe helper command.
- [x] Run portable tests, Bash syntax checks and available Windows harness; commit as `fix(installer): enforce engine and runtime checks in both wizards`.

## Task 5: Operator docs, review, and explicit Windows acceptance gates

**Files:** create `docs/safe-engine-installer.md`; modify `README.md`, `CLAUDE.md`, `docs/windows-test-plan.md`; maintain this plan's checkboxes and a results section.

**Consumes:** final CLI behavior and actual test evidence. **Produces:** reviewable local change, commands for field acceptance, no release by default.

- [x] Document the four helper commands, pin policy, dirty/template refusal, build-vs-runtime distinction, exact paths shown for troubleshooting, `.cmd` guidance, safe CA configuration, and empty PM2-list/dump recovery requiring operator review. Never advise posting tokens or raw dumps into chat.
- [x] Remove blanket “idempotent, always continues automatically” claims from README/CLAUDE; explain safe refusal. Distinguish code update from data migration and `pm2 save` from a configured Windows boot service.
- [x] Add this manual Windows test matrix to `docs/windows-test-plan.md`: PowerShell 5.1 and 7; fresh and clean-existing install; custom install path with spaces; `upstream` remote; dirty tracked/untracked refusal; same/newer/diverged engine; broken certificate; correct shell CA propagated to PM2; empty PM2 list with saved dump; unrelated app snapshot consent; build/link failure without restart.
- [x] Record Telegram acceptance without real secrets: short unique marker and long multiline/emoji message, exactly one inbound and visible new-message block, real turn start and correlated outbound. Get explicit approval before reboot, then verify the same build/root/CA and repeat. If no Windows machine is attached, mark this matrix NOT RUN and do not call Windows behavior fully validated.
- [x] Run local verification:

```sh
node --test test/installer/*.test.mjs slack-bridge/test/allowlist.test.js
bash -n nova-prereq.sh nova-init.sh
git diff --check
git status --short
```

Use Node 20 as an additional supported-floor test if available. On Windows run `powershell.exe -NoProfile -File test/installer/windows-entrypoints.test.ps1` and `pwsh -NoProfile -File test/installer/windows-entrypoints.test.ps1`; do not change system Execution Policy for the test.
- [x] Review the patch against the spec: no checkout/data destructive command, no shell injection path, no implicit PM2 all/save/resurrect, no moving bootstrap, no leaked env, no false online/Windows claims. Use the requesting-code-review skill for independent review when the chosen execution mode permits it. Fix findings with regression tests.
- [x] Commit reviewed docs/results as `docs(installer): document safe recovery and Windows acceptance` and use the finishing-a-development-branch skill. Leave branch/worktree and commits intact for user review; no push/PR/merge without a separate instruction.

## Plan self-review and current progress

- [x] Spec mapped to tasks: version/Git/build → 1–2; TLS/PM2/runtime → 3; all entry points and no bypass → 4; recovery, reporting, Windows acceptance → 5.
- [x] Distinct outcomes for source updated/build failed, daemon started/save refused and field test not run.
- [x] Preserved node-pty POSIX executable repair and identified fresh state setup as a required compatibility check.
- [x] No engine merge, student reinstall, antivirus change or remote write in local implementation scope.
- [x] Execution mode and worktree consent selected.
- [x] Tasks 1–5 implemented and locally verified.
- [x] Independent Task 5 review, final whole-branch review and local handoff completed. Branch retained; any integration/publication decision remains the user's.
- [ ] Windows/Telegram/reboot acceptance completed on an explicitly authorized test machine.

## Implementation results (2026-09-03)

- [x] Tasks 1–4 are implemented and their scoped reviews are clean; their final entrypoint commit is `72fa9ba`.
- [x] Task 5 documentation and plan-status fix (`b27f7cb`, `d3e32c9`) passed scoped independent review.
- [x] Controller verified `node --test test/installer/*.test.mjs slack-bridge/test/allowlist.test.js` at `72fa9ba`: 101 passed, 0 failed, 1 native-Windows skip. Bash syntax, available PowerShell parser checks, and `git diff --check` also passed.
- [x] Final whole-branch review and its one scoped fix-wave review passed. Code fix `a3badce`; durable evidence report at `a633c06`. Controller independently reran the full suite at `a633c06`: 128 passed, 0 failed, 1 native-Windows skip; Bash syntax, three PowerShell parsers and diff check passed. No push, PR, merge, release, service operation or student-machine change was performed. Branch/worktree are retained pending the user's separate integration decision.
- [ ] Native Windows PowerShell 5.1/7, Node 20, real Telegram marker roundtrip, and approved-reboot persistence remain acceptance gates. They are **NOT RUN**, not validated behavior.
