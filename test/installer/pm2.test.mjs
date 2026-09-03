import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, appendFileSync, rmSync } from 'node:fs';
import { tmpdir, userInfo } from 'node:os';
import { join } from 'node:path';
import { rootCertificates } from 'node:tls';
const mod = await import('../../scripts/installer/pm2.mjs').catch(() => ({}));
for (const empty of [false, true]) {
    test(`Windows username metadata survives ${empty ? 'fresh start' : 'existing jlist and dump'} through guarded save`, async t => {
        const f = fixture(t, { empty, dump: !empty, record: { USERNAME: userInfo().username, env: { USERNAME: userInfo().username } } });
        if (empty) mkdirSync(join(f.stateRoot, 'logs'));
        const result = await mod.ensureRuntime(f.options, f.adapters);
        assert.equal(result.saved, true);
        assert.deepEqual(f.mutations.map(x => x.operation), [empty ? 'start' : 'restart', 'save']);
    });
}
for (const record of [
    { NODE_EXTRA_CA_CERTS: '/one', node_extra_ca_certs: '/one' },
    { env: { USERNAME: 'student', username: 'student' } },
    { env: { node_extra_ca_certs: '/one' } },
]) {
    test('metadata exception does not hide actual environment case conflicts ' + JSON.stringify(record), async t => {
        const f = fixture(t, { record });
        await assert.rejects(mod.ensureRuntime(f.options, f.adapters), { code: 'ENV_CASE_CONFLICT' });
        assert.deepEqual(f.mutations, []);
    });
}
test('readiness cannot save after its total deadline has elapsed',async t=>{
    const f=fixture(t);let elapsed=0,restarted=false;
    const original=f.adapters.run;
    f.adapters.now=()=>elapsed;
    f.adapters.run=(node,args,opts)=>{
        const result=original(node,args,opts);
        if(args[1]==='restart')restarted=true;
        else if(restarted)elapsed+=31000;
        return result;
    };
    await assert.rejects(mod.ensureRuntime(f.options,f.adapters),{code:'RUNTIME_READINESS_TIMEOUT'});
    assert.deepEqual(f.mutations.map(x=>x.operation),['restart']);
});
function fixture(t, change = {}) {
    const dir = mkdtempSync(join(tmpdir(), 'nova-pm2-'));
    t.after(() => rmSync(dir, { recursive: true, force: true }));
    const root = join(dir, 'engine'), stateRoot = join(dir, 'state'), home = join(dir, 'pm2');
    for (const p of [root, stateRoot, home]) {
        mkdirSync(p);
    }
    const ca = join(dir, 'ca.pem');
    writeFileSync(ca, rootCertificates[0]);
    const out = join(dir, 'out.log'), err = join(dir, 'err.log');
    writeFileSync(out, 'old\n');
    writeFileSync(err, '');
    writeFileSync(join(home, 'pm2.pid'), '88');
    writeFileSync(join(stateRoot, 'daemon.pid'), '101');
    const env = { PM2_HOME: home, NODE_EXTRA_CA_CERTS: ca };
    const base = { pm_id: 0, name: 'cortextos-daemon', pid: 101, pm2_env: { name: 'cortextos-daemon', status: 'online', pm_cwd: root, pm_exec_path: join(root, 'dist', 'daemon.js'), exec_interpreter: 'node', CTX_INSTANCE_ID: 'default', CTX_ROOT: stateRoot, CTX_FRAMEWORK_ROOT: root, CTX_PROJECT_ROOT: root, PM2_HOME: home, username: userInfo().username, restart_time: 0, pm_uptime: 1, pm_out_log_path: out, pm_err_log_path: err, NODE_EXTRA_CA_CERTS: ca } };
    let processes = change.empty ? [] : [base];
    if (change.empty) {
        rmSync(join(stateRoot, 'daemon.pid'));
    }
    if (change.record) {
        Object.assign(base.pm2_env, change.record);
    }
    if (change.dump) {
        writeFileSync(join(home, 'dump.pm2'), JSON.stringify([base.pm2_env]));
    }
    if (change.ambiguous) {
        processes.push({ ...base, pm_id: 1 });
    }
    if (change.other) {
        processes.push({ pm_id: 3, name: 'unrelated', pid: 999, pm2_env: { status: 'online' } });
    }
    const mutations = [];
    let lists = 0, now = 0, startedAgent = false;
    const adapters = { now: () => now, pipePresent: async () => false, isAlive: pid => pid === 88 || (!change.empty && pid === 101), resolveNodeTool: () => ({ node: process.execPath, script: '/fake/pm2' }), verifyEngine: async () => ({ schema: 1 }), probeTLS: async () => { }, sleep: async (ms) => { now += ms; }, requestIPC: async (request) => { if (request.type === 'start-agent') {
            startedAgent = true;
            return { success: true };
        } return { success: true, data: [{ name: 'boss', status: change.bossNever ? 'starting' : change.needsBoss && !startedAgent ? 'stopped' : 'running', pid: 303 }] }; }, run: (node, args, opts) => {
            assert.equal(node, process.execPath);
            assert.equal(args[0], '/fake/pm2');
            const op = args[1];
            if (op === 'jlist') {
                lists++;
                if (change.accessFail) {
                    throw Error('secret');
                }
                if (change.changedSet && lists === 2) {
                    processes.push({ pm_id: 8, name: 'late-app', pid: 808, pm2_env: { status: 'online' } });
                }
                return { stdout: JSON.stringify(processes) };
            }
            if (op === 'start') {
                mutations.push({ operation: op, args, env: opts.env });
                assert.equal(args[2], join(root, 'dist', 'daemon.js'));
                assert.deepEqual(args.slice(-3), ['--', '--instance', 'default']);
                processes = [base];
                base.pid = 102;
                Object.assign(base.pm2_env, { exec_interpreter: process.execPath, pm_out_log_path: args[args.indexOf('--output') + 1], pm_err_log_path: args[args.indexOf('--error') + 1] });
                writeFileSync(join(stateRoot, 'daemon.pid'), '102');
                writeFileSync(base.pm2_env.pm_out_log_path, '[daemon] Running (pid: 102)\n');
                writeFileSync(base.pm2_env.pm_err_log_path, '');
                return { stdout: '' };
            }
            if (op === 'restart') {
                mutations.push({ operation: op, target: Number(args[2]), env: opts.env });
                if (change.restartFail) {
                    throw Error('secret');
                }
                base.pid = 102;
                base.pm2_env.exec_interpreter = process.execPath;
                base.pm2_env.restart_time++;
                base.pm2_env.NODE_EXTRA_CA_CERTS = change.dropCA ? undefined : opts.env.NODE_EXTRA_CA_CERTS;
                writeFileSync(join(stateRoot, 'daemon.pid'), '102');
                appendFileSync(out, '[daemon] Running (pid: 102)\n');
                if (change.tlsError) {
                    appendFileSync(err, 'SELF_SIGNED_CERT_IN_CHAIN\n');
                }
                return { stdout: '' };
            }
            if (op === 'save') {
                mutations.push({ operation: op });
                const saved = processes.map(p => {
                    const env = { ...p.pm2_env };
                    delete env.pm_id;
                    delete env.instances;
                    delete env.prev_restart_delay;
                    return env;
                });
                writeFileSync(join(home, 'dump.pm2'), JSON.stringify(saved));
                return { stdout: '' };
            }
            throw Error('unexpected operation ' + op);
        } };
    return { options: { root, stateRoot, instance: 'default', env, org: 'test', channel: 'telegram', allowRestart: true, allowGlobalSave: true }, adapters, mutations, base, home, ca, stateRoot };
}
test('consented targeted restart installs approved CA and exact Node before one save', async (t) => { assert.equal(typeof mod.ensureRuntime, 'function'); const f = fixture(t); await mod.ensureRuntime(f.options, f.adapters); assert.deepEqual(f.mutations.map(x => x.operation), ['restart', 'save']); assert.equal(f.mutations[0].target, 0); assert.equal(f.mutations[0].env.NODE_EXTRA_CA_CERTS, f.ca); });
test('persistent PM2 dump without live pm_id validates successfully', async t => {
    const f = fixture(t);
    f.options.release = { sha: 'a'.repeat(40) };
    f.adapters.verifyEngine = async () => ({ root: f.options.root, sha: 'a'.repeat(40) });
    f.base.pm2_env.exec_interpreter = process.execPath;
    const result = await mod.guardedSave(f.options, f.adapters);
    assert.equal(result.saved, true);
    assert.equal(result.autoStartVerified, false);
    assert.deepEqual(result.outcome, {
        root: f.options.root, requestedSha: 'a'.repeat(40), sourceSha: 'a'.repeat(40),
        build: 'verified', ca: 'validated-propagated', daemon: 'verified-online',
        boss: 'verified-running', saved: true, saveReason: null,
        autoStartVerified: false, channelRoundtripVerified: false,
    });
    assert.deepEqual(f.mutations.map(x => x.operation), ['save']);
});
test('Boss becoming stopped during final health read cancels save', async t => {
    const f = fixture(t);
    f.base.pm2_env.exec_interpreter = process.execPath;
    let reads = 0;
    f.adapters.requestIPC = async () => ({ success: true, data: [{ name: 'boss', status: ++reads === 1 ? 'running' : 'stopped', pid: 303 }] });
    await assert.rejects(mod.guardedSave(f.options, f.adapters), { code: 'BOSS_NOT_RUNNING' });
    assert.deepEqual(f.mutations, []);
});
for (const field of ['username', 'PM2_HOME']) {
    for (const action of ['ensureRuntime', 'guardedSave']) {
        test(`${action} refuses missing authoritative ${field}`, async t => {
            const f = fixture(t);
            f.base.pm2_env.exec_interpreter = process.execPath;
            delete f.base.pm2_env[field];
            await assert.rejects(mod[action](f.options, f.adapters), { code: 'PM2_RECOVERY_REQUIRED' });
            assert.deepEqual(f.mutations, []);
        });
    }
}
for (const [name, change, options, code] of [
    ['dump without live daemon', { empty: true, dump: true }, {}, 'PM2_RECOVERY_REQUIRED'],
    ['ambiguous daemon', { ambiguous: true }, {}, 'PM2_AMBIGUOUS'],
    ['wrong root', { record: { CTX_FRAMEWORK_ROOT: '/wrong' } }, {}, 'PM2_IDENTITY_MISMATCH'],
    ['stale absolute interpreter', { record: { exec_interpreter: '/wrong/node' } }, {}, 'PM2_IDENTITY_MISMATCH'],
    ['stopped daemon', { record: { status: 'stopped' } }, {}, 'PM2_UNHEALTHY'],
    ['errored daemon', { record: { status: 'errored' } }, {}, 'PM2_UNHEALTHY'],
    ['TLS bypass', { record: { NODE_TLS_REJECT_UNAUTHORIZED: '0' } }, {}, 'TLS_BYPASS_REFUSED'],
    ['nested TLS bypass', { record: { env: { NODE_TLS_REJECT_UNAUTHORIZED: '0' } } }, {}, 'TLS_BYPASS_REFUSED'],
    ['nested CA disagreement', { record: { env: { NODE_EXTRA_CA_CERTS: '/different/ca.pem' } } }, {}, 'PM2_ENV_CONFLICT'],
    ['restart declined', {}, { allowRestart: false }, 'RESTART_CONSENT_REQUIRED'],
    ['PM2 read failure', { accessFail: true }, {}, 'PM2_ACCESS_FAILED'],
]) {
    test(name + ' refuses without mutations', async (t) => { assert.equal(typeof mod.ensureRuntime, 'function'); const f = fixture(t, change); await assert.rejects(mod.ensureRuntime({ ...f.options, ...options }, f.adapters), { code }); assert.deepEqual(f.mutations, []); });
}
for (const [name, change, code] of [['failed restart', { restartFail: true }, 'PM2_MUTATION_FAILED'], ['CA lost after restart', { dropCA: true }, 'PM2_CA_MISMATCH'], ['fresh TLS error', { tlsError: true }, 'RUNTIME_TLS_ERROR']]) {
    test(name + ' never saves', async (t) => { assert.equal(typeof mod.ensureRuntime, 'function'); const f = fixture(t, change); await assert.rejects(mod.ensureRuntime(f.options, f.adapters), { code }); assert.deepEqual(f.mutations.map(x => x.operation), ['restart']); });
}
test('global save requires consent and does not save an unhealthy daemon', async (t) => { assert.equal(typeof mod.guardedSave, 'function'); const f = fixture(t, { other: true }); f.base.pm2_env.exec_interpreter = process.execPath; await assert.rejects(mod.guardedSave({ ...f.options, allowGlobalSave: false }, f.adapters), { code: 'GLOBAL_SAVE_CONSENT_REQUIRED' }); assert.deepEqual(f.mutations, []); });
test('absent PM2 pid never invokes a PM2 client during read-only inspection', async (t) => { assert.equal(typeof mod.inspectRuntime, 'function'); const f = fixture(t, { empty: true }); rmSync(join(f.home, 'pm2.pid')); f.adapters.run = () => { throw Error('must not call PM2'); }; const result = await mod.inspectRuntime(f.options, f.adapters); assert.equal(result.selected, null); });
test('fresh daemon starts explicit script and waits for Boss running before save', async (t) => { const f = fixture(t, { empty: true, needsBoss: true }); mkdirSync(join(f.stateRoot, 'logs')); await mod.ensureRuntime(f.options, f.adapters); assert.deepEqual(f.mutations.map(x => x.operation), ['start', 'save']); });
test('asynchronous start-agent acknowledgement without running Boss never saves', async (t) => { const f = fixture(t, { bossNever: true }); await assert.rejects(mod.ensureRuntime(f.options, f.adapters), { code: 'BOSS_NOT_RUNNING' }); assert.deepEqual(f.mutations.map(x => x.operation), ['restart']); });
test('changed process set cancels save', async (t) => { const f = fixture(t, { changedSet: true }); f.base.pm2_env.exec_interpreter = process.execPath; await assert.rejects(mod.guardedSave(f.options, f.adapters), { code: 'PM2_PROCESS_SET_CHANGED' }); assert.deepEqual(f.mutations, []); });
test('unmanaged IPC and mismatched Windows PM2 pipe refuse without jlist', async (t) => { for (const platform of ['darwin', 'win32']) {
    const f = fixture(t, { empty: true });
    rmSync(join(f.home, 'pm2.pid'));
    f.adapters.platform = platform;
    f.adapters.pipePresent = async () => true;
    f.adapters.run = () => { throw Error('must not invoke PM2'); };
    await assert.rejects(mod.inspectRuntime(f.options, f.adapters), { code: platform === 'win32' ? 'PM2_HOME_MISMATCH' : 'UNMANAGED_DAEMON' });
} });
test('standalone save revalidates receipt before any PM2 save', async (t) => { const f = fixture(t); f.base.pm2_env.exec_interpreter = process.execPath; f.adapters.verifyEngine = async () => { throw Object.assign(Error('bad receipt'), { code: 'BAD_RECEIPT' }); }; await assert.rejects(mod.guardedSave(f.options, f.adapters), { code: 'BAD_RECEIPT' }); assert.deepEqual(f.mutations, []); });
test('saved healthy snapshot must retain exact daemon identity fields', async (t) => { const f = fixture(t); f.base.pm2_env.exec_interpreter = process.execPath; const original = f.adapters.run; f.adapters.run = (node, args, opts) => { const result = original(node, args, opts); if (args[1] === 'save') {
    writeFileSync(join(f.home, 'dump.pm2'), JSON.stringify([{ ...f.base.pm2_env, CTX_ROOT: '/wrong' }]));
} return result; }; await assert.rejects(mod.guardedSave(f.options, f.adapters), { code: 'PM2_IDENTITY_MISMATCH' }); });
test('unrelated process change during restart invalidates global save consent', async (t) => { const f = fixture(t, { other: true }); const original = f.adapters.run; let restarted = false; f.adapters.run = (node, args, opts) => { const result = original(node, args, opts); if (args[1] === 'restart') {
    restarted = true;
} if (args[1] === 'jlist' && restarted) {
    const records = JSON.parse(result.stdout);
    records[1].pid = 1000;
    result.stdout = JSON.stringify(records);
} return result; }; await assert.rejects(mod.ensureRuntime(f.options, f.adapters), { code: 'PM2_PROCESS_SET_CHANGED' }); assert.deepEqual(f.mutations.map(x => x.operation), ['restart']); });
test('public readProcesses refuses to auto-launch absent PM2 daemon', async (t) => { const f = fixture(t, { empty: true }); rmSync(join(f.home, 'pm2.pid')); let called = false; f.adapters.run = () => { called = true; return { stdout: '[]' }; }; await assert.rejects(mod.readProcesses({ ...f.adapters, options: f.options }), { code: 'PM2_NOT_RUNNING' }); assert.equal(called, false); });
for (const [name, action, code] of [
    ['truncated log', f => writeFileSync(f.base.pm2_env.pm_out_log_path, ''), 'RUNTIME_LOGS_AMBIGUOUS'],
    ['rotated log', f => { const path = f.base.pm2_env.pm_out_log_path; rmSync(path); writeFileSync(path, '[daemon] Running (pid: 102)\n'); }, 'RUNTIME_LOGS_AMBIGUOUS'],
    ['missing bootstrap', f => writeFileSync(f.base.pm2_env.pm_out_log_path, 'old\nNo ready evidence\n'), 'RUNTIME_BOOTSTRAP_MISSING'],
]) {
    test(name + ' blocks save', async (t) => { const f = fixture(t); const original = f.adapters.run; f.adapters.run = (node, args, opts) => { const result = original(node, args, opts); if (args[1] === 'restart') {
        action(f);
    } return result; }; await assert.rejects(mod.ensureRuntime(f.options, f.adapters), { code }); assert.deepEqual(f.mutations.map(x => x.operation), ['restart']); });
}
