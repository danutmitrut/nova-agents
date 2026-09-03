# Final review fix wave

Date: 2026-09-03. Base: `d3e32c9`. Implementation commit: `a3badce57232966ae40b40a5a2715d88c74a1de6` (`fix(installer): handle Windows PM2 metadata and report verified phases`). This report is a follow-up documentation-only commit so it can name the immutable implementation commit.

## Result and scope

All four findings in `final-fix-brief.md` addressed in one scoped wave. Final portable suite: **129 tests, 128 passed, 0 failed, 1 native Windows skip**. Native Windows, Telegram/Slack roundtrip, reboot/autostart and publication remain pending. Controller owns the scoped re-review and final verification/finish. No plan gates were marked complete and no historical task briefs were edited.

Read first: final-fix brief, binding contracts, integration notes, approved design including the final phase-report contract. Used TDD instructions and verification-before-completion. No subagents. No host PM2 client, real daemon IPC, TLS/network request, certificate-store change, global installation, student-machine action, push, PR, merge or release was performed. Tests used disposable repositories, simulated process adapters and a disposable local IPC socket. Read-only memory registry lookup had no matching installer entry and supplied no implementation facts.

## Changes

1. **Windows PM2 metadata:** `select` separates only the lowercase `username` metadata field from flattened environment validation. It retains that authoritative metadata for user identity. Nested actual environment remains fully validated; flattened and merged environments still reject case conflicts, including equal-value security-key duplicates. Exact flat/nested security disagreements and TLS bypasses still fail closed. Realistic username/USERNAME jlist and flattened dump fixtures now cover existing installs and fresh-start health/save.
2. **PowerShell Slack verification:** removed whole-jlist PowerShell JSON parsing. A small Node stdin selector accepts exactly one online `nova-slack-bridge`, emits only `online`, and returns nonzero for invalid/missing/duplicate/offline records. The script path is passed as a normal argument, avoiding an inline JavaScript quoting dependency on Windows PowerShell 5.1 and `.cmd` shims. The caller still checks PM2 and Node exit codes before guarded save. Raw PM2 environment is not displayed.
3. **Environment sentinels:** Bash caller snapshots cover present and absent CTX/CA/repository values after success, prepare failure and start failure. Eight portable tests execute the real PowerShell capture/finally blocks around controlled success/throw cases. The native harness additionally wraps each complete entrypoint invocation in an environment observer; seven cases run with values present and absent (14 planned native cases). No production restoration defect was established or changed.
4. **Phase reports:** allowlisted outcomes distinguish resolved engine root, requested/source SHA, verified/failed/unverified build, CA absent/configured-but-not-validated/validated-and-propagated, daemon/Boss evidence, verified saved state, and reason when save is not verified. Prepare/check do not claim CA validation or runtime readiness. Runtime success reports follow CA validation, exact process health, Boss readiness and dump verification. Build-stage failure includes updated source evidence without reusing old build success. Generic refusal reports remain conservative. Telegram/Slack roundtrip and Windows autostart are explicitly never verified by these outcomes.

## Additive interfaces and compatibility

- `prepareEngine` and `verifyEngine` still return all existing BuildReceipt fields; they add an in-memory `outcome`. The receipt persisted under `.git/nova-installer/build.json` retains its previous schema and content fields, with no reporting data added.
- Post-source preparation errors retain `sourceSha` and `lastSuccessfulSha` and add `outcome` with failed build evidence. Earlier failures use conservative CLI fallback evidence.
- `guardedSave` and, through it, `ensureRuntime` preserve `{saved: true, autoStartVerified: false}` and add `outcome` after all existing save checks.
- `main` preserves its numeric 0/1 return/exit contract and command/consent interfaces. The CLI selects printable outcome fields explicitly rather than serializing arbitrary objects. Adapters without an outcome get conservative unverified output, not a fabricated readiness claim.
- `scripts/installer/outcome.mjs`: `phaseOutcome(context, receipt, {build, runtime})` returns only `{root, requestedSha, sourceSha, build, ca, daemon, boss, saved, saveReason, autoStartVerified, channelRoundtripVerified}`. `runtime: true` is used only after successful guarded save. `saved: false` means no verified save; printed wording deliberately says “salvare neverificată”, not that a partially failed operation could not have written a dump.
- `scripts/installer/slack-status.mjs`: standalone stdin JSON -> constant `online`/exit 0, or no payload/exit 1. No PM2 invocation or external effects.

## Modified files

Production:

- `nova-init.ps1`
- `scripts/nova-engine.mjs`
- `scripts/installer/engine.mjs`
- `scripts/installer/pm2.mjs`
- `scripts/installer/outcome.mjs` (new)
- `scripts/installer/slack-status.mjs` (new)

Regression/harness:

- `test/installer/cli.test.mjs`
- `test/installer/engine.test.mjs`
- `test/installer/pm2.test.mjs`
- `test/installer/entrypoint-fixtures.mjs`
- `test/installer/entrypoints.test.mjs`
- `test/installer/windows-entrypoints.test.ps1`
- `test/installer/environment-restoration.test.mjs` (new)
- `test/installer/slack-selector.test.mjs` (new)

Documentation: this report only. In particular, `nova-init.sh:394` and the engine/runtime behavior outside the findings were not changed.

## Exact test commands and observed output

All commands ran in `/Users/danmitrut/Documents/Codex/2026-09-02/skill-creator-users-danmitrut-codex-skills/work/nova-agents/.worktrees/safe-engine-installer`. Aggregate and failure excerpts below are copied from observed output; per-test durations omitted except aggregate duration where included.

### RED 1 — metadata and PowerShell parser

```text
node --test test/installer/pm2.test.mjs test/installer/slack-selector.test.mjs
✖ Windows username metadata survives existing jlist and dump through guarded save
✖ Windows username metadata survives fresh start through guarded save
✖ PowerShell Slack selector: Windows metadata (portable block, not native acceptance)
ℹ tests 45
ℹ suites 0
ℹ pass 42
ℹ fail 3
ℹ cancelled 0
ℹ skipped 0
ℹ todo 0
ℹ duration_ms 1231.967958
```

Exit 1. Both PM2 failures were `InstallError: ENV_CASE_CONFLICT`; PowerShell returned `REFUSED`, actual exit 1 versus expected 0. The three explicit actual-environment conflict tests passed before and after the fix.

### GREEN 1

```text
node --test test/installer/pm2.test.mjs test/installer/slack-selector.test.mjs
ℹ tests 45
ℹ suites 0
ℹ pass 45
ℹ fail 0
ℹ cancelled 0
ℹ skipped 0
ℹ todo 0
ℹ duration_ms 1134.67125
```

Exit 0. After extracting the Node selector from inline JavaScript to the Windows-safe file-path invocation, `node --test test/installer/slack-selector.test.mjs` again returned exit 0: 5 tests, 5 pass, 0 fail, 0 skipped (duration 1352.995834 ms).

### RED 2 — phase report contract

```text
node --test --test-name-pattern='outcome|outcomes|persistent PM2|allowlisted phase' test/installer/engine.test.mjs test/installer/pm2.test.mjs test/installer/cli.test.mjs
✖ CLI prints allowlisted phase evidence without leaking adapter/environment fields
✖ build outcomes distinguish verified source from runtime not yet checked
✖ build failure outcome never labels the updated source as a verified build
✖ persistent PM2 dump without live pm_id validates successfully
ℹ tests 4
ℹ suites 0
ℹ pass 0
ℹ fail 4
ℹ cancelled 0
ℹ skipped 0
ℹ todo 0
ℹ duration_ms 922.001667
```

Exit 1: missing phase text and `undefined` outcome fields, not fixture/process failures.

### GREEN 2

```text
node --test --test-name-pattern='outcome|outcomes|persistent PM2|allowlisted phase' test/installer/engine.test.mjs test/installer/pm2.test.mjs test/installer/cli.test.mjs
ℹ tests 4
ℹ suites 0
ℹ pass 4
ℹ fail 0
ℹ cancelled 0
ℹ skipped 0
ℹ todo 0
ℹ duration_ms 976.890625
```

Exit 0.

### Sentinel coverage and test-harness corrections

`node --test test/installer/environment-restoration.test.mjs test/installer/entrypoints.test.mjs` initially reported 24 tests/13 pass/10 fail/1 skip because the new harness accidentally supplied an inherited runtime while retaining the interactive runtime answer, and used macOS case-sensitive `PATH` against production Windows `Path`. After fixing the interactive fixture, 24 tests/19 pass/4 fail/1 skip remained: the portable prereq simulation had introduced both `PATH` and `Path`, unlike Windows. Normalizing to one `Path` key in that portable simulation resolved it. These were **test harness failures, not production RED evidence**; restoration production code was untouched.

```text
node --test test/installer/environment-restoration.test.mjs
ℹ tests 8
ℹ suites 0
ℹ pass 8
ℹ fail 0
ℹ cancelled 0
ℹ skipped 0
ℹ todo 0
ℹ duration_ms 1773.80575
```

Exit 0. All six Bash sentinel cases also passed in the complete suite.

### Whole portable suite — sandbox limitation, then authorized rerun

Exact command for both runs:

```text
node --test test/installer/*.test.mjs slack-bridge/test/allowlist.test.js
```

First, sandboxed run: exit 1, 129 tests/127 pass/1 fail/1 skip. Sole failure: `IPC handles fragmented response, rejection, timeout, size and connection failure`, `listen EPERM: operation not permitted` at disposable `/var/folders/.../nova-ipc-oKobPx/s`. No production socket or daemon was addressed.

Reran the same command with approved `sandbox_permissions=require_escalated`, solely to allow the disposable local IPC fixture to listen. Output:

```text
✔ IPC handles fragmented response, rejection, timeout, size and connection failure
ℹ tests 129
ℹ suites 1
ℹ pass 128
ℹ fail 0
ℹ cancelled 0
ℹ skipped 1
ℹ todo 0
ℹ duration_ms 20395.575584
```

Exit 0. The skip is `Windows native entrypoint acceptance`. Expected negative CLI-test diagnostics such as consent refusal and invalid arguments are intentional test output, not suite failures.

### Syntax, whitespace and environment

```text
bash -n nova-prereq.sh nova-init.sh
git diff --check
node --check scripts/installer/outcome.mjs
node --check scripts/installer/pm2.mjs
node --check scripts/installer/engine.mjs
node --check scripts/nova-engine.mjs
node --check scripts/installer/slack-status.mjs
```

All exit 0, no output.

```powershell
/Users/danmitrut/.local/bin/pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString(); $files = @("nova-init.ps1", "nova-prereq.ps1", "test/installer/windows-entrypoints.test.ps1"); foreach ($file in $files) { $tokens = $null; $errors = $null; [System.Management.Automation.Language.Parser]::ParseFile((Join-Path (Get-Location) $file), [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count) { $errors | Format-List; exit 1 }; Write-Output "PARSE OK: $file" }'
```

Exit 0:

```text
7.6.5
PARSE OK: nova-init.ps1
PARSE OK: nova-prereq.ps1
PARSE OK: test/installer/windows-entrypoints.test.ps1
```

Host Node (`node --version`): `v25.9.0`. Local PowerShell is macOS 7.6.5; its real selector/cleanup block execution is portable evidence only, not whole-entrypoint Windows acceptance or PowerShell 5.1 evidence. Minimum Node 20 acceptance remains unrun.

## Self-review and remaining concerns/gates

- Reviewed metadata exception interactions with nested/merged case conflicts, authoritative username absence/user identity, CA disagreement, TLS bypass, prior dump recovery, exact interpreter/root identity, consent, readiness deadline, Boss stop during save, process-set drift, and persistent dump lacking live `pm_id`. Existing refusal/regression tests stayed green.
- Reviewed Slack selector against duplicate/missing/offline/malformed records and a secret sentinel. Both raw environment case variants are accepted only by Node; no full JSON enters the PowerShell parser. The native fixture now includes the problematic metadata pair and nested environment rather than status-only JSON.
- Reviewed reporting provenance: no raw env/dump object is returned or printed; configure-only CA is not called validated; runtime readiness is not inferred from receipts; saved status is emitted only after guarded verification; receipt persistence remains unchanged; no channel exchange/autostart claims. Failures before a verified receipt deliberately report source/build/runtime as unverified instead of guessing.
- Reviewed Windows native-argument compatibility and moved Node parsing to a file to avoid relying on inline quoted JavaScript under legacy `.cmd` argument handling.
- Native harness adds original-value/absence observation outside complete script calls; portable tests separately inspect actual finally behavior. Native execution still **NOT RUN**; actual Windows 5.1/7 new/upgrade runs, real CA propagation, and long/multiline/emoji Telegram exchanges require the previously approved acceptance workflow.
- Reboot/autostart and publication require separate explicit authorization. No attempt made to treat passing local tests as those gates.
- No architecture uncertainty requiring expansion remained. Controller's one scoped re-review is next; do not replay completed task waves.

## Controller final handoff — 2026-09-03

The final reviewer inspected `d3e32c9..a633c06` and marked all four actual findings ADDRESSED: legitimate Windows PM2 metadata, Node-only Slack selection, environment sentinel coverage, and allowlisted phase reporting. No new Critical/Important issue remained. The earlier shell recovery-quoting allegation was retracted after source verification; the quotes were already correct.

Independent controller verification at `a633c06e2ac04952c7392fd97572f2e507f013fd`:

```text
node --test test/installer/*.test.mjs slack-bridge/test/allowlist.test.js
tests 129; pass 128; fail 0; skipped 1; exit 0; duration 22540.056292 ms
bash -n nova-prereq.sh nova-init.sh
exit 0, no output
git diff --check
exit 0, no output
```

The same run included actual portable PowerShell selector/cleanup block tests. Parser checks additionally passed for `nova-prereq.ps1`, `nova-init.ps1`, and `test/installer/windows-entrypoints.test.ps1` using macOS PowerShell 7.6.5. IPC test permission was limited in purpose to the disposable test socket; no real service was accessed. Node was v25.9.0.

Verdict: approved for **local implementation handoff**, not production Windows acceptance. Native Windows PowerShell 5.1/7, Node20, real PM2/CA integration, short and long/multiline/emoji channel roundtrips and approved-reboot persistence remain **NOT RUN**. Publication, merge and PR still require a separate user decision.

Branch `fix/safe-engine-installer` and its worktree are retained. The base checkout `main` remained clean at `c2d2e2d`; no external write or student-machine operation was performed. Final documentation-only status updates do not change the tested executable code.
